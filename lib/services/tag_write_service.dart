import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum TagWriteStatus {
  written,
  dbOnly,
  noPermission,
  consentDenied,
  notFound,
  updateFailed,
  unsupported,
  failed,
}

class TagWriteResult {
  final TagWriteStatus status;
  final List<String> fields;
  final String? error;

  const TagWriteResult({
    required this.status,
    this.fields = const <String>[],
    this.error,
  });

  bool get osWritten => status == TagWriteStatus.written;
}

class TagWriteService {
  TagWriteService._();
  static final TagWriteService instance = TagWriteService._();

  static const String channelName = 'swara/file_rename';
  final MethodChannel _channel = const MethodChannel(channelName);

  Future<TagWriteResult> writeTags({
    required int id,
    required String filePath,
    required String title,
    required String artist,
    required String album,
  }) async {
    if (Platform.isAndroid) {
      final sdk = await _channel.invokeMethod<int>('getSdkInt') ?? 0;
      if (sdk <= 29) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          return const TagWriteResult(status: TagWriteStatus.noPermission);
        }
      }
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('writeTags', {
        'id': id,
        'filePath': filePath,
        'title': title,
        'artist': artist,
        'album': album,
      });
      if (raw == null) {
        return const TagWriteResult(status: TagWriteStatus.failed);
      }
      return TagWriteResult(
        status: TagWriteStatus.written,
        fields: (raw['fields'] as List? ?? const []).cast<String>(),
      );
    } on PlatformException catch (e) {
      final status = switch (e.code) {
        'no_permission' => TagWriteStatus.noPermission,
        'consent_denied' => TagWriteStatus.consentDenied,
        'not_found' => TagWriteStatus.notFound,
        'update_failed' => TagWriteStatus.updateFailed,
        _ => TagWriteStatus.failed,
      };
      return TagWriteResult(status: status, error: e.message);
    } on MissingPluginException {
      return const TagWriteResult(status: TagWriteStatus.unsupported);
    } catch (e) {
      return TagWriteResult(status: TagWriteStatus.failed, error: e.toString());
    }
  }
}
