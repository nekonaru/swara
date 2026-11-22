import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_effects_service.dart';

/// Outcome of a version check against the GitHub releases feed.
enum UpdateOutcome { updateAvailable, upToDate, error }

/// Immutable result of [UpdateService.checkForUpdate]. [downloadUrl] and
/// [tagName] are only set for [UpdateOutcome.updateAvailable].
class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.outcome,
    this.tagName,
    this.downloadUrl,
    this.downloadDigest,
    this.downloadSize,
    this.currentVersion,
  });

  final UpdateOutcome outcome;
  final String? tagName;
  final String? downloadUrl;
  // SHA-256 hex digest of the chosen asset as published by GitHub
  // ("sha256:…" stripped), when the API provides one.
  final String? downloadDigest;
  // Asset size in bytes as published by GitHub, when available; used to
  // catch truncated downloads when the server omits Content-Length.
  final int? downloadSize;
  final String? currentVersion;

  const UpdateCheckResult.available({
    required String tagName,
    required String downloadUrl,
    String? downloadDigest,
    int? downloadSize,
    required String currentVersion,
  }) : this._(
          outcome: UpdateOutcome.updateAvailable,
          tagName: tagName,
          downloadUrl: downloadUrl,
          downloadDigest: downloadDigest,
          downloadSize: downloadSize,
          currentVersion: currentVersion,
        );

  const UpdateCheckResult.upToDate() : this._(outcome: UpdateOutcome.upToDate);
  const UpdateCheckResult.error() : this._(outcome: UpdateOutcome.error);
}

