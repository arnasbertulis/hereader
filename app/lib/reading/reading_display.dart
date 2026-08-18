import 'package:flutter/foundation.dart';

import '../data/library_repository.dart';

/// What the reader's place is measured against on a tile.
///
/// Home and the library both draw a book's chapter and how long is left in
/// it. This decides which "it" — the chapter the reader is in, or the whole
/// book. Both figures are honest and they answer different questions: whether
/// this chapter fits in the time available, and how big the remaining
/// commitment is.
///
/// A preference rather than a fixed choice because neither answer is the
/// obvious default, and because the app cannot always honour the narrower
/// one. A note, a book declaring no table of contents, a reader still in
/// front matter and a position that has just arrived from another device all
/// have no chapter (see ADR 0018), and the figure falls back to the book in
/// every one of those cases. The chapter name is shown either way, so the
/// line beside the figure always says what it is counting.
///
/// **Device-local, on purpose**, matching every other `ui.` key.
/// `AppearanceController`'s reasoning applies unchanged: a phone and a
/// desktop are read in different sittings, and ADR 0005 records the outbound
/// preference path as unused capability that a display toggle is the wrong
/// thing to open.

/// Preference keys, in the `ui.` namespace `activeProfileKey` established.
abstract final class ReadingDisplayKeys {
  static const timeLeftScope = 'ui.time_left_scope';
  static const stepWords = 'ui.step_words';
}

/// How far one deliberate step moves, in words.
///
/// The reading surface's left and right quarters and the Left and Right keys
/// all move by this. See ADR 0020.
///
/// Not `ReadingProfile.rewindWords`, which answers a different question: how
/// far a *resume* re-enters the sentence after a pause. That belongs to a
/// reading style and so travels with the profile; this belongs to the input —
/// a thumb on a phone and an arrow key on a desktop want different grains —
/// and so stays on the device, like every other `ui.` key.
const kDefaultStepWords = 1;
const kMinStepWords = 1;
const kMaxStepWords = 10;

/// A minimum of one, not zero. At zero both edge zones become controls that
/// visibly do nothing, and the centre already covers stopping where you are.
///
/// Never throws, and clamps rather than falling back: a value written by a
/// build that offered a wider range should degrade to the nearest one this
/// build can honour, which is nearer the reader's intent than the default is.
int decodeStepWords(String? value) =>
    int.tryParse(value ?? '')?.clamp(kMinStepWords, kMaxStepWords) ??
    kDefaultStepWords;

/// What the time-left figure counts down to.
enum TimeLeftScope { chapter, book }

/// Stored as a word rather than an index.
///
/// The same rule `encodeThemeMode` follows, for the same reason: an index
/// breaks silently the day the enum gains a case in a different position,
/// and the row already on disk would then name something else.
String encodeTimeLeftScope(TimeLeftScope scope) => switch (scope) {
  TimeLeftScope.chapter => 'chapter',
  TimeLeftScope.book => 'book',
};

/// Never throws. Restore runs inside the try that renders the startup
/// failure screen, so an unrecognised value has to degrade to a default
/// rather than cost the reader their app.
TimeLeftScope decodeTimeLeftScope(String? value) => switch (value) {
  'book' => TimeLeftScope.book,
  _ => TimeLeftScope.chapter,
};

/// What Settings › Reading writes, and the controller that holds it.
///
/// A `ChangeNotifier` rather than a value read per screen because the shell
/// keeps every tab alive in a cross-fading stack: a preference Home read once
/// when it was built would still be the old one after the reader changed it in
/// Settings and faded back.
///
/// [stepWords] has no such consumer in the shell — the reader is a route
/// pushed above it, and `ReaderScreen` reads the key itself at open through
/// the repository it already holds, decoded by the same [decodeStepWords].
/// It lives here because this is where the settings page writes, and one key
/// with one decoder read from two places is not two definitions of it.
class ReadingDisplayController extends ChangeNotifier {
  final LibraryRepository repository;

  /// Supplies a clock stamp for each write. Pass `syncEngine.issueStamp`.
  final Future<String> Function() issueStamp;

  TimeLeftScope _timeLeftScope = TimeLeftScope.chapter;
  int _stepWords = kDefaultStepWords;

  ReadingDisplayController({
    required this.repository,
    required this.issueStamp,
  });

  TimeLeftScope get timeLeftScope => _timeLeftScope;

  int get stepWords => _stepWords;

  /// Reads the stored values. Called from `_start()` before `runApp`,
  /// alongside `AppearanceController.restore`.
  Future<void> restore() async {
    final scope = await repository.preference(ReadingDisplayKeys.timeLeftScope);
    final step = await repository.preference(ReadingDisplayKeys.stepWords);

    _timeLeftScope = decodeTimeLeftScope(scope);
    _stepWords = decodeStepWords(step);

    notifyListeners();
  }

  Future<void> setTimeLeftScope(TimeLeftScope scope) async {
    if (scope == _timeLeftScope) return;

    // Written first, then notified: the other order shows the reader a
    // setting that did not stick if the write throws.
    await repository.setPreference(
      ReadingDisplayKeys.timeLeftScope,
      encodeTimeLeftScope(scope),
      hlc: await issueStamp(),
      sync: false,
    );

    _timeLeftScope = scope;
    notifyListeners();
  }

  /// Clamped rather than asserted. The slider cannot produce a value outside
  /// the range, so an out-of-range one means a caller this class cannot see,
  /// and pinning it is a better answer than throwing on a settings screen.
  Future<void> setStepWords(int words) async {
    final next = words.clamp(kMinStepWords, kMaxStepWords);
    if (next == _stepWords) return;

    await repository.setPreference(
      ReadingDisplayKeys.stepWords,
      '$next',
      hlc: await issueStamp(),
      sync: false,
    );

    _stepWords = next;
    notifyListeners();
  }
}
