import 'package:fake_async/fake_async.dart';
import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

/// Six tokens. The gaps in the text are irrelevant to a marquee's timing and
/// several of these carry one, which is the point of the velocity tests.
List<Token> _tokens() => const [
  Token(text: 'one', charOffset: 0),
  Token(text: 'two,', charOffset: 4, pauseAfter: PauseAfter.clause),
  Token(text: 'three', charOffset: 9),
  Token(text: 'four.', charOffset: 15, pauseAfter: PauseAfter.paragraph),
  Token(text: 'five', charOffset: 21),
  Token(text: 'six', charOffset: 26),
];

/// Every token 20px wide, so at 300 wpm the velocity is
/// `(300 / 60) * 20` = 100 px/s and a token takes exactly 200ms — the same
/// figure `playback_session_test.dart` uses for the fixed anchor.
TokenRun _evenRun() => const TokenRun(
  firstIndex: 0,
  advances: [20, 20, 20, 20, 20, 20],
  meanAdvance: 20,
);

/// Token 1 is three times as wide as its neighbours, and the mean is left at
/// 20 so that a walk using the mean and a walk using the measurement land in
/// visibly different places.
TokenRun _unevenRun() => const TokenRun(
  firstIndex: 0,
  advances: [20, 60, 20, 20, 20, 20],
  meanAdvance: 20,
);

ReadingProfile _profile({
  PresentationMode mode = PresentationMode.continuousScroll,
  PacingModelKind kind = PacingModelKind.constant,
  int rewindWords = 2,
  Duration paragraphPause = const Duration(milliseconds: 400),
}) => ReadingProfile(
  id: 'test',
  name: 'Test',
  rewindWords: rewindWords,
  pacing: PacingConfig(
    kind: kind,
    baseWpm: 300,
    paragraphPause: paragraphPause,
  ),
  presentation: PresentationConfig(mode: mode),
);

PlaybackSession _session({
  ReadingProfile? profile,
  TokenRun? run,
  int startIndex = 0,
}) {
  final s = PlaybackSession(
    tokens: _tokens(),
    profile: profile ?? _profile(),
    startIndex: startIndex,
  );
  s.run = run ?? _evenRun();
  return s;
}

