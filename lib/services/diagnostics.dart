/// Holder for non fatal startup errors caught at boot, so they can be
/// shown inside the app for debugging without adb or logcat.
class Diagnostics {
  static String? audioServiceError;
}
