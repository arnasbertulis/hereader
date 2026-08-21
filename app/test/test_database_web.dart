// Picked by test_database.dart under `flutter test --platform chrome`. Note
// that this target compiles with DDC, not dart2js — the same arithmetic
// still has to be checked against dart2js separately, per ADR 0009.
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

WasmSqlite3? _cached;

Future<WasmSqlite3> _sqlite3() async {
  final cached = _cached;
  if (cached != null) return cached;
  final WasmSqlite3 loaded;
  try {
    loaded = await WasmSqlite3.loadFromUrl(Uri.parse('/sqlite3.wasm'));
  } catch (error) {
    throw StateError(
      'Failed to fetch /sqlite3.wasm. Run `cp web/sqlite3.wasm '
      'test/sqlite3.wasm` in app/ before running `flutter test --platform '
      'chrome`.\n$error',
    );
  }
  loaded.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  return _cached = loaded;
}

QueryExecutor testExecutor() =>
    LazyDatabase(() async => WasmDatabase.inMemory(await _sqlite3()));