void main() {
  group('the timer chain is off', () {
    test(
      'scrolling is derived from the profile, not fixed at construction',
      () {
        final s = _session();
        expect(s.scrolling, isTrue);

        s.profile = _profile(mode: PresentationMode.fixedSingle);
        expect(s.scrolling, isFalse);
        s.dispose();
      },
    );

    test('playing arms no timer, so nothing advances without a tick', () {
      fakeAsync((async) {
        final s = _session();
        s.play();
        expect(s.state, PlaybackState.playing);

        async.elapse(const Duration(hours: 1));

        expect(s.index, 0, reason: 'a timer fired and moved the index');
        expect(s.state, PlaybackState.playing);
        s.dispose();
      });
    });

    test('switching to a fixed anchor while playing arms the chain', () {
      fakeAsync((async) {
        final s = _session();
        s.play();
        async.elapse(const Duration(hours: 1));
        expect(s.index, 0);

        s.profile = _profile(mode: PresentationMode.fixedSingle);
        async.elapse(const Duration(milliseconds: 200));
        expect(s.index, 1);
        s.dispose();
      });
    });

    test('switching to scroll while playing cancels the chain', () {
      fakeAsync((async) {
        final s = PlaybackSession(
          tokens: _tokens(),
          profile: _profile(mode: PresentationMode.fixedSingle),
        );
        s.run = _evenRun();
        s.play();
        async.elapse(const Duration(milliseconds: 200));
        expect(s.index, 1);

        s.profile = _profile();
        async.elapse(const Duration(hours: 1));
        expect(s.index, 1);
        expect(s.state, PlaybackState.playing);
        s.dispose();
      });
    });

    test('leaving scroll mode drops the sub-token offset', () {
      final s = _session();
      s.play();
      s.tick(const Duration(milliseconds: 100));
      expect(s.tokenOffset, closeTo(10, 0.001));

      s.profile = _profile(mode: PresentationMode.fixedSingle);
      expect(s.tokenOffset, 0);
      s.dispose();
    });
  });

  group('velocity', () {
    test('equal elapsed times move equal distance across every boundary', () {
      final s = _session();
      s.play();

      // Token 3 ends a paragraph and token 1 ends a clause. Both cross on the
      // same 200ms as the plain tokens either side of them.
      for (var i = 1; i < 6; i++) {
        s.tick(const Duration(milliseconds: 200));
        expect(s.index, i, reason: 'crossing into token $i');
        expect(s.tokenOffset, closeTo(0, 0.001));
      }
      s.dispose();
    });

    test('a long paragraph pause changes nothing', () {
      final long = _session(
        profile: _profile(paragraphPause: const Duration(seconds: 2)),
      );
      final short = _session(profile: _profile(paragraphPause: Duration.zero));
      long.play();
      short.play();

      // Across token 3, which is the paragraph end.
      for (var i = 0; i < 5; i++) {
        long.tick(const Duration(milliseconds: 200));
        short.tick(const Duration(milliseconds: 200));
      }
      expect(long.index, short.index);
      expect(long.index, 5);
      long.dispose();
      short.dispose();
    });

    test('velocity is baseWpm times the mean advance', () {
      final s = _session();
      expect(s.scrollVelocity, closeTo(100, 0.001));

      s.run = const TokenRun(
        firstIndex: 0,
        advances: [40, 40, 40, 40, 40, 40],
        meanAdvance: 40,
      );
      expect(s.scrollVelocity, closeTo(200, 0.001));
      s.dispose();
    });

    test('a token crosses at its own advance, not at the mean', () {
      final s = _session(run: _unevenRun());
      s.play();

      // 200ms clears token 0 at 20px.
      s.tick(const Duration(milliseconds: 200));
      expect(s.index, 1);

      // Token 1 is 60px, so it takes 600ms. At the mean it would have gone
      // three tokens by now.
      s.tick(const Duration(milliseconds: 400));
      expect(s.index, 1);
      expect(s.tokenOffset, closeTo(40, 0.001));

      s.tick(const Duration(milliseconds: 200));
      expect(s.index, 2);
      s.dispose();
    });

    test('a tick is ignored unless scrolling and playing', () {
      final paused = _session();
      paused.tick(const Duration(seconds: 1));
      expect(paused.index, 0);
      expect(paused.tokenOffset, 0);
      paused.dispose();

      final fixed = _session(
        profile: _profile(mode: PresentationMode.fixedSingle),
      );
      fixed.play();
      fixed.tick(const Duration(seconds: 1));
      expect(fixed.tokenOffset, 0);
      fixed.dispose();
    });

    test('running off the last token finishes', () {
      final s = _session(startIndex: 5);
      s.play();
      s.tick(const Duration(seconds: 1));

      expect(s.state, PlaybackState.finished);
      expect(s.currentToken, isNull);
      expect(s.tokenOffset, 0);
      s.dispose();
    });
  });

  group('scrubbing', () {
    test('forward and back by the same distance returns to the same place', () {
      // Token 1 is 60px, so 75px crosses it and lands 15px into token 2.
      final s = _session(run: _unevenRun(), startIndex: 1);
      s.scrubBy(75);
      expect(s.index, 2);
      expect(s.tokenOffset, closeTo(15, 0.001));

      s.scrubBy(-75);
      expect(s.index, 1);
      expect(s.tokenOffset, closeTo(0, 0.001));
      s.dispose();
    });

    test('a round trip from mid-token also returns exactly', () {
      final s = _session(run: _unevenRun(), startIndex: 0);
      s.scrubBy(12);
      final index = s.index;
      final offset = s.tokenOffset;

      s.scrubBy(73);
      s.scrubBy(-73);

      expect(s.index, index);
      expect(s.tokenOffset, closeTo(offset, 0.001));
      s.dispose();
    });

    test('backward clamps at the first token', () {
      final s = _session(startIndex: 2);
      s.scrubBy(-10000);
      expect(s.index, 0);
      expect(s.tokenOffset, 0);
      s.dispose();
    });

    test('forward clamps at the last token without finishing', () {
      final s = _session();
      s.scrubBy(10000);
      expect(s.index, 5);
      expect(s.tokenOffset, 0);
      expect(s.state, isNot(PlaybackState.finished));
      s.dispose();
    });

    test('scrubbing back off the end leaves the terminal state', () {
      final s = _session(startIndex: 5);
      s.play();
      s.tick(const Duration(seconds: 1));
      expect(s.state, PlaybackState.finished);

      // 30px back from the leading edge of the last token, at 20px a token.
      s.scrubBy(-30);
      expect(s.state, PlaybackState.paused);
      expect(s.index, 3);
      expect(s.tokenOffset, closeTo(10, 0.001));
      s.dispose();
    });

    test('a scrub does not arm the rewind suppression; the release does', () {
      final s = _session(startIndex: 3);
      s.play();
      s.pause();
      s.scrubBy(-20);
      expect(s.index, 2);

      // Still a plain pause, so resuming rewinds as it always did.
      s.play();
      expect(s.index, 0);
      s.dispose();
    });

    test('stopHere suppresses exactly one rewind', () {
      final s = _session(startIndex: 3);
      s.play();
      s.pause();
      s.scrubBy(-20);
      s.stopHere();

      s.play();
      expect(s.index, 2, reason: 'the release should hold the position');

      s.pause();
      s.play();
      expect(s.index, 0, reason: 'the suppression lasts one resume');
      s.dispose();
    });

    test('a scroll session ignores a scrub under a fixed anchor', () {
      final s = _session(profile: _profile(mode: PresentationMode.fixedSingle));
      s.scrubBy(100);
      expect(s.index, 0);
      s.dispose();
    });

    test('the direction is: positive is forward', () {
      final s = _session(startIndex: 2);
      s.scrubBy(20);
      expect(s.index, 3);
      s.scrubBy(-20);
      expect(s.index, 2);
      s.dispose();
    });
  });

  group('the offset and the seeks', () {
    test('stopHere keeps the offset where stopAt drops it', () {
      final held = _session();
      held.play();
      held.tick(const Duration(milliseconds: 100));
      expect(held.tokenOffset, closeTo(10, 0.001));
      held.stopHere();
      expect(held.tokenOffset, closeTo(10, 0.001));
      expect(held.index, 0);
      expect(held.state, PlaybackState.paused);
      held.dispose();

      final snapped = _session();
      snapped.play();
      snapped.tick(const Duration(milliseconds: 100));
      snapped.stopAt(0);
      expect(snapped.tokenOffset, 0);
      snapped.dispose();
    });

    test('a pause keeps the offset, so a finger landing does not snap', () {
      final s = _session();
      s.play();
      s.tick(const Duration(milliseconds: 150));
      s.pause();
      expect(s.tokenOffset, closeTo(15, 0.001));
      s.dispose();
    });

    test('every jump lands on a leading edge', () {
      for (final jump in <void Function(PlaybackSession)>[
        (s) => s.seekToIndex(4),
        (s) => s.stopAt(4),
        (s) => s.rewind(),
        (s) => s.advance(),
      ]) {
        final s = _session(startIndex: 2);
        s.play();
        s.tick(const Duration(milliseconds: 100));
        expect(s.tokenOffset, greaterThan(0));

        jump(s);
        expect(s.tokenOffset, 0);
        s.dispose();
      }
    });

    test('a resume rewind lands on a leading edge too', () {
      final s = _session(startIndex: 3);
      s.play();
      s.tick(const Duration(milliseconds: 100));
      s.pause();
      s.play();

      expect(s.index, 1);
      expect(s.tokenOffset, 0);
      s.dispose();
    });

    test('the update and the seed both carry the offset', () async {
      final s = _session();
      s.play();

      final seen = <double>[];
      final sub = s.updates.listen((u) => seen.add(u.tokenOffset));

      s.tick(const Duration(milliseconds: 50));
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, closeTo(5, 0.001));
      expect(s.current.tokenOffset, closeTo(5, 0.001));

      await sub.cancel();
      s.dispose();
    });
  });

  group('new geometry', () {
    test('a wider run holds the anchor at the same fraction of the word', () {
      final s = _session();
      s.play();
      s.tick(const Duration(milliseconds: 100));
      expect(s.tokenOffset, closeTo(10, 0.001));

      // Type size doubled: every advance doubles, so half of token 0 is now
      // 20px rather than 10.
      s.run = const TokenRun(
        firstIndex: 0,
        advances: [40, 40, 40, 40, 40, 40],
        meanAdvance: 40,
      );
      expect(s.tokenOffset, closeTo(20, 0.001));
      expect(s.index, 0);
      s.dispose();
    });

    test('a run that no longer covers the anchor falls back to the mean', () {
      final s = _session(startIndex: 0);
      s.play();
      s.tick(const Duration(milliseconds: 100));

      s.run = const TokenRun(
        firstIndex: 3,
        advances: [20, 20, 20],
        meanAdvance: 20,
      );
      expect(s.tokenOffset, closeTo(10, 0.001));
      s.dispose();
    });
  });

  group('elicited pacing under scroll', () {
    test('scroll wins: it plays and never waits for the reader', () {
      final s = _session(profile: _profile(kind: PacingModelKind.elicited));
      s.play();
      expect(s.state, PlaybackState.playing);

      for (var i = 0; i < 5; i++) {
        s.tick(const Duration(milliseconds: 200));
        expect(s.state, isNot(PlaybackState.awaitingAdvance));
      }
      expect(s.index, 5);
      s.dispose();
    });

    test('the same profile does wait under a fixed anchor', () {
      final s = _session(
        profile: _profile(
          kind: PacingModelKind.elicited,
          mode: PresentationMode.fixedSingle,
        ),
      );
      s.play();
      expect(s.state, PlaybackState.awaitingAdvance);
      s.dispose();
    });
  });
}
