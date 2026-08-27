// Picked by test_database.dart under `flutter test --platform chrome`. Note
// that this target compiles with DDC, not dart2js — the same arithmetic
// still has to be checked against dart2js separately, per ADR 0009.
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

WasmSqlite3? _sqlite3;

/// Fetches and instantiates the sqlite3 WASM module, once per suite.
///
/// Called from `flutter_test_config.dart` before `main()`, which is the only
/// place this can happen: the fetch is real network I/O, and a `testWidgets`
/// body runs inside `FakeAsync`, which cannot advance real asynchronous work
/// (`widget_tester.dart:820-822`).
Future<void> initTestDatabase() async {
  if (_sqlite3 != null) return;
  final WasmSqlite3 loaded;
  try {
    loaded = await WasmSqlite3.loadFromUrl(Uri.parse('/sqlite3.wasm'));
  } catch (error) {
    throw StateError(
      'Failed to fetch /sqlite3.wasm. Run `dart run '
      'tool/stage_chrome_test_assets.dart` in app/ before running '
      '`flutter test --platform chrome`.\n$error',
    );
  }
  loaded.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  _sqlite3 = loaded;
}

QueryExecutor testExecutor() {
  final sqlite3 = _sqlite3;
  if (sqlite3 == null) {
    throw StateError(
      'initTestDatabase() has not run. It is called from '
      'test/flutter_test_config.dart, which flutter_tools wires into the '
      'generated web entrypoint — a test reaching this has been run some '
      'other way.',
    );
  }
  return WasmDatabase.inMemory(sqlite3);
}
