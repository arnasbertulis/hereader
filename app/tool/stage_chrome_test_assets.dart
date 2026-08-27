// Stages the two assets the browser test run needs, then gets out of the way.
//
//     dart run tool/stage_chrome_test_assets.dart
//     flutter test --platform chrome --timeout 60s $(grep -L "@TestOn('vm')" test/*_test.dart)
//
// Both assets exist because `flutter_tools` serves `<cwd>/test` at the test
// server's root, so `test/` is the only directory the in-browser runner can
// reach. Neither copy is tracked; both are gitignored.
//
// This script is the single place that staging is written down. It ran as a
// bare `cp` in `ci-flutter.yml` and as a code block in `app/README.md`
// before, and the two had already drifted — only the README knew about
// CanvasKit, because only Windows needs it, and CI is Linux. See ADR 0009.

import 'dart:io';

void main(List<String> arguments) {
  if (!File('pubspec.yaml').existsSync() || !Directory('test').existsSync()) {
    _fail('run this from the app/ directory');
  }

  _stageSqlite3Wasm();
  _stageCanvasKit();
}

/// The database module, copied from the one tracked `web/sqlite3.wasm`.
///
/// `test/flutter_test_config.dart` fetches it once per suite before `main()`
/// runs, rather than on demand: a `testWidgets` body runs inside `FakeAsync`,
/// which cannot advance a real network fetch, so a lazily loaded executor
/// would hang there until the runner's timeout instead of failing.
void _stageSqlite3Wasm() {
  final source = File('web/sqlite3.wasm');
  if (!source.existsSync()) {
    _fail(
      'missing ${source.path} — the tracked copy the test copy is made from',
    );
  }

  source.copySync('test/sqlite3.wasm');
  stdout.writeln('staged test/sqlite3.wasm');
}

/// The engine's CanvasKit build — on Windows only, where the test server
/// cannot serve its own.
///
/// `flutter_tools`' `_localCanvasKitHandler` (`flutter_web_platform.dart:518`)
/// builds its path with `_fileSystem.path.fromUri` and then guards on
/// `startsWith('canvaskit/')`. On Windows `fromUri` yields a backslash path,
/// so the guard never matches, every engine asset gets a `404`, and the run
/// hangs at zero CPU after Chrome launches — no error, no output, no suite.
/// The next handler in the cascade serves `<cwd>/test` and builds its path
/// correctly, so a copy there is what gets served instead.
///
/// Linux and macOS have a posix path context, the guard matches, and the
/// handler serves the SDK copy directly. Nothing to stage, which is why CI
/// never needed this and why the gap went unnoticed until it was hit by hand.
void _stageCanvasKit() {
  if (!Platform.isWindows) {
    stdout.writeln('skipped test/canvaskit — only Windows needs it');
    return;
  }

  final flutterRoot = _flutterRoot();
  if (flutterRoot == null) {
    _fail(
      'cannot locate the Flutter SDK — set FLUTTER_ROOT, or run this with '
      'the Dart bundled at <flutter_root>/bin/cache/dart-sdk',
    );
  }

  final source = Directory('$flutterRoot/bin/cache/flutter_web_sdk/canvaskit');
  if (!source.existsSync()) {
    _fail('missing ${source.path} — run `flutter precache --web` first');
  }

  // Removed rather than copied over: an SDK upgrade renames engine assets,
  // and a stale file left beside the new ones is served just as happily.
  final destination = Directory('test/canvaskit');
  if (destination.existsSync()) {
    destination.deleteSync(recursive: true);
  }

  _copyDirectory(source, destination);
  stdout.writeln('staged test/canvaskit from ${source.path}');
}

/// `FLUTTER_ROOT` if the caller set it, otherwise read back off the running
/// Dart, which lives at `<flutter_root>/bin/cache/dart-sdk/bin/` whenever it
/// is the one Flutter ships. Returns null for a standalone Dart SDK with no
/// `FLUTTER_ROOT` set — the caller reports that rather than guessing, because
/// a staging step that silently does nothing reproduces the exact hang this
/// script exists to prevent.
String? _flutterRoot() {
  final fromEnvironment = Platform.environment['FLUTTER_ROOT'];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }

  const marker = '/bin/cache/dart-sdk/bin/';
  final executable = Platform.resolvedExecutable.replaceAll(r'\', '/');
  final index = executable.indexOf(marker);
  return index == -1 ? null : executable.substring(0, index);
}

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final target = '${destination.path}/${_basename(entity.path)}';
    if (entity is Directory) {
      _copyDirectory(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

String _basename(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  return trimmed.substring(trimmed.lastIndexOf('/') + 1);
}

Never _fail(String message) {
  stderr.writeln('stage_chrome_test_assets: $message');
  exit(1);
}
