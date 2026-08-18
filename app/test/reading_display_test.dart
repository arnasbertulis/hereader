import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/reading_display.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repo;
  late int stamps;

  Future<String> issueStamp() async {
    stamps++;
    return '000000000000$stamps-00000-test';
  }

  ReadingDisplayController controller() =>
      ReadingDisplayController(repository: repo, issueStamp: issueStamp);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);
    stamps = 0;
  });

  tearDown(() => db.close());

  test('round-trips every case', () {
    for (final scope in TimeLeftScope.values) {
      expect(decodeTimeLeftScope(encodeTimeLeftScope(scope)), scope);
    }
  });

  test('stores a word rather than an index', () {
    // An index breaks silently the day the enum gains a case in a different
    // position: the row on disk would then name something else.
    expect(encodeTimeLeftScope(TimeLeftScope.chapter), 'chapter');
    expect(encodeTimeLeftScope(TimeLeftScope.book), 'book');
  });

  test('falls back to the chapter on anything unrecognised', () {
    // Read inside the try whose catch renders the startup failure screen, so
    // a value this build does not know has to produce something renderable
    // rather than a throw.
    expect(decodeTimeLeftScope(null), TimeLeftScope.chapter);
    expect(decodeTimeLeftScope(''), TimeLeftScope.chapter);
    expect(decodeTimeLeftScope('part'), TimeLeftScope.chapter);
  });

  test('a fresh install counts the chapter', () async {
    final c = controller();
    await c.restore();

    expect(c.timeLeftScope, TimeLeftScope.chapter);
  });

  test('a set choice survives a restart', () async {
    final first = controller();
    await first.restore();
    await first.setTimeLeftScope(TimeLeftScope.book);

    final second = controller();
    await second.restore();

    expect(second.timeLeftScope, TimeLeftScope.book);
  });

  test('setting the value already held writes nothing', () async {
    final c = controller();
    await c.restore();

    await c.setTimeLeftScope(TimeLeftScope.chapter);

    expect(stamps, 0);
  });

  test('a change notifies its listeners', () async {
    final c = controller();
    await c.restore();

    var notified = 0;
    c.addListener(() => notified++);

    await c.setTimeLeftScope(TimeLeftScope.book);

    // Home and the library both listen. They are kept alive in the shell's
    // cross-fading stack, so a value read at build time would still be the
    // old one when the reader faded back from Settings.
    expect(notified, 1);
  });

  test('the choice stays on this device', () async {
    final c = controller();
    await c.restore();
    await c.setTimeLeftScope(TimeLeftScope.book);

    final queued = await db.select(db.outboxEvents).get();

    // Every ui. key is written with sync: false. ADR 0005 records the
    // outbound preference path as unused capability, and a display toggle is
    // the wrong thing to open it with.
    expect(queued, isEmpty);
  });
}
