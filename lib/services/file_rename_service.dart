import 'package:flutter/services.dart';

/// Dart facade for the native file rename bridge.
enum FileRenameStatus {
  renamed,
  noPermission,
  consentDenied,
  targetExists,
  notFound,
  unsupported,
  failed,
}

class FileRenameResult {
  final FileRenameStatus status;
  final String? path;
  final String? displayName;
  final String? error;

  const FileRenameResult({
    required this.status,
    this.path,
    this.displayName,
    this.error,
  });
}

class FileRenameService {
  FileRenameService._();
  static final FileRenameService instance = FileRenameService._();

  static const String channelName = 'swara/file_rename';
  final MethodChannel _channel = const MethodChannel(channelName);

  Future<FileRenameResult> rename({
    required int id,
    required String oldPath,
    required String newDisplayName,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('rename', {
        'id': id,
        'oldPath': oldPath,
        'newDisplayName': newDisplayName,
      });
      if (raw == null) {
        return const FileRenameResult(status: FileRenameStatus.failed);
      }
      return FileRenameResult(
        status: FileRenameStatus.renamed,
        path: raw['path'] as String?,
        displayName: raw['displayName'] as String?,
      );
    } on PlatformException catch (e) {
      final status = switch (e.code) {
        'no_permission' => FileRenameStatus.noPermission,
        'consent_denied' => FileRenameStatus.consentDenied,
        'target_exists' => FileRenameStatus.targetExists,
        'not_found' => FileRenameStatus.notFound,
        _ => FileRenameStatus.failed,
      };
      return FileRenameResult(status: status, error: e.message);
    } on MissingPluginException {
      return const FileRenameResult(status: FileRenameStatus.unsupported);
    } catch (e) {
      return FileRenameResult(
          status: FileRenameStatus.failed, error: e.toString());
    }
  }
}
