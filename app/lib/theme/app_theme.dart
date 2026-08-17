import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';
import 'page_transitions.dart';

/// The two inputs [appTheme] took that a [ColorScheme] cannot carry back out.
///
/// `buildScheme` maps an accent through `fidelity` and folds the contrast
/// level into every role, so neither the accent a reader picked nor whether
/// contrast was raised can be read back off the result. The reader screen
/// needs both: it builds its own scheme at a brightness taken from the
/// profile's background rather than from the platform, so it has to start
/// from the same two values this theme started from.
///
/// An extension rather than a constructor argument on `ReaderScreen`.
/// `BookOpener` holds a repository and a sync engine and has no route to
/// `AppearanceController`, so passing the accent down would mean threading
/// the controller through `HomeScreen` and `LibraryScreen` for one colour.
/// Reading it from the ambient theme also picks up the platform path: when
/// the operating system asks for high contrast, `MaterialApp` selects
/// `highContrastTheme`, and the extension on that theme reports true without
/// the reader screen knowing which theme it was handed.
@immutable
class AppChromeSource extends ThemeExtension<AppChromeSource> {
  /// The colour as the reader picked it, before `fidelity` mapped it.
  final Color accent;

  final bool highContrast;

  const AppChromeSource({required this.accent, required this.highContrast});

  /// Falls back to the same accent [appTheme] does, so a subtree built
  /// without a registered extension behaves as the app's default rather than
  /// throwing or drawing an unrelated colour.
  static const fallback = AppChromeSource(
    accent: Color(0xFF2F4858),
    highContrast: false,
  );

  static AppChromeSource of(BuildContext context) =>
      Theme.of(context).extension<AppChromeSource>() ?? fallback;

  @override
  AppChromeSource copyWith({Color? accent, bool? highContrast}) =>
      AppChromeSource(
        accent: accent ?? this.accent,
        highContrast: highContrast ?? this.highContrast,
      );

  /// The accent interpolates and the flag steps at the midpoint.
  ///
  /// Nothing animates between two themes in this app, since appearance
  /// changes rebuild `MaterialApp` outright. Implemented because the base
  /// class requires it, and implemented honestly rather than by returning
  /// `this`, so a future animated theme change does not silently hold the
  /// old accent for the length of the transition.
  @override
  AppChromeSource lerp(ThemeExtension<AppChromeSource>? other, double t) {
    if (other is! AppChromeSource) return this;

    return AppChromeSource(
      accent: Color.lerp(accent, other.accent, t) ?? other.accent,
      highContrast: t < 0.5 ? highContrast : other.highContrast,
    );
  }
}

/// Assembles a [ThemeData] for ordinary app chrome — Home, Library and
/// Settings — from [buildScheme] and the component themes below.
///
/// The reading surface does not use this. `readerChromeTheme` in
/// `profile_presentation.dart` builds its own scheme at a brightness taken
/// from the profile's own background, so a reader who chose light on dark
/// keeps dark chrome over their book while the rest of the app follows the
/// platform.
///
/// [accent] falls back to [AppAccents.defaultAccent] when omitted. It is
/// nullable rather than carrying a default value because a default has to be
/// a constant expression, and reading `.color` off a const `AppAccent` is not
/// one. Resolving it in the body keeps the accent list as the single place a
/// colour is written down.
///
/// `themeMode` stays a `MaterialApp`-level concern rather than living here,
/// since it decides which of `theme` / `darkTheme` applies rather than
/// anything about either theme's content.
ThemeData appTheme({
  required Brightness brightness,
  Color? accent,
  bool highContrast = false,
}) {
  final resolvedAccent = accent ?? AppAccents.defaultAccent.color;
  final scheme = buildScheme(
    accent: resolvedAccent,
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

    // Carries the two values `scheme` cannot report back, for the reader
    // screen. See [AppChromeSource].
    extensions: [
      AppChromeSource(accent: resolvedAccent, highContrast: highContrast),
    ],

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
