// Picked by test_database.dart on the Dart VM, where drift's native
// executor is available.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// No-op on this target. `NativeDatabase.memory()` needs nothing loaded
/// ahead of it; the web half does, and both halves have to offer the same
/// symbol for `flutter_test_config.dart` to call unconditionally.
Future<void> initTestDatabase() async {}

QueryExecutor testExecutor() => NativeDatabase.memory();
