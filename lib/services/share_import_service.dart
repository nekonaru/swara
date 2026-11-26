import 'package:flutter/services.dart';

/// Bridge for audio files shared into Swara from other apps.
class ShareImportService {
  ShareImportService._();
  static final ShareImportService instance = ShareImportService._();

  static const MethodChannel channel = MethodChannel('swara/share_import');

  Future<List<String>> getInitialImport() async {
    try {
      final raw = await channel.invokeListMethod<String>('getInitialImport');
      return raw ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  Future<({int imported, int skipped, int failed})> importUris(
      List<String> uris) async {
    if (uris.isEmpty) return (imported: 0, skipped: 0, failed: 0);
    try {
      final raw = await channel.invokeMapMethod<String, dynamic>(
        'importAudioFiles',
        uris,
      );
      if (raw == null) return (imported: 0, skipped: 0, failed: uris.length);
      return (
        imported: (raw['imported'] as num?)?.toInt() ?? 0,
        skipped: (raw['skipped'] as num?)?.toInt() ?? 0,
        failed: (raw['failed'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return (imported: 0, skipped: 0, failed: uris.length);
    } catch (_) {
      // Missing plugin or a malformed platform reply must not become an
      // unhandled error in the OS callback.
      return (imported: 0, skipped: 0, failed: uris.length);
    }
  }
}
