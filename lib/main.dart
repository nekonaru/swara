import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/language_provider.dart';
import 'providers/library_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/theme_provider.dart';
import 'services/db_helper.dart';
import 'services/equalizer_service.dart';
import 'services/loudness_service.dart';
import 'services/permission_service.dart';
import 'services/snapshot_service.dart';
import 'services/share_import_service.dart';
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
  // Ask for permissions only after the user has seen the intro, from the
  // onboarding finish action or the home screen. A dialog over the splash
  // pauses the entrance animation and breaks the handoff.

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

  // Keep at most three recent local snapshots. The interval gate lives in
  // SnapshotService, so timer and lifecycle callers cannot duplicate work.
  unawaited(bootFuture.then((_) {
    _startAutoSnapshots();
    _startShareImportBridge();
  }));

  // Dynamic launcher shortcuts are registered by the boot task after the
  // saved language is loaded, so their titles are localized.
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
      await _channel.invokeMethod('notifyHandlerReady');
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
    if (action.startsWith('swara.widget.PLAY_SLOT:')) {
      // Payload is "slotId:filePath". Both must still match the live queue.
      final raw = action.substring('swara.widget.PLAY_SLOT:'.length);
      final separator = raw.indexOf(':');
      if (separator < 0) return;
      final slotId = int.tryParse(raw.substring(0, separator));
      final path = raw.substring(separator + 1);
      if (slotId != null && path.isNotEmpty) {
        var pos = service.queuePosForSlot(slotId);
        if (pos == null ||
            pos < 0 ||
            pos >= service.queueOrderLength ||
            service.songAtOrderIndex(pos)?.filePath != path) {
          // Slot ids are index based and change after removals. Fall back to
          // the file path, like Android Auto does, so a stale widget row can
          // still play the song the user sees.
          pos = null;
          for (var i = 0; i < service.queueOrderLength; i++) {
            if (service.songAtOrderIndex(i)?.filePath == path) {
              pos = i;
              break;
            }
          }
        }
        if (pos != null && pos >= 0 && pos < service.queueOrderLength) {
          await service.playAtQueueIndex(pos);
        }
      }
      return;
    }
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

  static Future<void> pushState(String title, String artist, bool playing,
      String? artPath, int positionMs, String nextTitle,
      String queueJson) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'title': title,
        'artist': artist,
        'playing': playing,
        'artPath': artPath,
        'positionMs': positionMs,
        'nextTitle': nextTitle,
        'queueJson': queueJson,
      });
    } catch (e) {
      debugPrint('Widget state push failed: $e');
    }
  }
}

final GlobalKey<ScaffoldMessengerState> _shareScaffoldKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> _handleSharedImport(List<String> uris) async {
  if (uris.isEmpty) return;
  try {
    await _WidgetBridge.bootFuture;
  } catch (_) {}
  final result = await ShareImportService.instance.importUris(uris);
  if (result.imported > 0) {
    await LibraryProvider.instance.scanDevice();
  }
  final messenger = _shareScaffoldKey.currentState;
  if (messenger == null) return;
  final l = lookupAppLocalizations(LanguageProvider.instance.locale);
  final parts = <String>[];
  if (result.imported > 0) parts.add(l.shareImportImported(result.imported));
  if (result.skipped > 0) parts.add(l.shareImportSkipped(result.skipped));
  if (result.failed > 0) parts.add(l.shareImportFailed('${result.failed}'));
  if (parts.isEmpty) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(parts.join(' ')),
    ));
}

void _startShareImportBridge() {
  ShareImportService.channel.setMethodCallHandler((call) async {
    if (call.method == 'onImportUris') {
      final uris = (call.arguments as List?)?.cast<String>() ?? const <String>[];
      unawaited(_handleSharedImport(uris));
    }
  });
  unawaited(ShareImportService.channel.invokeMethod<void>('notifyHandlerReady'));
  unawaited(ShareImportService.instance.getInitialImport()
      .then((uris) => _handleSharedImport(uris)));
}

void _startAutoSnapshots() {
  Timer.periodic(SnapshotService.defaultInterval, (_) {
    unawaited(SnapshotService.instance.createSnapshot());
  });
  unawaited(SnapshotService.instance.createSnapshot());
}

