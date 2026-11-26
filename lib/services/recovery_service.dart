import 'package:shared_preferences/shared_preferences.dart';

import 'db_helper.dart';
import 'snapshot_service.dart';

/// Detects a library that is much smaller than the newest local snapshot and
/// offers a one-time recovery before the startup scan can rewrite the DB.
class RecoveryService {
  RecoveryService._();
  static final RecoveryService instance = RecoveryService._();

  static const String offeredKey = 'recovery_offer_done';

  Future<bool> shouldOffer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(offeredKey) ?? false) return false;
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(offeredKey, true);
    } catch (_) {}
  }
}
