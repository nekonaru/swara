import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The single source of truth for every visual default in Swara.
///
/// Screens used to style their own app bars, cards, dialogs, buttons and
/// muted text, so each one drifted a little on its own: one app bar was
/// elevated, the next flat, a card had a 12 px corner here and a 20 px one
/// there, and subtitles came in three different greys. Anything a screen does
/// not style by hand now comes from here, so a plain widget already matches
/// the rest of the app.
///
/// Motion lives here too: one page transition for every screen (the player
/// keeps its own slide up route in utils/page_transitions.dart), chosen to be
/// quick and quiet rather than showy.
ThemeData buildSwaraTheme({
  required Color seed,
  required Brightness brightness,
  bool amoledBlack = false,
}) {
  final bool isDark = brightness == Brightness.dark;
  // The AMOLED option promises a pitch black background, so the surface
  // itself goes black while every other container keeps its seeded tone and
  // stays visible on top of it.
  final bool black = isDark && amoledBlack;

  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  ).copyWith(
    // copyWith ignores nulls, so this only replaces the surface when the
    // AMOLED option is on and keeps the seeded value otherwise.
    surface: black ? Colors.black : null,
  );
  final Color background = black ? Colors.black : scheme.surface;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    // Read directly by a few Material widgets, so these follow the black
    // surface as well instead of leaving a grey edge in an AMOLED theme.
    canvasColor: black ? Colors.black : scheme.surface,
    cardColor: black ? Colors.black : scheme.surface,

    // Flat, same colour while the content scrolls under it. Screens no
    // longer need to fight the default elevation shift with their own
    // backgroundColor overrides.
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: scheme.onSurface,
      ),
    ),

    // Cards read as cards on every theme: no shadow, a lifted container
    // tone from the scheme, one corner radius everywhere.
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: scheme.onSurfaceVariant,
      ),
    ),

    // One shape for every list row, so the press ripple is rounded the same
    // way in Settings, the song menus and the folder lists.
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),

    // Stadium buttons with a semibold label: the same tap target and the
    // same weight everywhere instead of per screen tweaks.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    // Floating by default, so snackbars no longer hug the screen edge when a
    // screen forgets to ask for floating itself.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: scheme.inverseSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: TextStyle(
        fontSize: 14,
        color: scheme.onInverseSurface,
      ),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),

    // The library tabs keep the selected label on the foreground colour and
    // drop the hairline under the bar, which is what made the top of the
    // home screen look busier than the rest of the app.
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13),
      indicatorColor: scheme.primary,
      dividerColor: Colors.transparent,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      // Track colour from the scheme, so a loading bar no longer shows the
      // default purple track when the accent is teal or orange.
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
    ),

    // One transition for the whole app: a short fade with a small upward
    // slide, quicker on the way back than on the way in. Faster than the
    // default zoom while staying calm, and it never delays the first frame.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
