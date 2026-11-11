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
    this.currentVersion,
  });

  final UpdateOutcome outcome;
  final String? tagName;
  final String? downloadUrl;
  final String? currentVersion;

  const UpdateCheckResult.available({
    required String tagName,
    required String downloadUrl,
    required String currentVersion,
  }) : this._(
          outcome: UpdateOutcome.updateAvailable,
          tagName: tagName,
          downloadUrl: downloadUrl,
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
      final downloadUrl = _pickApkAsset(assets, abis);
      if (downloadUrl == null) return const UpdateCheckResult.error();

      final current = (await PackageInfo.fromPlatform()).version;
      final newer = compareVersions(tagName, current) > 0;
      if (!newer) return const UpdateCheckResult.upToDate();
      return UpdateCheckResult.available(
        tagName: tagName,
        downloadUrl: downloadUrl,
        currentVersion: current,
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
      return const UpdateCheckResult.error();
    }
  }

  /// Download the update APK into the app cache under `updates/`, returning
  /// the file path on success or null on any failure. [onProgress] reports
  /// 0.0..1.0 when the total size is known, or -1 when it is not.
  Future<String?> downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final docs = await getTemporaryDirectory();
      final dir = Directory('${docs.path}/updates');
      await dir.create(recursive: true);
      final file = File('${dir.path}/swara-update.apk');
      if (await file.exists()) {
        await file.delete();
      }

      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(url))
          ..headers['User-Agent'] = 'Swara-update-check';
        final res = await client.send(req).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) return null;

        final total = res.contentLength ?? 0;
        var received = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in res.stream) {
            received += chunk.length;
            onProgress?.call(total > 0 ? received / total : -1);
            sink.add(chunk);
          }
        } finally {
          await sink.close();
        }
        if (!await file.exists() || await file.length() == 0) return null;
        return file.path;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Update download failed: $e');
      return null;
    }
  }

  /// Pick the APK asset to install, matching the device's ABI.
  String? _pickApkAsset(List assets, List<String> abis) {
    final lower = abis.map((a) => a.toLowerCase()).toSet();
    final wantsArm64 = lower.contains('arm64-v8a');
    final wantsArmv7 = lower.contains('armeabi-v7a') &&
        !lower.contains('arm64-v8a') &&
        !lower.contains('x86_64');

    // Preference order per device class. x86_64 builds ship from v1.8.1 only;
    // everywhere else falls back to the newest available compatible APK.
    String? arm64Url;
    String? armv7Url;
    String? x86_64Url;
    String? anyUrl;

    for (final raw in assets) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String?)?.toLowerCase() ?? '';
      final url = raw['browser_download_url'] as String?;
      if (url == null || !name.endsWith('.apk')) continue;
      anyUrl ??= url;
      if (name == 'app-arm64-v8a-release.apk') arm64Url = url;
      if (name == 'app-armeabi-v7a-release.apk') armv7Url = url;
      if (name == 'app-x86_64-release.apk') x86_64Url = url;
    }
    if (lower.contains('x86_64')) return x86_64Url ?? arm64Url ?? armv7Url ?? anyUrl;
    if (wantsArm64) return arm64Url ?? armv7Url ?? x86_64Url ?? anyUrl;
    if (wantsArmv7) return armv7Url ?? arm64Url ?? x86_64Url ?? anyUrl;
    if (arm64Url != null) return arm64Url;
    if (armv7Url != null) return armv7Url;
    return anyUrl;
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
