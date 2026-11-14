import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/language_provider.dart';
import 'providers/library_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/theme_provider.dart';
import 'services/db_helper.dart';
import 'services/equalizer_service.dart';
import 'services/player_service.dart';
import 'services/swara_audio_handler.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Persist the playback position whenever the app is pushed to the
  // background, so a cold start resumes at the same minute:second.
  WidgetsBinding.instance.addObserver(_SwaraLifecycleObserver());
  // Handle widget button taps from native. Deferred to the first frame so
  // the engine is fully configured when the handler registers.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _WidgetBridge.init();
  });
  // Ask for the two permissions the app needs, right at first launch
  // instead of later in the onboarding or first scan flow. Only asked once.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_requestEssentialPermissions());
  });

  // Cap the in-memory image cache because the library can hold 2600 songs
  // with artwork, so unbounded cached art can spike memory on scroll.
  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 << 20;

  final themeProvider = ThemeProvider();
  final languageProvider = LanguageProvider.instance;

  // Start all independent init tasks in parallel and paint first frame
  // immediately, so the user sees the splash instead of a black screen.
  final bootFuture = _bootApp(
    themeProvider: themeProvider,
    languageProvider: languageProvider,
  );
  // Widget actions from the home-screen widget need the boot work (playback
  // restore) to be done first, otherwise a cold start from the widget would
  // find an empty queue and swallow the tap.
  _WidgetBridge.bootFuture = bootFuture;

  runApp(MusicApp(
    themeProvider: themeProvider,
    languageProvider: languageProvider,
    bootFuture: bootFuture,
  ));

  // Register dynamic launcher shortcuts (long press on the app icon).
  // Best effort: a shortcut failure must never crash or block the app.
  _setupDynamicShortcuts();
}

// Keys for the one-time essential permission prompt shown at first launch.
const String _essentialPermissionsAskedKey = 'essential_permissions_asked';

// Ask for audio (music files) and notification permission once, at app open.
// Whether the user allows or denies, the prompt never repeats on its own;
// permission_handler shows nothing when the permission is already granted.
Future<void> _requestEssentialPermissions() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_essentialPermissionsAskedKey) ?? false) return;
    await prefs.setBool(_essentialPermissionsAskedKey, true);

    if (!await Permission.audio.isGranted) {
      final status = await Permission.audio.request();
      debugPrint('Swara: audio permission result: $status');
    }
    if (!await Permission.notification.isGranted) {
      final status = await Permission.notification.request();
      debugPrint('Swara: notification permission result: $status');
    }
  } catch (e) {
    debugPrint('Swara: essential permission request failed: $e');
  }
}

// Home screen widget bridge. Receives button taps from the native widget
// provider and forwards them to the player, and pushes the current
// title/artist/playing state to the widget on every playback change.
class _WidgetBridge {
  static const MethodChannel _channel = MethodChannel('swara/widget');
  static bool _initialized = false;
  // Set to the in-flight boot future by main() so a widget tap launched
  // from a dead process dispatches after the playback restore finishes.
  static Future<void>? bootFuture;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_onNativeCall);
    try {
      // Cold start launched from a widget tap while the process was dead:
      // replay the action that started us.
      final initial = await _channel.invokeMethod<String>('getInitialAction');
      if (initial != null && initial.isNotEmpty) {
        _handleAction(initial);
      }
    } catch (e) {
      debugPrint('Widget initial action read failed: $e');
    }
  }

  static Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onWidgetAction') {
      final action = call.arguments;
      if (action is String) _handleAction(action);
    }
    return null;
  }

  static Future<void> _handleAction(String action) async {
    // Wait for the boot work (which restores playback state) before acting,
    // otherwise a tap that launched the app would hit an empty queue.
    try {
      await _WidgetBridge.bootFuture;
    } catch (_) {
      // Boot failures are logged at the call site; act anyway.
    }
    final service = PlayerService.instance;
    switch (action) {
      case 'swara.widget.TOGGLE':
        unawaited(service.togglePlayPause());
        break;
      case 'swara.widget.NEXT':
        unawaited(service.next());
        break;
      case 'swara.widget.PREV':
        unawaited(service.smartPrevious());
        break;
    }
  }

  static Future<void> pushState(String title, String artist, bool playing) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'title': title,
        'artist': artist,
        'playing': playing,
      });
    } catch (e) {
      debugPrint('Widget state push failed: $e');
    }
  }
}

