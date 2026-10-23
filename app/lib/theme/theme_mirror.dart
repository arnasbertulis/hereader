/// A one-way copy of the reader's theme choice, for the web page's loading
/// background.
///
/// The choice lives in the database, behind the engine the page is still
/// loading, so `web/index.html` cannot read it before first paint. This puts
/// just that choice where an inline script can: a `localStorage` key holding
/// `light`, `dark` or `system`.
///
/// Not a second writer. The `preferences` row stays the source of truth, the
/// copy is written after that row and from what it holds, and nothing in the
/// app reads it back.
///
/// Platform code lives behind the conditional export: the web implementation
/// needs `dart:js_interop`, which the other targets cannot compile.
library;

export 'theme_mirror_key.dart';
export 'theme_mirror_stub.dart'
    if (dart.library.js_interop) 'theme_mirror_web.dart';