/// Thin wrapper around the public GitHub releases API for nekonaru/swara.
///
/// Everything here is read-only and unauthenticated; GitHub allows 60
/// requests per hour per IP, which is plenty for an on-demand check.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String _latestUrl =
      'https://api.github.com/repos/nekonaru/swara/releases/latest';
  static const Duration _timeout = Duration(seconds: 10);

  // Set by the progress dialog's Cancel action; checked by the streaming
  // loop so a cancelled download aborts and deletes the partial file.
  bool _cancelRequested = false;

  /// True when the last download ended because the user tapped Cancel.
  bool lastDownloadCancelled = false;

  /// Ask the in-flight download to abort. Safe to call even when no
  /// download is running; takes effect on the next chunk boundary.
  void cancelDownload() => _cancelRequested = true;

  /// Fetch the latest release and compare it against the installed version.
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final res = await http.get(
        Uri.parse(_latestUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Swara-update-check',
        },
      ).timeout(_timeout);
      if (res.statusCode != 200) return const UpdateCheckResult.error();

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final tagName = (body['tag_name'] as String?)?.trim() ?? '';
      if (tagName.isEmpty) return const UpdateCheckResult.error();

      final abis = await AudioEffectsService.instance.deviceAbi();
      final assets = (body['assets'] as List?) ?? const [];
      final picked = _pickApkAsset(assets, abis);
      if (picked == null) return const UpdateCheckResult.error();

      final current = (await PackageInfo.fromPlatform()).version;
      final newer = compareVersions(tagName, current) > 0;
      if (!newer) return const UpdateCheckResult.upToDate();
      return UpdateCheckResult.available(
        tagName: tagName,
        downloadUrl: picked.$1,
        downloadDigest: _normalizeDigest(picked.$2),
        downloadSize: picked.$3,
        currentVersion: current,
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
      return const UpdateCheckResult.error();
    }
  }

  /// Strip the "sha256:" prefix GitHub prepends to asset digests. Returns
  /// null when the digest is missing or malformed.
  static String? _normalizeDigest(String? digest) {
    if (digest == null) return null;
    final match = RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(digest.trim());
    return match?.group(1)?.toLowerCase();
  }

  /// Download the update APK into the app cache under `updates/`, returning
  /// (path, verified, mismatch). (null, false, true) on digest mismatch,
  /// (null, false, false) on any other failure. [onProgress] reports
  /// 0.0..1.0 when the total size is known, or -1 when it is not. When
  /// [digest] (SHA-256 hex) is provided the file is verified against it on
  /// Android; a mismatch discards the download. [expectedSize], when known
  /// from the release manifest, is used to catch short downloads when the
  /// server omits Content-Length.
  Future<(String?, bool, bool)> downloadApk(
    String url, {
    String? digest,
    int? expectedSize,
    void Function(double progress)? onProgress,
  }) async {
    _cancelRequested = false;
    lastDownloadCancelled = false;
    late File apkFile;
    try {
      final docs = await getTemporaryDirectory();
      final dir = Directory('${docs.path}/updates');
      await dir.create(recursive: true);
      apkFile = File('${dir.path}/swara-update.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(url))
          ..headers['User-Agent'] = 'Swara-update-check';
        final res = await client.send(req).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) return (null, false, false);

        final headerTotal = res.contentLength ?? 0;
        final total = headerTotal > 0
            ? headerTotal
            : (expectedSize ?? 0).clamp(0, 1 << 30);
        var received = 0;
        final sink = apkFile.openWrite();
        try {
          await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
            if (_cancelRequested) {
              break;
            }
            received += chunk.length;
            onProgress?.call(total > 0 ? received / total : -1);
            sink.add(chunk);
          }
        } finally {
          await sink.close();
        }
        if (_cancelRequested) {
          try {
            await apkFile.delete();
          } catch (_) {
            // A missing file is fine; the cancel path does not need it.
          }
          lastDownloadCancelled = true;
          return (null, false, false);
        }
        if (!await apkFile.exists() || await apkFile.length() == 0) return (null, false, false);
        // A truncated (but nonzero) download is worse than no download: the
        // installer would fail with a parse error and no feedback. When the
        // size is known, insist on an exact match.
        if (total > 0 && await apkFile.length() != total) {
          debugPrint('Update download truncated: got ${await apkFile.length()} of $total bytes');
          await apkFile.delete();
          return (null, false, false);
        }
        // Verify the APK against the SHA-256 digest published on the GitHub
        // asset before letting the installer open it. Anything unexpected
        // deletes the partial apkFile: no silent uninstalls, no surprises.
        var verified = false;
        if (digest != null) {
          final hex = await AudioEffectsService.instance.sha256(apkFile.path);
          if (hex == null) {
            debugPrint('Update APK digest could not be computed');
            await apkFile.delete();
            return (null, false, false);
          }
          if (hex != digest) {
            debugPrint('Update APK digest mismatch: expected $digest, got $hex');
            await apkFile.delete();
            return (null, false, true);
          }
          verified = true;
        }
        return (apkFile.path, verified, false);
      } finally {
        client.close();
      }
    } catch (e) {
      // Delete any partial file so the next attempt starts clean and the
      // cache never holds a half-written APK.
      try {
        await apkFile.delete();
      } catch (_) {}
      debugPrint('Update download failed: $e');
      return (null, false, false);
    }
  }

  /// Pick the APK asset to install, matching the device's ABI. Returns the
  /// asset URL, the GitHub-published SHA-256 digest ("sha256:…" stripped)
  /// when available, and the asset size in bytes when available.
  (String, String?, int?)? _pickApkAsset(List assets, List<String> abis) {
    // Without an ABI report, guessing arm64 can hand a 32-bit device an
    // incompatible split. Fail closed instead.
    if (abis.isEmpty) return null;
    final lower = abis.map((a) => a.toLowerCase()).toSet();
    final wantsArm64 = lower.contains('arm64-v8a');
    final wantsArmv7 = lower.contains('armeabi-v7a') &&
        !lower.contains('arm64-v8a') &&
        !lower.contains('x86_64');

    // Preference order per device class. x86_64 desktop-class environments
    // fall back to arm64, mirroring what CI builds and publishes.
    (String, String?, int?)? arm64Pick;
    (String, String?, int?)? armv7Pick;
    (String, String?, int?)? x86_64Pick;
    (String, String?, int?)? anyPick;

    for (final raw in assets) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String?)?.toLowerCase() ?? '';
      final url = raw['browser_download_url'] as String?;
      final digest = raw['digest'] as String?;
      // GitHub's asset object carries a `size` in bytes; use it to catch
      // truncated downloads when the HTTP response omits Content-Length.
      final size = raw['size'] is num ? (raw['size'] as num).toInt() : null;
      if (url == null || !name.endsWith('.apk')) continue;
      final pick = (url, digest, size);
      anyPick ??= pick;
      if (name == 'app-arm64-v8a-release.apk') arm64Pick = pick;
      if (name == 'app-armeabi-v7a-release.apk') armv7Pick = pick;
      if (name == 'app-x86_64-release.apk') x86_64Pick = pick;
    }
    if (lower.contains('x86_64')) return x86_64Pick ?? arm64Pick ?? armv7Pick ?? anyPick;
    if (wantsArm64) return arm64Pick ?? armv7Pick ?? x86_64Pick ?? anyPick;
    if (wantsArmv7) return armv7Pick ?? arm64Pick ?? x86_64Pick ?? anyPick;
    if (arm64Pick != null) return arm64Pick;
    if (armv7Pick != null) return armv7Pick;
    return anyPick;
  }

  /// Compare two semver-ish version strings like `v3.10.0` and `3.4.0`.
  /// Returns >0 when [a] is newer, <0 when [b] is newer, 0 when equal.
  static int compareVersions(String a, String b) {
    List<int> parse(String v) => v
        .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
        .split('.')
        .map((part) {
          // Strip any build-metadata suffix like "+48".
          final digits = RegExp(r'^\d+').firstMatch(part.trim());
          return digits == null ? 0 : int.parse(digits.group(0)!);
        })
        .toList();
    final pa = parse(a);
    final pb = parse(b);
    final length = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
