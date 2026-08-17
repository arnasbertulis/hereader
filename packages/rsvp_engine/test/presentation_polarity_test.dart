import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

void main() {
  group('an unset polarity', () {
    test('is what a config carries until someone sets one', () {
      expect(const PresentationConfig().polarity, isNull);
    });

    test('takes the fallback, and a set one ignores it', () {
      const unset = PresentationConfig();
      expect(
        unset.resolvedWith(Polarity.lightOnDark).polarity,
        Polarity.lightOnDark,
      );

      const pinned = PresentationConfig(polarity: Polarity.darkOnLight);
      expect(
        pinned.resolvedWith(Polarity.lightOnDark).polarity,
        Polarity.darkOnLight,
      );
    });

    test('resolves without touching anything else', () {
      const config = PresentationConfig(
        fontSizePt: 48,
        letterSpacingEm: 0.12,
        tintArgb: 0xFF102030,
        transitionMs: 60,
      );

      final resolved = config.resolvedWith(Polarity.lightOnDark);

      expect(resolved.fontSizePt, 48);
      expect(resolved.letterSpacingEm, 0.12);
      expect(resolved.tintArgb, 0xFF102030);
      expect(resolved.transitionMs, 60);
    });
  });

  group('setting the nullable fields', () {
    // The reason both live outside copyWith: a reader turning "follow the
    // app" back on has to be able to reach null, and `?? this.polarity`
    // cannot express it.
    test('withPolarity puts a pinned profile back to unset', () {
      const pinned = PresentationConfig(polarity: Polarity.lightOnDark);
      expect(pinned.withPolarity(null).polarity, isNull);
      expect(pinned.withPolarity(Polarity.darkOnLight).polarity,
          Polarity.darkOnLight);
    });

    test('withTint clears a background the same way', () {
      const tinted = PresentationConfig(tintArgb: 0xFF102030);
      expect(tinted.withTint(null).tintArgb, isNull);
    });

    test('copyWith carries both through untouched', () {
      const config = PresentationConfig(
        polarity: Polarity.lightOnDark,
        tintArgb: 0xFF102030,
      );

      final wider = config.copyWith(letterSpacingEm: 0.1);

      expect(wider.polarity, Polarity.lightOnDark);
      expect(wider.tintArgb, 0xFF102030);
    });
  });

  group('polarity on the wire', () {
    test('an unset polarity is an absent key, not a null one', () {
      expect(
        const PresentationConfig().toJson().containsKey('polarity'),
        isFalse,
      );
    });

    test('a set polarity travels by name', () {
      const config = PresentationConfig(polarity: Polarity.lightOnDark);
      expect(config.toJson()['polarity'], 'lightOnDark');
    });

    test('unset survives a round trip', () {
      final json = const PresentationConfig().toJson();
      expect(PresentationConfig.fromJson(json).polarity, isNull);
    });

    test('a payload written before this field keeps its polarity', () {
      // Every build up to this one wrote the key on every profile, so a
      // reader's stored profiles stay on the surface they already read on.
      // Nothing about the app's theme reaches them. This is the migration:
      // presentation is a JSON column, so there is no schema step to run.
      final config = PresentationConfig.fromJson(const <String, dynamic>{
        'mode': 'fixedSingle',
        'anchorX': 0.5,
        'anchorY': 0.5,
        'fontSizePt': 44.0,
        'letterSpacingEm': 0.0,
        'chunkSize': 1,
        'polarity': 'darkOnLight',
        'orpHighlight': false,
        'transitionMs': 0,
      });

      expect(config.polarity, Polarity.darkOnLight);
    });

    test('a name this build cannot read means unset', () {
      expect(
        PresentationConfig.fromJson(
          const <String, dynamic>{'polarity': 'sepiaOnCream'},
        ).polarity,
        isNull,
      );

      expect(
        PresentationConfig.fromJson(
          const <String, dynamic>{'polarity': 7},
        ).polarity,
        isNull,
      );
    });

    test('a whole profile round trips both states', () {
      final standard = ReadingProfile.fromJson(Presets.standard.toJson());
      expect(standard.presentation.polarity, isNull);

      final cfl = ReadingProfile.fromJson(Presets.centralFieldLoss.toJson());
      expect(cfl.presentation.polarity, Polarity.lightOnDark);
    });
  });

  group('presets', () {
    test('the ones whose citations pick a surface state it', () {
      const cited = [
        Presets.centralFieldLoss,
        Presets.centralFieldLossTimed,
        Presets.lowFatigue,
      ];

      for (final preset in cited) {
        expect(
          preset.presentation.polarity,
          Polarity.lightOnDark,
          reason:
              '${preset.id} is picked for its reversed surface. Leaving its '
              'polarity unset would let a light app theme override it.',
        );
      }
    });

    test('the ones with nothing to say about polarity follow the app', () {
      expect(Presets.standard.presentation.polarity, isNull);
      expect(Presets.spacedType.presentation.polarity, isNull);
    });

    test('a fork keeps whichever state its preset was in', () {
      final followed = Presets.standard.fork(id: 'p.1.00000001');
      expect(followed.presentation.polarity, isNull);

      final pinned = Presets.centralFieldLoss.fork(id: 'p.1.00000002');
      expect(pinned.presentation.polarity, Polarity.lightOnDark);
    });
  });
}
