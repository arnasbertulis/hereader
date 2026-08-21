// Picked by test_database.dart on the Dart VM, where drift's native
// executor is available.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

QueryExecutor testExecutor() => NativeDatabase.memory();