// Saves the playback position when the app is backgrounded, so a cold start
// resumes paused at the exact minute:second the user left off.
class _SwaraLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      PlayerService.instance.saveResumeStateNow();
      unawaited(SnapshotService.instance.createSnapshot());
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
// empty results are ignored and errors are only logged. The shortcut waits
// for the shared boot future before acting, so a cold start launched from a
// shortcut never races the playback restore.
Future<void> _handleAppShortcut(String shortcutType) async {
  try {
    await _WidgetBridge.bootFuture;
  } catch (_) {
    // Boot failures are logged at the call site; act anyway.
  }
  try {
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
/// Up-next snapshot for the home widget. Called only when the queue
/// fingerprint changes, never on ordinary notification ticks.
String _widgetQueueJson(PlayerService service) => jsonEncode(<Map<String, Object?>>[
      for (var i = service.currentIndex + 1;
          i < service.queueOrderLength && i <= service.currentIndex + 5;
          i++)
        {
          'slotId': service.queueSlotIdAt(i) ?? -1,
          'path': service.songAtOrderIndex(i)?.filePath ?? '',
          'title': service.songAtOrderIndex(i)?.title ?? '',
          'artist': service.songAtOrderIndex(i)?.artist ?? '',
        },
    ]);

// Subscribe to playback state and mirror it into the home screen widget.
void _startWidgetStatePush() {
  var lastTitle = '';
  var lastArtist = '';
  var lastPlaying = false;
  var lastArt = '';
  var lastNextTitle = '';
  var lastQueueJson = '';
  var lastQueueFingerprint = '';
  var hasPushed = false;
  // Track the previous tick, not the last pushed value. Comparing against the
  // last push makes every 1.5 s of normal playback look like a seek and
  // rebuilds the widget about 40 times a minute.
  var lastTickPositionMs = 0;
  var hasTick = false;
  // The position stream advances smoothly at ~1 Hz; a jump larger than the
  // threshold means a seek happened, and the widget chronometer's base must
  // be re-pushed. (A-B repeat seeks, slider seeks, restore seeks all move
  // the playhead discontinuously.)
  const jumpThresholdMs = 1500;

  Future<void> push({bool force = false}) async {
    final service = PlayerService.instance;
    final song = service.currentSong;
    final title = song?.title ?? 'Swara';
    final artist = song?.artist ?? '';
    final playing = song != null && service.player.playing;
    final art = (song?.albumArtPath ?? '').trim();
    // Snapshot the position at push time; the widget chronometer
    // keeps counting from the base on its own afterwards. Use the
    // cold-restore-aware getter so a post-restore push is never 0:00.
    final positionMs = song != null ? service.positionForWidget : 0;
    final nextTitle = service.nextTitle ?? '';
    // Cheap fingerprint first. jsonEncode and five queue lookups are wasted
    // on every favorite, shuffle or speed toggle otherwise.
    final fingerprint = '${service.queueVersion}|${service.currentIndex}|'
        '${service.queueOrderLength}';
    final stateChanged = !hasPushed ||
        title != lastTitle ||
        artist != lastArtist ||
        playing != lastPlaying ||
        art != lastArt ||
        nextTitle != lastNextTitle;
    final queueChanged = fingerprint != lastQueueFingerprint;
    if (!force && !stateChanged && !queueChanged) return;
    final queueJson = queueChanged || lastQueueJson.isEmpty
        ? _widgetQueueJson(service)
        : lastQueueJson;
    lastQueueFingerprint = fingerprint;
    lastTitle = title;
    lastArtist = artist;
    lastPlaying = playing;
    lastArt = art;
    lastNextTitle = nextTitle;
    lastQueueJson = queueJson;
    lastTickPositionMs = positionMs;
    hasTick = true;
    hasPushed = true;
    await _WidgetBridge.pushState(
        title, artist, playing, art.isEmpty ? null : art, positionMs,
        nextTitle, queueJson);
  }

  // Republish the widget whenever the position stream shows a discontinuity
  // (a seek), so the widget clock does not drift after seeking.
  String? lastSubscribedPlayerId;
  StreamSubscription<Duration>? positionSub;

  void resubscribe() {
    positionSub?.cancel();
    final player = PlayerService.instance.player;
    lastSubscribedPlayerId = player.hashCode.toString();
    positionSub = player.positionStream.listen((_) {
      final service = PlayerService.instance;
      final positionMs = service.positionForWidget;
      if (hasTick && (positionMs - lastTickPositionMs).abs() > jumpThresholdMs) {
        // An A-B loop jumps back to point A on every repetition. The widget
        // state did not otherwise change, so do not republish it each time.
        final a = service.abRepeatA;
        final looping = service.hasABRepeat &&
            a != null &&
            (positionMs - a.inMilliseconds).abs() <
                (PlayerService.abRepeatTolerance.inMilliseconds + 300);
        if (!looping) unawaited(push(force: true));
      }
      lastTickPositionMs = positionMs;
      hasTick = true;
    });
  }

  PlayerService.instance.addListener(() {
    unawaited(push());
    final player = PlayerService.instance.player;
    final id = player.hashCode.toString();
    // The audible player instance changes on crossfade; resubscribe then.
    if (id != lastSubscribedPlayerId) {
      resubscribe();
    }
  });
  resubscribe();
  unawaited(push());
}

Future<bool> _bootApp({
  required ThemeProvider themeProvider,
  required LanguageProvider languageProvider,
}) async {
  final results = await Future.wait<dynamic>([
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
        ).timeout(
          // An OEM hang here must not wedge the whole boot (widget taps and
          // shortcuts wait on this future); degrade to notification-less
          // playback instead.
          const Duration(seconds: 6),
          onTimeout: () => throw TimeoutException('AudioService init timed out'),
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
        // Custom gains are persisted on every slider change and on every
        // preset selection, so they are the live curve for both 'Custom' and
        // 'user:<id>' tokens after a restart.
        final presetToken = themeProvider.equalizerPreset;
        final isUserCurve = presetToken.startsWith('user:');
        final savedGains = isUserCurve
            ? themeProvider.gainsForActivePreset()
            : null;
        if (presetToken == 'Custom' || isUserCurve) {
          await EqualizerService.instance.applyCustom(
            savedGains ?? themeProvider.customEqGains,
            presetToken: presetToken,
          );
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
        // Shortcut titles come from the active locale, so register them
        // only after the saved language is known.
        _setupDynamicShortcuts();
      } catch (e) {
        debugPrint('LanguageProvider failed to load: $e');
      }
    }(),
    () async {
      // Load the saved loudness preference before the player attaches its
      // DSP effects to the first audio session.
      try {
        await LoudnessService.instance.load();
      } catch (e) {
        debugPrint('Loudness load failed: $e');
      }
    }(),
    () async {
      // No automatic deletion at boot. Metadata cache cleanup is an explicit
      // user action in Settings so nothing is removed without confirmation.
    }(),
    () async {
      // Read the onboarding flag as part of boot so the intro has a single
      // gate and no unbranded spinner stage.
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getBool(kOnboardingDoneKey) ?? false;
      } catch (_) {
        return true;
      }
    }(),
    // No artificial floor here. The native splash and SplashScreen's own
    // entrance already carry the brand moment; waiting 600 ms on every warm
    // launch only delayed the first usable screen.
  ]);
  return results[6] as bool? ?? true;
}

class MusicApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  final LanguageProvider languageProvider;
  final Future<bool> bootFuture;
  const MusicApp(
      {super.key,
      required this.themeProvider,
      required this.languageProvider,
      required this.bootFuture});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // One instance for both the app and OS callbacks (shared imports).
        ChangeNotifierProvider.value(value: LibraryProvider.instance),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: languageProvider),
        // PlayerService is a singleton; register it once globally so any
        // Selector can read it without a local wrapper.
        ChangeNotifierProvider.value(value: PlayerService.instance),
      ],
      child: Consumer2<ThemeProvider, LanguageProvider>(
        builder: (context, tp, lp, _) => DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            // Material You on Android 12+ when enabled; otherwise the
            // seeded palette. Falls back silently when the system has no
            // dynamic scheme.
            final dynamic = tp.dynamicColor;
            return MaterialApp(
              scaffoldMessengerKey: _shareScaffoldKey,
              title: 'Swara',
              debugShowCheckedModeBanner: false,
              locale: lp.locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              // Apply the user text scale on top of the system setting,
              // never instead of it: the OS accessibility size stays in
              // effect, the in-app scale multiplies on top.
              builder: (context, child) {
                final media = MediaQuery.of(context);
                final systemScale = media.textScaler.scale(1.0);
                // Keep system bars in step with the active theme after the
                // splash hands off, including AMOLED black backgrounds.
                final scheme = Theme.of(context).colorScheme;
                final dark = scheme.brightness == Brightness.dark;
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: Colors.transparent,
                    statusBarIconBrightness:
                        dark ? Brightness.light : Brightness.dark,
                    systemNavigationBarColor: scheme.surface,
                    systemNavigationBarIconBrightness:
                        dark ? Brightness.light : Brightness.dark,
                  ),
                  child: MediaQuery(
                    data: media.copyWith(
                      textScaler:
                          TextScaler.linear(systemScale * tp.textScale),
                    ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
              themeMode: tp.themeMode,
              // Both themes come from the same builder (lib/theme/app_theme.dart)
              // so light and dark share every component default: app bar, card,
              // dialog, buttons, list rows, snackbars and the page transition.
              theme: buildSwaraTheme(
                seed: tp.accentColor,
                brightness: Brightness.light,
                dynamicScheme: dynamic ? lightDynamic : null,
              ),
              darkTheme: tp.buildDarkTheme(
                dynamicScheme: dynamic ? darkDynamic : null,
              ),
              home: BootGate(bootFuture: bootFuture),
            );
          },
        ),
      ),
    );
  }
}

// Single gate: the branded splash crossfades straight into the first real
// screen. No unbranded spinner and no hard cut between two gates.
class BootGate extends StatefulWidget {
  final Future<bool> bootFuture;
  const BootGate({super.key, required this.bootFuture});

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  bool _permissionRequested = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return FutureBuilder<bool>(
      future: widget.bootFuture,
      builder: (context, snapshot) {
        final ready = snapshot.hasData;
        final onboardingDone = snapshot.data ?? false;
        if (ready && onboardingDone && !_permissionRequested) {
          _permissionRequested = true;
          // Ask only after the crossfade finishes so no dialog covers it.
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await Future<void>.delayed(reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 240));
            await PermissionService.ensureEssentialPermissions();
          });
        }
        final Widget destination = onboardingDone
            ? const HomeScreen()
            : const OnboardingScreen();
        return AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          switchInCurve: const Cubic(0.23, 1.0, 0.32, 1.0),
          switchOutCurve: const Cubic(0.23, 1.0, 0.32, 1.0),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: ready
              ? KeyedSubtree(key: const ValueKey('app'), child: destination)
              : const SplashScreen(key: ValueKey('splash')),
        );
      },
    );
  }
}
