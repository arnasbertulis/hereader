import 'dart:js_interop';

import 'theme_mirror_key.dart';

extension type _Storage._(JSObject _) implements JSObject {
  external void setItem(String key, String value);
}

@JS('localStorage')
external _Storage get _localStorage;

/// Writes the theme choice where `web/index.html` reads it before first paint.
///
/// Swallows a failure. Private browsing and disabled storage make
/// `localStorage` throw, and the cost of that is the loading background
/// following the browser's preference again, which is where it started. It
/// must not fail the theme change itself.
void writeThemeMirror(String encodedThemeMode) {
  try {
    _localStorage.setItem(themeMirrorStorageKey, encodedThemeMode);
  } catch (_) {
    // Deliberately swallowed so the theme change isn't blocked; no warning is
    // raised. See above.
  }
}
