import 'dart:async';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:app/reading/profile_presentation.dart';
import 'package:app/reading/reader_screen.dart';
import 'package:app/reading/rsvp_view.dart';
import 'package:app/reading/scrolling_text_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

ReadingProfile _profile({
  String id = 'p.test',
  String name = 'Test',
  PresentationMode mode = PresentationMode.fixedSingle,
}) => ReadingProfile(
  id: id,
  name: name,
  presentation: PresentationConfig(mode: mode),
);

TokenizedText _text() => TokenizedText.from(const [
  (id: 'one', text: 'Alpha beta gamma.'),
  (id: 'two', text: 'Delta epsilon zeta.'),
], parserVersion: 1);

Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late AppDatabase database;
  late LibraryRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = LibraryRepository(database);
  });

  tearDown(() => database.close());

  group('the warning', () {
    test('is silent when the device asks for nothing', () {
      expect(
        reduceMotionWarning(
          _profile(mode: PresentationMode.continuousScroll),
          disabled: false,
        ),
        isNull,
      );
    });

    test('is silent for a profile that does not move text', () {
      expect(reduceMotionWarning(_profile(), disabled: true), isNull);
    });

    test(
      'fires for a scrolling profile on a device asking for less motion',
      () {
        final warning = reduceMotionWarning(
          _profile(mode: PresentationMode.continuousScroll),
          disabled: true,
        );

        expect(warning, isNotNull);
        // Warned about, not acted on: the reader chose motion as their reading
        // method. The wording has to say the app is going to keep moving.
        expect(warning, contains('reduce motion'));
      },
    );

    test('the fade warning goes quiet under scroll', () {
      // `transitionMs` fades one word into the next, and there is no such
      // moment on a marquee. A warning about a control that is not on screen
      // is worse than none.
      final fading = ReadingProfile(
        id: 'p.fade',
        name: 'Fade',
        pacing: const PacingConfig(baseWpm: 600),
        presentation: const PresentationConfig(transitionMs: 300),
      );

      expect(fadeWarning(fading), isNotNull);
      expect(
        fadeWarning(
          fading.copyWith(
            presentation: fading.presentation.copyWith(
              mode: PresentationMode.continuousScroll,
            ),
          ),
        ),
        isNull,
      );
    });
  });

  group('the editor control', () {
    final navigator = GlobalKey<NavigatorState>();

    /// Pushes the editor as a route, so the save-on-pop path is the one
    /// under test. The screen has no Save button: `PopScope` writes the
    /// draft when the route leaves.
    Future<void> openEditor(
      WidgetTester tester,
      ReadingProfile profile, {
      bool reduceMotion = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );

      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            // The ambient MediaQuery with one field changed, not a fresh
            // one: a bare `MediaQueryData` carries a zero size, and the list
            // then has nothing to scroll.
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: ProfileEditScreen(
                profile: profile,
                repository: repository,
                issueStamp: _stamp,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder list() => find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;

    /// Back to the top of the list, where the preview lives.
    Future<void> scrollToTop(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.drag(list(), const Offset(0, 300));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    /// The editor is one long `ListView`, so anything below the fold has to
    /// be scrolled to before it is built.
    ///
    /// Returns to the top first, because `scrollUntilVisible` only travels
    /// one way and these tests visit controls in both directions. Named
    /// scrollable, because the name field builds an `EditableText` and that
    /// is a second `Scrollable`.
    Future<void> scrollTo(WidgetTester tester, Finder target) async {
      await scrollToTop(tester);
      await tester.scrollUntilVisible(target, 200, scrollable: list());
      await tester.pumpAndSettle();
    }

    Finder modeControl() => find.byType(SegmentedButton<PresentationMode>);

    testWidgets('offers two modes and never the unbuilt one', (tester) async {
      await openEditor(tester, _profile());
      await scrollTo(tester, modeControl());

      final control = tester.widget<SegmentedButton<PresentationMode>>(
        modeControl(),
      );

      expect(control.segments.map((s) => s.value), [
        PresentationMode.fixedSingle,
        PresentationMode.continuousScroll,
      ]);
      expect(control.selected, {PresentationMode.fixedSingle});

      await _disposeTree(tester);
    });

    testWidgets('switching it redraws the preview as a marquee', (
      tester,
    ) async {
      await openEditor(tester, _profile());
      expect(find.byType(RsvpView), findsOneWidget);

      await scrollTo(tester, find.text('Sliding'));
      await tester.tap(find.text('Sliding'));
      await tester.pumpAndSettle();

      // Back to the preview, which is the first thing in the same list.
      await scrollToTop(tester);

      expect(find.byType(ScrollingTextView), findsOneWidget);
      expect(find.byType(RsvpView), findsNothing);

      await _disposeTree(tester);
    });

    testWidgets('the fade and fixation controls go with it', (tester) async {
      await openEditor(tester, _profile());

      await scrollTo(tester, find.text('Fade between words'));
      await scrollTo(tester, find.text('Highlight a fixation letter'));

      await scrollTo(tester, find.text('Sliding'));
      await tester.tap(find.text('Sliding'));
      await tester.pumpAndSettle();

      // Absent rather than present and inert. Their stored values are left
      // alone, which the round trip below covers.
      await scrollToTop(tester);
      await tester.drag(list(), const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(find.text('Fade between words'), findsNothing);
      expect(find.text('Highlight a fixation letter'), findsNothing);

      await _disposeTree(tester);
    });

    testWidgets('the pacing model goes away under sliding', (tester) async {
      // Velocity comes from the reading speed alone: `PlaybackSession`
      // branches on the presentation mode before it consults a `PacingModel`,
      // so the kind, the length scaling and the three pauses have nothing to
      // act on.
      await openEditor(tester, _profile());

      await scrollTo(tester, find.byType(SegmentedButton<PacingModelKind>));
      await scrollTo(tester, find.text('Length scaling'));
      await scrollTo(tester, find.text('Pause at sentences'));

      await scrollTo(tester, find.text('Sliding'));
      await tester.tap(find.text('Sliding'));
      await tester.pumpAndSettle();

      await scrollToTop(tester);
      await tester.drag(list(), const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(find.byType(SegmentedButton<PacingModelKind>), findsNothing);
      expect(find.text('Length scaling'), findsNothing);
      expect(find.text('Pause at commas'), findsNothing);
      expect(find.text('Pause at sentences'), findsNothing);
      expect(find.text('Pause at paragraphs'), findsNothing);

      // These two still apply, so they stay.
      await scrollTo(tester, find.text('Reading speed'));
      await scrollTo(tester, find.text('Rewind on resume'));

      await _disposeTree(tester);
    });

    testWidgets('the reading speed is live under sliding even on Manual', (
      tester,
    ) async {
      // The bug this rule fixes: sliding outranks the pacing model, so an
      // elicited profile switched to sliding had the one control that sets
      // its velocity greyed out.
      await openEditor(
        tester,
        ReadingProfile(
          id: 'mine',
          name: 'Mine',
          pacing: const PacingConfig(kind: PacingModelKind.elicited),
          presentation: const PresentationConfig(
            mode: PresentationMode.continuousScroll,
          ),
        ),
      );

      await scrollTo(tester, find.text('Reading speed'));

      // The first slider on the page: the pacing controls above it are
      // hidden under sliding, and the type size is further down.
      expect(
        tester.widget<Slider>(find.byType(Slider).first).onChanged,
        isNotNull,
      );

      await _disposeTree(tester);
    });

    testWidgets('the caret controls appear only under sliding, and persist', (
      tester,
    ) async {
      await openEditor(tester, _profile(id: 'mine', name: 'Mine'));

      await scrollToTop(tester);
      await tester.drag(list(), const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<CaretPlacement>), findsNothing);

      await scrollTo(tester, find.text('Sliding'));
      await tester.tap(find.text('Sliding'));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Where to look'));
      await scrollTo(tester, find.text('Above'));
      await tester.tap(find.text('Above'));
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Chevron'));
      await tester.tap(find.text('Chevron'));
      await tester.pumpAndSettle();

      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();

      final saved = (await repository.allProfiles()).firstWhere(
        (p) => p.id == 'mine',
      );
      expect(saved.presentation.caretPlacement, CaretPlacement.above);
      expect(saved.presentation.caretStyle, CaretStyle.chevron);

      await _disposeTree(tester);
    });

    testWidgets('the mode is saved, and the inert settings are kept', (
      tester,
    ) async {
      await openEditor(
        tester,
        ReadingProfile(
          id: 'mine',
          name: 'Mine',
          presentation: const PresentationConfig(
            transitionMs: 120,
            orpHighlight: true,
          ),
        ),
      );

      await scrollTo(tester, find.text('Sliding'));
      await tester.tap(find.text('Sliding'));
      await tester.pumpAndSettle();

      // Saved on pop; the screen has no Save button.
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();

      final saved = (await repository.allProfiles()).firstWhere(
        (p) => p.id == 'mine',
      );
      expect(saved.presentation.mode, PresentationMode.continuousScroll);

      // Hidden, not cleared, so switching back restores what the reader had.
      expect(saved.presentation.transitionMs, 120);
      expect(saved.presentation.orpHighlight, isTrue);

      await _disposeTree(tester);
    });

    testWidgets('the reduce-motion warning appears only where it applies', (
      tester,
    ) async {
      const text =
          'Your device asks apps to reduce motion. This mode moves text '
          'continuously and will keep doing so.';

      Future<void> check(
        ReadingProfile profile, {
        required bool reduceMotion,
        required Matcher matcher,
      }) async {
        await openEditor(tester, profile, reduceMotion: reduceMotion);
        await scrollTo(tester, modeControl());
        expect(find.text(text), matcher);
      }

      await check(
        _profile(mode: PresentationMode.continuousScroll),
        reduceMotion: false,
        matcher: findsNothing,
      );
      await check(_profile(), reduceMotion: true, matcher: findsNothing);
      await check(
        _profile(mode: PresentationMode.continuousScroll),
        reduceMotion: true,
        matcher: findsOneWidget,
      );

      await _disposeTree(tester);
    });
  });

  group('the reader sheet toggle', () {
    Widget reader() => MaterialApp(
      home: ReaderScreen(
        book: LibraryBook(id: 'b', title: 'A Book', text: _text()),
        repository: repository,
        issueStamp: _stamp,
        onSave: (_) async {},
      ),
    );

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(readerProfileButtonKey));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(readerScrollModeKey),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a stored profile is edited in place', (tester) async {
      final mine = _profile(id: 'mine', name: 'Mine');
      await repository.saveProfile(mine, hlc: await _stamp());
      await repository.setActiveProfile(mine.id, hlc: await _stamp());

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();
      expect(find.byType(RsvpView), findsOneWidget);

      await openSheet(tester);
      await tester.tap(find.byKey(readerScrollModeKey));
      await tester.pumpAndSettle();

      // No fork: the reader owns this profile, so the switch edits it.
      final saved = (await repository.allProfiles()).firstWhere(
        (p) => p.id == 'mine',
      );
      expect(saved.presentation.mode, PresentationMode.continuousScroll);
      expect(find.byType(ScrollingTextView), findsOneWidget);

      await _disposeTree(tester);
    });

    testWidgets('a preset is forked, and the fork is named after the mode', (
      tester,
    ) async {
      // Presets cannot be saved. The repo already has one rule for "the
      // reader changed a preset" — fork it and adopt the fork — and this
      // mirrors it rather than inventing a second. The name says what
      // changed, because a reader who flipped one switch did not ask for a
      // duplicate. See ADR 0025.
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await openSheet(tester);
      await tester.tap(find.byKey(readerScrollModeKey));
      await tester.pumpAndSettle();

      final active = await repository.activeProfile();
      expect(active.isBuiltIn, isFalse);
      expect(active.presentation.mode, PresentationMode.continuousScroll);
      expect(active.name, '${Presets.standard.name} (sliding)');
      expect(active.name, isNot(contains('copy')));

      // The preset itself is untouched.
      expect(Presets.standard.presentation.mode, PresentationMode.fixedSingle);

      await _disposeTree(tester);
    });

    testWidgets('a profile of the readers own is edited in place', (
      tester,
    ) async {
      // Nothing to go back to: this one matches no preset, so the switch
      // does what it does for any other setting and leaves the profile where
      // it is. Its name is the reader's, and is not touched.
      final mine = ReadingProfile(
        id: 'mine',
        name: 'Mine',
        pacing: const PacingConfig(baseWpm: 123),
        presentation: const PresentationConfig(
          mode: PresentationMode.continuousScroll,
        ),
      );
      await repository.saveProfile(mine, hlc: await _stamp());
      await repository.setActiveProfile(mine.id, hlc: await _stamp());

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();
      expect(find.byType(ScrollingTextView), findsOneWidget);

      await openSheet(tester);
      await tester.tap(find.byKey(readerScrollModeKey));
      await tester.pumpAndSettle();

      expect(find.byType(RsvpView), findsOneWidget);
      final saved = (await repository.allProfiles()).firstWhere(
        (p) => p.id == 'mine',
      );
      expect(saved.presentation.mode, PresentationMode.fixedSingle);
      expect(saved.name, 'Mine');

      await _disposeTree(tester);
    });

    testWidgets('turning it off returns to the preset it was forked from', (
      tester,
    ) async {
      // The reported confusion: the switch went off and left the reader on a
      // profile called "Standard (sliding)" showing one word at a time. A
      // switch has to land the reader where they started, so the fork it
      // made goes with it.
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await openSheet(tester);
      await tester.tap(find.byKey(readerScrollModeKey));
      await tester.pumpAndSettle();
      expect((await repository.activeProfile()).isBuiltIn, isFalse);

      await openSheet(tester);
      await tester.tap(find.byKey(readerScrollModeKey));
      await tester.pumpAndSettle();

      expect(find.byType(RsvpView), findsOneWidget);
      expect((await repository.activeProfile()).id, Presets.standard.id);

      // Nothing the reader chose was in it, so it is not left behind either.
      final stored = (await repository.allProfiles()).where(
        (p) => !p.isBuiltIn,
      );
      expect(stored, isEmpty);

      await _disposeTree(tester);
    });

    testWidgets('a fork carrying caret settings is kept, and reused', (
      tester,
    ) async {
      // The caret controls only exist under sliding, so adjusting them is
      // the expected thing to do inside a fork. Deleting the fork would take
      // those settings with it, and forking again would hand back the
      // defaults, so the fork is left in place and found again next time.
      final fork = Presets.standard.fork(
        id: 'fork',
        name: '${Presets.standard.name} (sliding)',
      );
      await repository.saveProfile(
        fork.copyWith(
          presentation: fork.presentation.copyWith(
            mode: PresentationMode.continuousScroll,
            caretStyle: CaretStyle.chevron,
          ),
        ),
        hlc: await _stamp(),
      );
      await repository.setActiveProfile('fork', hlc: await _stamp());

      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();

      await openSheet(tester);
      await tester.tap(find.byKey(readerScrollModeKey));
      await tester.pumpAndSettle();

      expect((await repository.activeProfile()).id, Presets.standard.id);
      expect(
        (await repository.allProfiles()).where((p) => p.id == 'fork'),
        hasLength(1),
      );

      await openSheet(tester);
      await tester.tap(find.byKey(readerScrollModeKey));
      await tester.pumpAndSettle();

      final active = await repository.activeProfile();
      expect(active.id, 'fork', reason: 'reused rather than forked again');
      expect(active.presentation.caretStyle, CaretStyle.chevron);
      expect(
        (await repository.allProfiles()).where((p) => !p.isBuiltIn),
        hasLength(1),
      );

      await _disposeTree(tester);
    });
  });

  group('the time estimate', () {
    test('scroll reports a time even under elicited pacing', () {
      // Decision 19: the marquee outranks the pacing model, so there is
      // always a rate. ADR 0014 withholds an estimate when there is none.
      final elicited = ReadingProfile(
        id: 'p.e',
        name: 'E',
        pacing: const PacingConfig(kind: PacingModelKind.elicited),
      );

      expect(
        remainingReadingTime(
          remainingTokens: 100,
          config: estimationPacing(elicited),
        ),
        isNull,
      );

      final scrolling = elicited.copyWith(
        presentation: const PresentationConfig(
          mode: PresentationMode.continuousScroll,
        ),
      );

      expect(
        remainingReadingTime(
          remainingTokens: 100,
          config: estimationPacing(scrolling),
        ),
        isNotNull,
      );
    });

    test('a steady profile is handed through unchanged', () {
      final steady = ReadingProfile(id: 'p.s', name: 'S');
      expect(estimationPacing(steady), same(steady.pacing));
    });
  });
}
