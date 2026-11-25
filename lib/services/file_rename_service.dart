import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

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
  // True when the OS already renamed the file even if the DB update failed.
  final bool fileRenamed;

  const FileRenameResult({
    required this.status,
    this.path,
    this.displayName,
    this.error,
    this.fileRenamed = false,
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
    // Legacy Android needs WRITE_EXTERNAL_STORAGE for File.renameTo. On
    // scoped storage this request is harmless and the native side asks for
    // per-item consent instead.
    if (Platform.isAndroid) {
      final sdk = await _channel.invokeMethod<int>('getSdkInt') ?? 0;
      // WRITE_EXTERNAL_STORAGE is only meaningful up to API 29. On newer
      // versions the native side asks for per-item MediaStore consent.
      if (sdk <= 29) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          return const FileRenameResult(status: FileRenameStatus.noPermission);
        }
      }
    }
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
