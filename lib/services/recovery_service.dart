import 'package:on_audio_query/on_audio_query.dart';

import 'db_helper.dart';
import 'snapshot_service.dart';

/// Detects a library that is much smaller than the newest local snapshot and
/// offers a one-time recovery before the startup scan can rewrite the DB.
class RecoveryService {
  RecoveryService._();
  static final RecoveryService instance = RecoveryService._();

  Future<bool> shouldOffer() async {
    try {
      if (await SnapshotService.autoRestoreOffered()) return false;
      final snapshotCount = await SnapshotService.instance.latestSongCount();
      if (snapshotCount < 10) return false;
      // A scan no longer prunes rows, so the DB count alone cannot show loss.
      // Compare the stored ids with what MediaStore still reports instead.
      final tracks = await OnAudioQuery().querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );
      final deviceIds = tracks.map((t) => t.id).toSet();
      if (deviceIds.isEmpty) return false;
      final rows = await (await DBHelper.instance.db)
          .query('songs', columns: ['id']);
      final dbIds = rows
          .map((r) => (r['id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      final missing = dbIds.difference(deviceIds).length;
      if (missing < 5) return false;
      return missing >= (dbIds.length * 0.1).round() &&
          snapshotCount > deviceIds.length;
    } catch (_) {
      // Recovery is optional; a failed check must never block startup.
      return false;
    }
  }

  Future<void> markOffered() async {
    try {
      await SnapshotService.markAutoRestoreOffered();
    } catch (_) {}
  }
}