// Saves the playback position when the app is backgrounded, so a cold start
// resumes paused at the exact minute:second the user left off.
class _SwaraLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      PlayerService.instance.saveResumeStateNow();
    }
  }
}

// Registers dynamic launcher shortcuts and handles their callbacks.
// Needs the quick_actions package (see report). Uses only existing APIs:
// DBHelper.getFavorites / getRecentlyPlayed for data and
// PlayerService.setShuffle / setQueueAndPlay for playback.
// NOTE: quick_actions API shape below follows the plugin standard
// (QuickActions setShortcutItems + initialize callback) but is not
// verified against a resolved version in this repo, so confirm on upgrade.
// No native code or manifest change is needed for dynamic shortcuts.
void _setupDynamicShortcuts() {
  try {
    const QuickActions quickActions = QuickActions();
    quickActions.initialize((String shortcutType) {
      _handleAppShortcut(shortcutType);
    });
    quickActions.setShortcutItems(<ShortcutItem>[
      ShortcutItem(
        type: 'shuffle_favorites',
        localizedTitle:
            lookupAppLocalizations(LanguageProvider.instance.locale)
                .shortcutShuffle,
        icon: 'ic_stat_swara',
      ),
      ShortcutItem(
        type: 'continue_listening',
        localizedTitle:
            lookupAppLocalizations(LanguageProvider.instance.locale)
                .shortcutContinue,
        icon: 'ic_stat_swara',
      ),
    ]);
  } catch (e) {
    // Shortcuts are optional, so log and keep the app running normally.
    debugPrint('App shortcuts setup failed: $e');
  }
}

// Runs the action for a launcher shortcut type. Everything is best effort:
// empty results are ignored and errors are only logged.
Future<void> _handleAppShortcut(String shortcutType) async {
  try {
    // Make sure the player listeners exist (init is idempotent, so calling
    // it again after a cold start via shortcut is safe).
    await PlayerService.instance.init();
    if (shortcutType == 'shuffle_favorites') {
      final favs = await DBHelper.instance.getFavorites();
      if (favs.isEmpty) return;
      // Enable shuffle BEFORE building the queue so setQueueAndPlay
      // creates a shuffled play order starting from the first song.
      PlayerService.instance.setShuffle(true);
      await PlayerService.instance.setQueueAndPlay(favs, 0);
    } else if (shortcutType == 'continue_listening') {
      final recent =
          await DBHelper.instance.getRecentlyPlayed(limit: 20);
      if (recent.isEmpty) return;
      // Queue the history in recency order and start with the most
      // recently played song (index 0).
      PlayerService.instance.setShuffle(false);
      await PlayerService.instance.setQueueAndPlay(recent, 0);
    }
  } catch (e) {
    debugPrint('App shortcut "$shortcutType" failed: $e');
  }
}

// Runs independent startup tasks concurrently. Each task guards its own
// failure so one failing init never blocks the others or the app launch.
// PlayerService and AudioService are safe to start together: the audio
// handler only attaches a listener to the existing PlayerService singleton
// and reads its state lazily at runtime.
// Subscribe to playback state and mirror it into the home screen widget.
void _startWidgetStatePush() {
  var lastTitle = '';
  var lastArtist = '';
  var lastPlaying = false;
  var hasPushed = false;

  Future<void> push() async {
    final service = PlayerService.instance;
    final song = service.currentSong;
    final title = song?.title ?? 'Swara';
    final artist = song?.artist ?? '';
    final playing = song != null && service.player.playing;
    // Push only on real state transitions, not on every notification
    // (speed/pitch slider drags would otherwise rebind the widget 60 times
    // per second).
    if (hasPushed &&
        title == lastTitle &&
        artist == lastArtist &&
        playing == lastPlaying) {
      return;
    }
    lastTitle = title;
    lastArtist = artist;
    lastPlaying = playing;
    hasPushed = true;
    await _WidgetBridge.pushState(title, artist, playing);
  }

  PlayerService.instance.addListener(() => unawaited(push()));
  unawaited(push());
}

