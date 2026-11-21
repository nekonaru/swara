import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time audio/notification permission prompt, shared by the onboarding
/// finish action and the home screen for returning users. Asking during the
/// intro animation would pause the splash and make the handoff stutter.
class PermissionService {
  PermissionService._();

  static const String askedKey = 'essential_permissions_asked';

  static Future<void> ensureEssentialPermissions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(askedKey) ?? false) return;
      if (!await Permission.audio.isGranted) {
        await Permission.audio.request();
      }
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }
      // Persist only after both requests returned: a throw must not suppress
      // the prompts on every later launch.
      await prefs.setBool(askedKey, true);
    } catch (e) {
      // Permission prompts are best effort; the app stays usable without.
    }
  }
}
