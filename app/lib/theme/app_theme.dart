import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';
import 'page_transitions.dart';

/// Assembles a [ThemeData] for ordinary app chrome — Home, Library and
/// Settings — from [buildScheme] and the component themes below.
///
/// Moved from `profile_presentation.dart` in the UI pass, along with the
/// name `appTheme`. The reading surface does not use this: `readerChromeTheme`
/// in `profile_presentation.dart` seeds from its own fixed neutral rather
/// than [accent], so a reader's chosen app accent never reaches the one
/// screen where the colours on show are the reader's own choice, not the
/// app's.
///
/// [accent] falls back to [AppAccents.defaultAccent] when omitted, which is
/// what PR 3 ships while there is still one fixed theme; appearance
/// preferences (PR 4) will pass a reader's stored choice through instead.
/// It is nullable rather than carrying a default value because a default
/// has to be a constant expression, and reading `.color` off a const
/// `AppAccent` is not one. Resolving it in the body keeps the accent list
/// as the single place a colour is written down, rather than repeating the
/// hex here or splitting every accent into a parallel bare-`Color`
/// constant purely to satisfy const evaluation.
///
/// `themeMode` stays a `MaterialApp`-level concern rather than living here,
/// since it decides which of `theme` / `darkTheme` applies rather than
/// anything about either theme's content.
ThemeData appTheme({
  required Brightness brightness,
  Color? accent,
  bool highContrast = false,
}) {
  final scheme = buildScheme(
    accent: accent ?? AppAccents.defaultAccent.color,
    brightness: brightness,
    highContrast: highContrast,
  );
  final hairlineWidth = highContrast
      ? AppHairline.widthHighContrast
      : AppHairline.width;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: appTextTheme(scheme),
    scaffoldBackgroundColor: scheme.surface,

    // Hairlines instead of shadows, per section 2 of the UI brief. No
    // elevation anywhere in the component themes below is incidental.
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(
        bottom: BorderSide(color: scheme.outlineVariant, width: hairlineWidth),
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: scheme.outlineVariant, width: hairlineWidth),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorShape: const StadiumBorder(),
      indicatorColor: scheme.primaryContainer,
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorShape: const StadiumBorder(),
      indicatorColor: scheme.primaryContainer,
      useIndicator: true,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        minimumSize: const Size(48, 48),
        textStyle: appTextTheme(scheme).labelLarge,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        side: BorderSide(color: scheme.outline, width: hairlineWidth),
        minimumSize: const Size(48, 48),
        textStyle: appTextTheme(scheme).labelLarge,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        minimumSize: const Size(48, 48),
        textStyle: appTextTheme(scheme).labelLarge,
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: hairlineWidth,
      space: hairlineWidth,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
      ),
    ),

    // A fade and two percent of scale, on every platform. The default
    // slides a full screen sideways over 300ms, which is the motion the
    // frame-pacing investigation found worst on Android Chrome: long, slow
    // translation of a large area, rendered on the main thread through
    // requestAnimationFrame while the panel runs at twice that rate.
    pageTransitionsTheme: quietPageTransitions,
  );
}
