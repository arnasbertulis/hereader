import 'dart:convert';

import 'package:test/test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

/// These classes define no `==`, so round trips compare their JSON. If value
/// equality is added later, these can compare objects directly.
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
      final restored =
          PacingConfig.fromJson(decoded as Map<String, dynamic>);
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

    test('unknown mode and polarity fall back', () {
      final restored = PresentationConfig.fromJson({
        'mode': 'holographic',
        'polarity': 'sepiaOnMauve',
      });
      expect(restored.mode, PresentationMode.fixedSingle);
      expect(restored.polarity, Polarity.darkOnLight);
    });

    test('rejects chunkSize above 1', () {
      expect(() => PresentationConfig(chunkSize: 3), throwsA(isA<AssertionError>()));
    });

    test('rejects an anchor outside the surface', () {
      expect(() => PresentationConfig(anchorX: 1.4), throwsA(isA<AssertionError>()));
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
      expect(restored.toJson(), equals(profile.toJson()));
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
        expect(restored.toJson(), equals(p.toJson()), reason: 'broke on ${p.id}');
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
}
