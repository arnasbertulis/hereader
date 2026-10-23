/// The `localStorage` key `web/index.html` reads before first paint.
///
/// Written down twice, here and in the page's inline script, because HTML
/// cannot read a Dart constant. `web_shell_colors_test.dart` fails if they
/// drift apart.
const themeMirrorStorageKey = 'hereader.theme_mode';
