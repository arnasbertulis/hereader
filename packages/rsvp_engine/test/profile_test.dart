import 'dart:convert';

import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

/// `PacingConfig` and `PresentationConfig` define no `==`, so their round
/// trips compare JSON. `ReadingProfile` has value equality; its round trip
/// below compares the objects directly.
void main() {
  group('PacingConfig serialization', () {
    test('round trips through JSON', () {
      const original = PacingConfig(
        kind: PacingModelKind.lengthScaled,
        baseWpm: 173,
        referenceLetterCount: 6.5,
        lengthScaleStrength: 0.4,
        clausePause: Duration(milliseconds: 111),
        sentencePause: Duration(milliseconds: 222),
        paragraphPause: Duration(milliseconds: 333),
        minDisplay: Duration(milliseconds: 44),
        maxDisplay: Duration(milliseconds: 999),
      );

      final restored = PacingConfig.fromJson(original.toJson());

      expect(restored.toJson(), equals(original.toJson()));
      expect(restored.kind, PacingModelKind.lengthScaled);
      expect(restored.baseWpm, 173);
      expect(restored.sentencePause, const Duration(milliseconds: 222));
    });

    test('survives a real encode/decode cycle', () {
      const original = PacingConfig(kind: PacingModelKind.elicited);
      final decoded = jsonDecode(jsonEncode(original.toJson()));
      final restored = PacingConfig.fromJson(decoded as Map<String, dynamic>);
      expect(restored.kind, PacingModelKind.elicited);
    });

    test('unknown pacing kind falls back to constant', () {
      final restored = PacingConfig.fromJson({'kind': 'quantumPacing'});
      expect(restored.kind, PacingModelKind.constant);
    });

    test('empty JSON yields defaults', () {
      final restored = PacingConfig.fromJson({});
      expect(restored.toJson(), equals(const PacingConfig().toJson()));
    });
  });

  group('PresentationConfig serialization', () {
    test('round trips through JSON', () {
      const original = PresentationConfig(
        anchorX: 0.35,
        anchorY: 0.6,
        fontFamily: 'Atkinson Hyperlegible',
        fontSizePt: 52,
        letterSpacingEm: 0.15,
        polarity: Polarity.lightOnDark,
        tintArgb: 0xFF1A1A1A,
        orpHighlight: true,
        transitionMs: 80,
      );

      final restored = PresentationConfig.fromJson(original.toJson());

      expect(restored.toJson(), equals(original.toJson()));
      expect(restored.fontFamily, 'Atkinson Hyperlegible');
      expect(restored.tintArgb, 0xFF1A1A1A);
    });

    test('omits null optionals rather than writing nulls', () {
      const original = PresentationConfig();
      expect(original.toJson().containsKey('fontFamily'), isFalse);
      expect(original.toJson().containsKey('tintArgb'), isFalse);
    });

    test('an unknown mode falls back', () {
      final restored = PresentationConfig.fromJson({'mode': 'holographic'});
      expect(restored.mode, PresentationMode.fixedSingle);
    });

    test('rejects chunkSize above 1', () {
      expect(
        () => PresentationConfig(chunkSize: 3),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects an anchor outside the surface', () {
      expect(
        () => PresentationConfig(anchorX: 1.4),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ReadingProfile', () {
    const profile = ReadingProfile(
      id: 'test.profile',
      name: 'Test',
      pacing: PacingConfig(baseWpm: 190),
      presentation: PresentationConfig(fontSizePt: 44),
      rewindWords: 4,
    );

    test('round trips through JSON', () {
      final restored = ReadingProfile.fromJson(profile.toJson());
      expect(restored, equals(profile));
      expect(restored.pacing.baseWpm, 190);
      expect(restored.presentation.fontSizePt, 44);
      expect(restored.rewindWords, 4);
    });

    test('missing nested configs fall back to defaults', () {
      final restored = ReadingProfile.fromJson({'id': 'bare', 'name': 'Bare'});
      expect(restored.pacing.toJson(), equals(const PacingConfig().toJson()));
      expect(
        restored.presentation.toJson(),
        equals(const PresentationConfig().toJson()),
      );
    });

    test('copyWith leaves untouched fields alone', () {
      final edited = profile.copyWith(name: 'Renamed');
      expect(edited.name, 'Renamed');
      expect(edited.id, 'test.profile');
      expect(edited.pacing.baseWpm, 190);
    });

    test('fork produces an editable copy under a new id', () {
      final forked = Presets.standard.fork(id: 'user.001');

      expect(forked.id, 'user.001');
      expect(forked.isBuiltIn, isFalse);
      expect(forked.name, 'Standard (copy)');
      expect(forked.pacing.toJson(), equals(Presets.standard.pacing.toJson()));
    });

    test('fork accepts an explicit name', () {
      final forked = Presets.standard.fork(id: 'user.002', name: 'Evenings');
      expect(forked.name, 'Evenings');
    });
  });

  group('ReadingProfile equality', () {
    const base = ReadingProfile(
      id: 'test.profile',
      name: 'Test',
      pacing: PacingConfig(baseWpm: 190),
      presentation: PresentationConfig(fontSizePt: 44),
      rewindWords: 4,
    );

    ReadingProfile identicalCopy() => const ReadingProfile(
      id: 'test.profile',
      name: 'Test',
      pacing: PacingConfig(baseWpm: 190),
      presentation: PresentationConfig(fontSizePt: 44),
      rewindWords: 4,
    );

    test('profiles built with identical field values compare equal and hash '
        'equal', () {
      final other = identicalCopy();
      expect(other, equals(base));
      expect(other.hashCode, equals(base.hashCode));
    });

    test('a profile compares equal to itself', () {
      expect(base, equals(base));
    });

    test('a profile compares unequal to a fork of itself', () {
      final forked = base.fork(id: 'user.forked');
      expect(forked, isNot(equals(base)));
    });

    test('a difference in id makes profiles unequal', () {
      expect(base.copyWith(id: 'other.id'), isNot(equals(base)));
    });

    test('a difference in name makes profiles unequal', () {
      expect(base.copyWith(name: 'Other'), isNot(equals(base)));
    });

    test('a difference in pacing makes profiles unequal', () {
      expect(
        base.copyWith(pacing: const PacingConfig(baseWpm: 300)),
        isNot(equals(base)),
      );
    });

    test('a difference in presentation makes profiles unequal', () {
      expect(
        base.copyWith(presentation: const PresentationConfig(fontSizePt: 60)),
        isNot(equals(base)),
      );
    });

    test('a difference in rewindWords makes profiles unequal', () {
      expect(base.copyWith(rewindWords: 0), isNot(equals(base)));
    });

    test('equality agrees with what the profile serialises to', () {
      // A round trip through JSON produces a distinct object graph — new
      // PacingConfig and PresentationConfig instances — that must still
      // compare equal, because equality is defined in terms of toJson.
      final restored = ReadingProfile.fromJson(base.toJson());
      expect(restored, equals(base));
      expect(restored.toJson(), equals(base.toJson()));
    });
  });

  group('Presets', () {
    test('ids are unique', () {
      final ids = Presets.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('all are marked built in', () {
      expect(Presets.all.every((p) => p.isBuiltIn), isTrue);
    });

    test('every preset survives a round trip', () {
      for (final p in Presets.all) {
        final restored = ReadingProfile.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>,
        );
        expect(
          restored.toJson(),
          equals(p.toJson()),
          reason: 'broke on ${p.id}',
        );
      }
    });

    test('byId finds a preset and returns null otherwise', () {
      expect(Presets.byId('builtin.standard')?.name, 'Standard');
      expect(Presets.byId('nope'), isNull);
    });

    test('the central field loss preset uses reader-elicited advance', () {
      // Arditi 1999. If this ever changes, the change should be deliberate.
      expect(Presets.centralFieldLoss.pacing.kind, PacingModelKind.elicited);
    });

    test('the timed alternative scales by word length', () {
      // Aquilante et al. 2001.
      expect(
        Presets.centralFieldLossTimed.pacing.kind,
        PacingModelKind.lengthScaled,
      );
    });

    test('the default preset uses a constant rate', () {
      expect(Presets.standard.pacing.kind, PacingModelKind.constant);
    });
  });

  group('the scroll caret', () {
    test('defaults to one above and one below, solid, clear of the line', () {
      const config = PresentationConfig();

      expect(config.caretPlacement, CaretPlacement.both);
      expect(config.caretStyle, CaretStyle.filled);
      expect(config.caretGapEm, greaterThan(0));
      expect(config.caretScale, 1);
      expect(config.caretThicknessEm, greaterThan(0));
    });

    test('round-trips through JSON', () {
      const config = PresentationConfig(
        mode: PresentationMode.continuousScroll,
        caretPlacement: CaretPlacement.above,
        caretStyle: CaretStyle.chevron,
        caretGapEm: 0.6,
        caretThicknessEm: 0.2,
        caretScale: 1.8,
      );

      final back = PresentationConfig.fromJson(config.toJson());

      expect(back.caretPlacement, CaretPlacement.above);
      expect(back.caretStyle, CaretStyle.chevron);
      expect(back.caretGapEm, 0.6);
      expect(back.caretThicknessEm, 0.2);
      expect(back.caretScale, 1.8);
    });

    test('copyWith carries them across', () {
      const config = PresentationConfig(
        caretPlacement: CaretPlacement.below,
        caretStyle: CaretStyle.outline,
        caretGapEm: 0.4,
        caretThicknessEm: 0.25,
        caretScale: 0.75,
      );

      final same = config.copyWith(fontSizePt: 60);

      expect(same.caretPlacement, CaretPlacement.below);
      expect(same.caretStyle, CaretStyle.outline);
      expect(same.caretGapEm, 0.4);
      expect(same.caretThicknessEm, 0.25);
      expect(same.caretScale, 0.75);

      // And the tint setter, which rebuilds the whole object by hand.
      final tinted = config.withTint(0xFF102030);
      expect(tinted.caretStyle, CaretStyle.outline);
      expect(tinted.caretGapEm, 0.4);
      expect(tinted.caretThicknessEm, 0.25);
      expect(tinted.caretScale, 0.75);
    });

    test('the wire clamps rather than throwing', () {
      // A later build could send a gap this one does not offer, or a name it
      // does not know. Neither may lose the rest of the profile; see the
      // json_coerce note in the package README.
      final wide = PresentationConfig.fromJson({'caretGapEm': 9.0});
      expect(wide.caretGapEm, 1);

      final negative = PresentationConfig.fromJson({'caretGapEm': -3.0});
      expect(negative.caretGapEm, 0);

      final unknown = PresentationConfig.fromJson({
        'caretPlacement': 'sideways',
        'caretStyle': 'sparkle',
      });
      expect(unknown.caretPlacement, CaretPlacement.both);
      expect(unknown.caretStyle, CaretStyle.filled);

      // A thickness of zero draws nothing and a caret larger than a line of
      // text stops marking a place in it, so both move to the nearest bound
      // the editor itself offers.
      final heavy = PresentationConfig.fromJson({'caretThicknessEm': 4.0});
      expect(heavy.caretThicknessEm, PresentationConfig.maxCaretThicknessEm);

      final invisible = PresentationConfig.fromJson({'caretThicknessEm': 0.0});
      expect(
        invisible.caretThicknessEm,
        PresentationConfig.minCaretThicknessEm,
      );

      final huge = PresentationConfig.fromJson({'caretScale': 40.0});
      expect(huge.caretScale, PresentationConfig.maxCaretScale);

      final tiny = PresentationConfig.fromJson({'caretScale': -1.0});
      expect(tiny.caretScale, PresentationConfig.minCaretScale);
    });

    test('a profile written before these fields reads the defaults', () {
      const old = PresentationConfig();
      final json = old.toJson()
        ..remove('caretPlacement')
        ..remove('caretStyle')
        ..remove('caretGapEm')
        ..remove('caretThicknessEm')
        ..remove('caretScale');

      final back = PresentationConfig.fromJson(json);

      expect(back.caretPlacement, old.caretPlacement);
      expect(back.caretStyle, old.caretStyle);
      expect(back.caretGapEm, old.caretGapEm);
      expect(back.caretThicknessEm, old.caretThicknessEm);
      expect(back.caretScale, old.caretScale);
    });
  });
}
