// Test files run on two targets: `flutter test` on the Dart VM, and
// `flutter test --platform chrome` in a browser. `dart:ffi`, which
// `NativeDatabase` needs, does not exist on the browser target, so the two
// executors live in separate files and this one picks between them at
// compile time.
export 'test_database_vm.dart'
    if (dart.library.js_interop) 'test_database_web.dart';
