import 'package:app/reading/mode_fork.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

ReadingProfile _mine({
  String id = 'mine',
  String name = 'Mine',
  PresentationMode mode = PresentationMode.fixedSingle,
}) => ReadingProfile(
  id: id,
  name: name,
  presentation: PresentationConfig(mode: mode),
);

void main() {
  group('presetBehind', () {
    test('is null for a Preset itself', () {
      expect(presetBehind(Presets.standard), isNull);
    });

    test('finds the preset an exact fork came from, and it is discardable', () {
      final fork = Presets.standard.fork(
        id: 'fork',
        name: '${Presets.standard.name} (sliding)',
      );
      final sliding = fork.copyWith(
        presentation: fork.presentation.copyWith(
          mode: PresentationMode.continuousScroll,
        ),
      );

      final origin = presetBehind(sliding);
      expect(origin?.preset.id, Presets.standard.id);
      expect(origin?.discardable, isTrue);
    });

    test('finds the preset behind a caret fork, and it is not discardable', () {
      final fork = Presets.standard.fork(
        id: 'fork',
        name: '${Presets.standard.name} (sliding)',
      );
      final sliding = fork.copyWith(
        presentation: fork.presentation.copyWith(
          mode: PresentationMode.continuousScroll,
          caretStyle: CaretStyle.chevron,
        ),
      );

      final origin = presetBehind(sliding);
      expect(origin?.preset.id, Presets.standard.id);
      expect(origin?.discardable, isFalse);
    });

    test('is null for a profile matching no preset', () {
      final mine = ReadingProfile(
        id: 'mine',
        name: 'Mine',
        pacing: const PacingConfig(baseWpm: 123),
      );

      expect(presetBehind(mine), isNull);
    });
  });

  group('slidingForkOf', () {
    test('finds a matching sliding fork already in the list', () {
      final fork = Presets.standard
          .fork(id: 'fork')
          .copyWith(
            presentation: Presets.standard.presentation.copyWith(
              mode: PresentationMode.continuousScroll,
            ),
          );

      expect(slidingForkOf(Presets.standard, [fork])?.id, 'fork');
    });

    test('skips a fork that is not in sliding mode', () {
      final fork = Presets.standard.fork(id: 'fork');

      expect(slidingForkOf(Presets.standard, [fork]), isNull);
    });

    test('is null when nothing in the list matches', () {
      expect(slidingForkOf(Presets.standard, [_mine()]), isNull);
    });
  });

  group('decideMode', () {
    test('a stored profile is edited in place', () {
      final mine = _mine();

      final decision = decideMode(
        profile: mine,
        mode: PresentationMode.continuousScroll,
        profiles: [mine],
      );

      expect(decision, isA<SaveInPlace>());
      final saved = (decision as SaveInPlace).profile;
      expect(saved.id, 'mine');
      expect(saved.presentation.mode, PresentationMode.continuousScroll);
    });

    test('a preset is forked, and the fork is named after the mode', () {
      final decision = decideMode(
        profile: Presets.standard,
        mode: PresentationMode.continuousScroll,
        profiles: const [],
      );

      expect(decision, isA<ForkAndSelect>());
      final forked = (decision as ForkAndSelect).profile;
      expect(forked.isBuiltIn, isFalse);
      expect(forked.presentation.mode, PresentationMode.continuousScroll);
      expect(forked.name, '${Presets.standard.name} (sliding)');
    });

    test(
      'turning sliding off on the reader\'s own profile edits it in place',
      () {
        // A baseWpm distinct from every preset's, so this matches none of them
        // and the switch treats it like any other setting rather than a fork.
        final mine = ReadingProfile(
          id: 'mine',
          name: 'Mine',
          pacing: const PacingConfig(baseWpm: 123),
          presentation: const PresentationConfig(
            mode: PresentationMode.continuousScroll,
          ),
        );

        final decision = decideMode(
          profile: mine,
          mode: PresentationMode.fixedSingle,
          profiles: [mine],
        );

        expect(decision, isA<SaveInPlace>());
        final saved = (decision as SaveInPlace).profile;
        expect(saved.id, 'mine');
        expect(saved.presentation.mode, PresentationMode.fixedSingle);
      },
    );

    test('a fork carrying caret settings is kept, and reused', () {
      final fork = Presets.standard.fork(
        id: 'fork',
        name: '${Presets.standard.name} (sliding)',
      );
      final sliding = fork.copyWith(
        presentation: fork.presentation.copyWith(
          mode: PresentationMode.continuousScroll,
          caretStyle: CaretStyle.chevron,
        ),
      );

      // Off: the caret fork is kept, not discarded.
      final off = decideMode(
        profile: sliding,
        mode: PresentationMode.fixedSingle,
        profiles: [sliding],
      );
      expect(off, isA<ReturnToPreset>());
      final returned = off as ReturnToPreset;
      expect(returned.preset.id, Presets.standard.id);
      expect(returned.discard, isNull);

      // On again, from the preset: the same fork is reused rather than
      // forked a second time.
      final on = decideMode(
        profile: Presets.standard,
        mode: PresentationMode.continuousScroll,
        profiles: [sliding],
      );
      expect(on, isA<SelectExistingFork>());
      expect((on as SelectExistingFork).fork.id, 'fork');
    });

    test(
      'turning sliding on and then off returns to the Preset started from',
      () {
        final on = decideMode(
          profile: Presets.standard,
          mode: PresentationMode.continuousScroll,
          profiles: const [],
        );
        expect(on, isA<ForkAndSelect>());
        final fork = (on as ForkAndSelect).profile;

        final off = decideMode(
          profile: fork,
          mode: PresentationMode.fixedSingle,
          profiles: [fork],
        );

        expect(off, isA<ReturnToPreset>());
        final returned = off as ReturnToPreset;
        expect(returned.preset.id, Presets.standard.id);
        // Nothing the reader chose was in it, so it is safe to discard.
        expect(returned.discard?.id, fork.id);
      },
    );
  });
}