Future<void> _bootApp({
  required ThemeProvider themeProvider,
  required LanguageProvider languageProvider,
}) {
  return Future.wait([
    () async {
      try {
        await PlayerService.instance.init();
        _startWidgetStatePush();
      } catch (e) {
        // Keep the app usable when the player fails to init.
        debugPrint('PlayerService init failed: $e');
      }
    }(),
    () async {
      try {
        await AudioService.init(
          builder: () => SwaraAudioHandler(),
          config: const AudioServiceConfig(
            androidNotificationChannelId:
                'com.nikodwidharma.offline_music_player.channel.audio',
            androidNotificationChannelName: 'Swara media controls',
            androidNotificationIcon: 'drawable/ic_stat_swara',
            androidNotificationOngoing: true,
            androidStopForegroundOnPause: true,
          ),
        );
      } catch (e) {
        debugPrint('AudioService failed to initialize: $e');
      }
    }(),
    () async {
      try {
        await themeProvider.load();
        // Seed the equalizer with the saved preset so the first
        // attach already uses it (no session yet, just stored).
        // Custom gains ride along when the stored preset is Custom.
        if (themeProvider.equalizerPreset == 'Custom') {
          await EqualizerService.instance
              .applyCustom(themeProvider.customEqGains);
        } else {
          await EqualizerService.instance
              .applyPreset(themeProvider.equalizerPreset);
        }
      } catch (e) {
        debugPrint('ThemeProvider failed to load: $e');
      }
    }(),
    () async {
      // Load the saved app language before startup (defaults to English).
      try {
        await languageProvider.load();
      } catch (e) {
        debugPrint('LanguageProvider failed to load: $e');
      }
    }(),
  ]);
}

class MusicApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  final LanguageProvider languageProvider;
  final Future<void> bootFuture;
  const MusicApp(
      {super.key,
      required this.themeProvider,
      required this.languageProvider,
      required this.bootFuture});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: languageProvider),
        // PlayerService is a singleton; register it once globally so any
        // Selector can read it without a local wrapper.
        ChangeNotifierProvider.value(value: PlayerService.instance),
      ],
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, tp, lp, _) => MaterialApp(
          title: 'Swara',
          debugShowCheckedModeBanner: false,
          locale: lp.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Apply the user text scale on top of the system setting.
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler:
                    TextScaler.linear(tp.textScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          themeMode: tp.themeMode,
          // Both themes come from the same builder (lib/theme/app_theme.dart)
          // so light and dark share every component default: app bar, card,
          // dialog, buttons, list rows, snackbars and the page transition.
          theme: buildSwaraTheme(
            seed: tp.accentColor,
            brightness: Brightness.light,
          ),
          darkTheme: tp.buildDarkTheme(),
          home: BootGate(bootFuture: bootFuture),
        ),
      ),
    );
  }
}

// Shows the splash while boot init runs, then hands off to StartupGate.
// The handoff is a soft fade so the app does not hard-cut after boot.
class BootGate extends StatelessWidget {
  final Future<void> bootFuture;
  const BootGate({super.key, required this.bootFuture});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: bootFuture,
      builder: (context, snapshot) {
        final ready = snapshot.connectionState == ConnectionState.done;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          // Same curve family as the splash entrance.
          switchInCurve: const Cubic(0.23, 1.0, 0.32, 1.0),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: ready
              ? const StartupGate(key: ValueKey('gate'))
              : const SplashScreen(key: ValueKey('splash')),
        );
      },
    );
  }
}

// Chooses the first screen based on the persisted onboarding flag.
// Shows onboarding when 'onboarding_done' is not true, else HomeScreen.
// Boot init above runs in parallel behind BootGate and SplashScreen.
// The notification permission is requested here (once, best effort) only
// after onboarding is done, so boot never pops a permission dialog.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  // Stored once so the FutureBuilder below never restarts the future
  // on rebuild (inline futures in build would refetch on every frame).
  late final Future<bool> _doneFuture = _loadAndMaybeRequestNotification();

  Future<bool> _loadAndMaybeRequestNotification() async {
    final bool done;
    try {
      final prefs = await SharedPreferences.getInstance();
      done = prefs.getBool(kOnboardingDoneKey) ?? false;
    } catch (e) {
      // On storage failure, fall back to home so the app stays usable.
      debugPrint('Failed to read onboarding flag: $e');
      return true;
    }
    if (done) {
      try {
        await Permission.notification.request();
      } catch (e) {
        debugPrint('Notification permission could not be requested: $e');
      }
    }
    return done;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _doneFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // Minimal splash while the flag loads.
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) {
          return const HomeScreen();
        }
        return const OnboardingScreen();
      },
    );
  }
}
