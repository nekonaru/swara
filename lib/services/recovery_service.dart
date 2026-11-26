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
      final current = await DBHelper.instance.getSongCount();
      return current < (snapshotCount * 0.7).round();
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
