import 'package:flutter/material.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import '../data/library_repository.dart';
import 'app_colors.dart';

/// The three appearance choices a reader makes about app chrome, and the
/// controller that stores them.
///
/// These are the app around the books: Home, Library, Settings, sign-in. The
/// reading surface takes its colours from the active reading profile and
/// nothing here reaches it. `readerChromeTheme` seeds from its own fixed
/// neutral for exactly that reason, so a reader who tinted their background
/// moss and set the accent to rust never sees the two adjacent.
///
/// **Device-local, on purpose.** `setPreference` takes `sync: false` and
/// every write below passes it explicitly. Two reasons. A phone read
/// outdoors and a desktop in a dim room want different brightnesses, which
/// is the argument that already keeps the active profile pointer local.
/// And syncing these needs the outbound preference path, which ADR 0005
/// records as unused capability; a theme switch is the wrong first thing to
/// send through it.

/// Preference keys, in the `ui.` namespace `activeProfileKey` established.
abstract final class AppearanceKeys {
  static const themeMode = 'ui.theme_mode';
  static const accent = 'ui.accent';
  static const highContrast = 'ui.high_contrast';
}

@immutable
class AppearanceSettings {
  final ThemeMode themeMode;
  final Color accent;
  final bool highContrast;

  const AppearanceSettings({
    required this.themeMode,
    required this.accent,
    required this.highContrast,
  });

  /// What a device with nothing stored starts from.
  ///
  /// A `static final` rather than default parameter values, for the same
  /// reason `appTheme` takes a nullable accent: `AppAccents.defaultAccent`
  /// is a const object, and reading `.color` off one is not a constant
  /// expression. Writing the Ink hex here instead would put it in two files,
  /// and the next person to change Ink would change one of them.
  static final AppearanceSettings defaults = AppearanceSettings(
    themeMode: ThemeMode.system,
    accent: AppAccents.defaultAccent.color,
    highContrast: false,
  );

  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    Color? accent,
    bool? highContrast,
  }) => AppearanceSettings(
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    highContrast: highContrast ?? this.highContrast,
  );

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.themeMode == themeMode &&
      other.accent == accent &&
      other.highContrast == highContrast;

  @override
  int get hashCode => Object.hash(themeMode, accent, highContrast);
}

// -- encoding ------------------------------------------------------------
//
// Values are stored as the words they mean rather than as enum indices. An
// index breaks silently the day the enum gains a case in a different
// position, and it says nothing at all to anyone reading the row.

String encodeThemeMode(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'system',
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
};

/// Falls back to following the platform rather than throwing.
///
/// Appearance is read inside `_start()`, before the first frame, so a row
/// this build does not recognise has to degrade to something renderable.
/// Failing there would replace the app with the startup failure screen over
/// a preference, which is the same reasoning ADR 0005 applies to profiles
/// arriving from a build with different constraints.
ThemeMode decodeThemeMode(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

final _accentHex = RegExp(r'^#?[0-9a-fA-F]{6}$');

/// Six-digit hex with a leading `#`, matching what `hexOf` already shows a
/// reader in the background picker.
///
/// The colour rather than the accent's name, so the custom accent the
/// appearance section will add needs no second storage format and no
/// migration: an arbitrary colour is already representable.
String encodeAccent(Color color) {
  final argb = color.toARGB32();
  return '#${_pair(redOf(argb))}${_pair(greenOf(argb))}${_pair(blueOf(argb))}';
}

String _pair(int component) =>
    component.toRadixString(16).padLeft(2, '0').toUpperCase();

/// Parses a stored accent, falling back to Ink on anything unrecognised.
///
/// Read two hex digits at a time rather than six at once. Every value that
/// exists here is at most 255, so there is no arithmetic whose result could
/// differ between the VM and `dart2js` — the failure class ADR 0009 exists
/// for. This file could not run in a browser test anyway, since `app/test/`
/// reaches `dart:ffi` through drift, which is precisely why it is written so
/// that being untestable there costs nothing.
Color decodeAccent(String? value) {
  if (value == null || !_accentHex.hasMatch(value)) {
    return AppearanceSettings.defaults.accent;
  }

  final hex = value.startsWith('#') ? value.substring(1) : value;

  return Color.fromARGB(
    0xFF,
    int.parse(hex.substring(0, 2), radix: 16),
    int.parse(hex.substring(2, 4), radix: 16),
    int.parse(hex.substring(4, 6), radix: 16),
  );
}

String encodeHighContrast(bool value) => value ? 'true' : 'false';

bool decodeHighContrast(String? value) => value == 'true';

// -- controller ----------------------------------------------------------

/// Holds the current appearance and writes changes through to the database.
///
/// Sits above `MaterialApp`, which rebuilds from it. Screens take it
/// directly rather than looking it up through an inherited widget, matching
/// how `SettingsScreen` already takes a repository and a stamp function: a
/// test that wants one constructs one.
class AppearanceController extends ChangeNotifier {
  final LibraryRepository repository;

  /// Supplies a clock stamp for each write. Pass `syncEngine.issueStamp`.
  final Future<String> Function() issueStamp;

  AppearanceSettings _settings = AppearanceSettings.defaults;

  AppearanceController({required this.repository, required this.issueStamp});

  AppearanceSettings get settings => _settings;

  /// Reads the three keys. Called from `_start()` before `runApp`.
  ///
  /// Before the first frame rather than after it, because reading them later
  /// means a white flash on a dark-theme device on every cold start, and the
  /// reader this app is for is more likely than most to be sensitive to it.
  ///
  /// Three keyed lookups rather than one query over the table. The
  /// repository exposes preferences by key and nothing else, and a
  /// prefix query added here would be a second way to read the same table
  /// for three rows on a path that runs once.
  Future<void> restore() async {
    final themeMode = await repository.preference(AppearanceKeys.themeMode);
    final accent = await repository.preference(AppearanceKeys.accent);
    final contrast = await repository.preference(AppearanceKeys.highContrast);

    _settings = AppearanceSettings(
      themeMode: decodeThemeMode(themeMode),
      accent: decodeAccent(accent),
      highContrast: decodeHighContrast(contrast),
    );

    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _settings.themeMode) return;

    await _persist(AppearanceKeys.themeMode, encodeThemeMode(mode));
    _settings = _settings.copyWith(themeMode: mode);
    notifyListeners();
  }

  Future<void> setAccent(Color accent) async {
    if (accent == _settings.accent) return;

    await _persist(AppearanceKeys.accent, encodeAccent(accent));
    _settings = _settings.copyWith(accent: accent);
    notifyListeners();
  }

  Future<void> setHighContrast(bool value) async {
    if (value == _settings.highContrast) return;

    await _persist(AppearanceKeys.highContrast, encodeHighContrast(value));
    _settings = _settings.copyWith(highContrast: value);
    notifyListeners();
  }

  /// Written first, then notified.
  ///
  /// The other order paints the change a frame sooner and shows the reader a
  /// setting that did not stick if the write throws. This is one keyed
  /// upsert against local SQLite, so the frame it costs is not one anybody
  /// can see.
  Future<void> _persist(String key, String value) async {
    await repository.setPreference(
      key,
      value,
      hlc: await issueStamp(),
      sync: false,
    );
  }
}
