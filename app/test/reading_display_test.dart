import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/reading_display.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

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
    db = AppDatabase(testExecutor());
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

  group('step words', () {
    test('a fresh install steps by one', () {
      expect(controller().stepWords, kDefaultStepWords);
      expect(kDefaultStepWords, 1);
    });

    test('survives a restart', () async {
      final first = controller();
      await first.setStepWords(4);

      final second = controller();
      await second.restore();

      expect(second.stepWords, 4);
    });

    test('an absent, empty or unreadable value steps by the default', () {
      expect(decodeStepWords(null), kDefaultStepWords);
      expect(decodeStepWords(''), kDefaultStepWords);
      expect(decodeStepWords('lots'), kDefaultStepWords);
      expect(decodeStepWords('3.5'), kDefaultStepWords);
    });

    test('a value outside the range is pinned, not discarded', () {
      // Nearer the reader's intent than the default is: a row written by a
      // build offering a wider range still says which end they wanted.
      expect(decodeStepWords('0'), kMinStepWords);
      expect(decodeStepWords('-2'), kMinStepWords);
      expect(decodeStepWords('40'), kMaxStepWords);
    });

    test('zero is not reachable through the setter either', () async {
      final c = controller();
      await c.setStepWords(0);

      expect(c.stepWords, kMinStepWords);
    });

    test('setting the value it already holds writes nothing', () async {
      final c = controller();
      await c.restore();

      await c.setStepWords(kDefaultStepWords);

      expect(stamps, 0);
    });

    test('a change notifies once', () async {
      final c = controller();
      var notified = 0;
      c.addListener(() => notified++);

      await c.setStepWords(6);

      expect(notified, 1);
      expect(c.stepWords, 6);
    });

    test('queues nothing for other devices', () async {
      final c = controller();
      await c.setStepWords(5);

      // Device-local like every other ui. key. A thumb on a phone and an
      // arrow key on a desktop want different grains, which is the whole
      // reason this is not `ReadingProfile.rewindWords`. See ADR 0020.
      expect(await db.select(db.outboxEvents).get(), isEmpty);
    });

    test('restore reads both keys', () async {
      final first = controller();
      await first.setStepWords(7);
      await first.setTimeLeftScope(TimeLeftScope.book);

      final second = controller();
      await second.restore();

      // One `restore` and two reads. The step arrived after the scope did,
      // and a restore that still read one key would leave the reader's step
      // at the default on every launch with nothing to show for it.
      expect(second.stepWords, 7);
      expect(second.timeLeftScope, TimeLeftScope.book);
    });
  });
}
