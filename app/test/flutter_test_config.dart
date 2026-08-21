import 'dart:async';

import 'test_database.dart';

/// Runs once per suite, before `main()`, on both targets.
///
/// The web half of `testExecutor()` needs an sqlite3 WASM module fetched over
/// the network, and there is exactly one place that fetch can happen. A
/// `testWidgets` body runs inside `FakeAsync`, which cannot advance real
/// asynchronous work — `flutter_test/lib/src/widget_tester.dart:820-822` says
/// so, and `WidgetTester.runAsync` exists to escape it. A `LazyDatabase`
/// deferring the load to the first query puts that fetch in the one zone
/// where it can never resolve: the suite then hangs until the runner's
/// wall-clock timeout, which is what cost a CI run 25 minutes and produced no
/// pass/fail list.
///
/// This file is honoured on the web target, not only on the VM one.
/// `flutter_tools/lib/src/test/web_test_compiler.dart:63-78` calls
/// `findTestConfigFile` per test file, and
/// `flutter_tools/lib/src/web/bootstrap.dart:590-604` emits the result into
/// the generated entrypoint as `entryPointRunner`. From there
/// `flutter_test/lib/src/_test_selector_web.dart:52-56` hands
/// `() => entryPointRunner(entryPoint)` to `RemoteListener.start`, and
/// `test_api/lib/src/backend/remote_listener.dart:137` awaits
/// `declarer.declare(main, ...)` — so this completes before a single test is
/// declared, let alone run.
///
/// Three consequences worth stating rather than rediscovering:
///
/// - On the VM target `initTestDatabase()` is a no-op, so this costs nothing
///   there.
/// - It loads the module once per suite, including suites that open no
///   database — one ~750 KB fetch against a local server plus instantiation.
/// - It moves the blast radius of a missing `/sqlite3.wasm` from one failing
///   test to the whole suite failing at startup, which is why the wrapped
///   error message names the `cp` command.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initTestDatabase();
  await testMain();
}
