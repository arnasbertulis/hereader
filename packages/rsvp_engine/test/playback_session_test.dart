import 'package:fake_async/fake_async.dart';
import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

/// "one two three four five." at 300 wpm is 200ms per token.
List<Token> _tokens() => const [
  Token(text: 'one', charOffset: 0),
  Token(text: 'two', charOffset: 4),
  Token(text: 'three', charOffset: 8),
  Token(text: 'four', charOffset: 14),
  Token(text: 'five.', charOffset: 19, pauseAfter: PauseAfter.sentence),
];

ReadingProfile _profile({
  PacingModelKind kind = PacingModelKind.constant,
  int rewindWords = 2,
  Duration sentencePause = const Duration(milliseconds: 220),
}) => ReadingProfile(
  id: 'test',
  name: 'Test',
  rewindWords: rewindWords,
  pacing: PacingConfig(kind: kind, baseWpm: 300, sentencePause: sentencePause),
);

void main() {
  group('constant pacing', () {
    test('starts idle and reports the first token', () {
      final s = PlaybackSession(tokens: _tokens(), profile: _profile());
      expect(s.state, PlaybackState.idle);
      expect(s.index, 0);
      expect(s.currentToken?.text, 'one');
      s.dispose();
    });

    test('advances one token per interval', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(), profile: _profile());
        s.play();
        expect(s.state, PlaybackState.playing);
        expect(s.index, 0);

        async.elapse(const Duration(milliseconds: 200));
        expect(s.index, 1);

        async.elapse(const Duration(milliseconds: 400));
        expect(s.index, 3);
        expect(s.currentToken?.text, 'four');

        s.dispose();
      });
    });

    test('reaches finished after the last token', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(), profile: _profile());
        s.play();
        async.elapse(const Duration(seconds: 5));

        expect(s.state, PlaybackState.finished);
        expect(s.currentToken, isNull);
        s.dispose();
      });
    });

    test('blanks the anchor during a punctuation pause', () {
      fakeAsync((async) {
        // Sentence pause on the first token so the gap is observable
        // without running to the end.
        const tokens = [
          Token(text: 'Stop.', charOffset: 0, pauseAfter: PauseAfter.sentence),
          Token(text: 'Next', charOffset: 6),
        ];
        final updates = <PlaybackUpdate>[];
        final s = PlaybackSession(tokens: tokens, profile: _profile());
        s.updates.listen(updates.add);

        s.play();
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        final gap = updates.where((u) => u.inGap).toList();
        expect(gap, isNotEmpty, reason: 'a gap update should be emitted');
        expect(gap.first.token, isNull);
        expect(gap.first.state, PlaybackState.playing);

        // Still on the same token until the pause elapses.
        expect(s.index, 0);

        async.elapse(const Duration(milliseconds: 220));
        expect(s.index, 1);
        expect(s.currentToken?.text, 'Next');

        s.dispose();
      });
    });
  });

  group('pause and resume', () {
    test('pausing stops the clock', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(), profile: _profile());
        s.play();
        async.elapse(const Duration(milliseconds: 600));
        expect(s.index, 3);

        s.pause();
        expect(s.state, PlaybackState.paused);

        async.elapse(const Duration(seconds: 10));
        expect(s.index, 3, reason: 'a paused session must not advance');

        s.dispose();
      });
    });

    test('resuming steps back by rewindWords', () {
      fakeAsync((async) {
        final s = PlaybackSession(
          tokens: _tokens(),
          profile: _profile(rewindWords: 2),
        );
        s.play();
        async.elapse(const Duration(milliseconds: 600));
        expect(s.index, 3);

        s.pause();
        s.play();
        expect(s.index, 1);
        expect(s.state, PlaybackState.playing);

        s.dispose();
      });
    });

    test('rewind on resume clamps at the first token', () {
      fakeAsync((async) {
        final s = PlaybackSession(
          tokens: _tokens(),
          profile: _profile(rewindWords: 10),
        );
        s.play();
        async.elapse(const Duration(milliseconds: 200));
        s.pause();
        s.play();

        expect(s.index, 0);
        s.dispose();
      });
    });

    test('starting from idle does not rewind', () {
      final s = PlaybackSession(
        tokens: _tokens(),
        profile: _profile(rewindWords: 3),
        startIndex: 2,
      );
      s.play();
      expect(s.index, 2);
      s.dispose();
    });

    test('explicit rewind does not compound with rewindWords', () {
      fakeAsync((async) {
        final s = PlaybackSession(
          tokens: _tokens(),
          profile: _profile(rewindWords: 2),
        );
        s.play();
        async.elapse(const Duration(milliseconds: 600));
        expect(s.index, 3);

        s.rewind();
        expect(s.index, 2, reason: 'one step back, not one plus rewindWords');

        s.dispose();
      });
    });
  });

  group('elicited pacing', () {
    test('waits for the reader and arms no timer', () {
      fakeAsync((async) {
        final s = PlaybackSession(
          tokens: _tokens(),
          profile: _profile(kind: PacingModelKind.elicited),
        );
        s.play();

        expect(s.state, PlaybackState.awaitingAdvance);

        async.elapse(const Duration(minutes: 5));
        expect(s.index, 0, reason: 'elicited pacing must never self-advance');

        s.advance();
        expect(s.index, 1);
        expect(s.state, PlaybackState.awaitingAdvance);

        s.dispose();
      });
    });

    test('pausing while awaiting advance is a real pause', () {
      final s = PlaybackSession(
        tokens: _tokens(),
        profile: _profile(kind: PacingModelKind.elicited, rewindWords: 2),
      );
      s.play();
      s.advance();
      s.advance();
      s.advance();
      expect(s.index, 3);

      s.pause();
      expect(s.state, PlaybackState.paused);

      s.play();
      expect(s.index, 1, reason: 'resume from paused applies rewindWords');
      expect(s.state, PlaybackState.awaitingAdvance);

      s.dispose();
    });

    test('advancing past the last token finishes', () {
      final s = PlaybackSession(
        tokens: _tokens(),
        profile: _profile(kind: PacingModelKind.elicited),
      );
      s.play();
      for (var i = 0; i < 10; i++) {
        s.advance();
      }
      expect(s.state, PlaybackState.finished);
      s.dispose();
    });
  });

  group('seeking', () {
    test('seekToCharOffset lands on the token containing the offset', () {
      final s = PlaybackSession(tokens: _tokens(), profile: _profile());

      s.seekToCharOffset(10); // inside "three", which starts at 8
      expect(s.currentToken?.text, 'three');

      s.seekToCharOffset(8); // exactly at its start
      expect(s.currentToken?.text, 'three');

      s.dispose();
    });

    test('an offset before the first token lands on the first token', () {
      final s = PlaybackSession(tokens: _tokens(), profile: _profile());
      s.seekToCharOffset(0);
      expect(s.index, 0);
      s.dispose();
    });

    test('an offset past the end lands on the last token', () {
      final s = PlaybackSession(tokens: _tokens(), profile: _profile());
      s.seekToCharOffset(9999);
      expect(s.currentToken?.text, 'five.');
      s.dispose();
    });

    test('seeking while playing keeps playing', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(), profile: _profile());
        s.play();
        s.seekToIndex(1);
        expect(s.state, PlaybackState.playing);

        async.elapse(const Duration(milliseconds: 200));
        expect(s.index, 2);

        s.dispose();
      });
    });

    test('seeking out of range clamps', () {
      final s = PlaybackSession(tokens: _tokens(), profile: _profile());
      s.seekToIndex(-5);
      expect(s.index, 0);
      s.seekToIndex(500);
      expect(s.index, 4);
      s.dispose();
    });
  });

  group('profile swapping', () {
    test('switching to elicited mid-session stops the timer', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(), profile: _profile());
        s.play();
        async.elapse(const Duration(milliseconds: 200));
        expect(s.index, 1);

        s.profile = _profile(kind: PacingModelKind.elicited);
        expect(s.state, PlaybackState.awaitingAdvance);

        async.elapse(const Duration(minutes: 1));
        expect(s.index, 1);

        s.dispose();
      });
    });

    test('a slower profile takes effect on the current token', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(), profile: _profile());
        s.play();

        s.profile = ReadingProfile(
          id: 'slow',
          name: 'Slow',
          pacing: const PacingConfig(baseWpm: 60), // 1000ms per token
        );

        async.elapse(const Duration(milliseconds: 400));
        expect(s.index, 0, reason: 'the new rate should already apply');

        async.elapse(const Duration(milliseconds: 700));
        expect(s.index, 1);

        s.dispose();
      });
    });
  });

  group('edge cases', () {
    test('an empty token list is finished immediately', () {
      final s = PlaybackSession(tokens: const [], profile: _profile());
      expect(s.state, PlaybackState.finished);
      expect(s.currentToken, isNull);

      s.play();
      expect(s.state, PlaybackState.finished);
      s.dispose();
    });

    test('a finished session ignores play', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(), profile: _profile());
        s.play();
        async.elapse(const Duration(seconds: 5));
        expect(s.state, PlaybackState.finished);

        s.play();
        expect(s.state, PlaybackState.finished);
        s.dispose();
      });
    });

    test('rewinding out of finished returns to a paused token', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(), profile: _profile());
        s.play();
        async.elapse(const Duration(seconds: 5));

        s.rewind(2);
        expect(s.state, PlaybackState.paused);
        expect(s.currentToken, isNotNull);

        s.dispose();
      });
    });

    test('dispose stops the clock and tolerates later calls', () {
      fakeAsync((async) {
        final s = PlaybackSession(tokens: _tokens(), profile: _profile());
        s.play();
        s.dispose();

        async.elapse(const Duration(seconds: 5));
        expect(s.index, 0);

        expect(() {
          s.pause();
          s.advance();
        }, returnsNormally);
      });
    });

    test('charOffset tracks the current token', () {
      final s = PlaybackSession(tokens: _tokens(), profile: _profile());
      s.seekToIndex(2);
      expect(s.charOffset, 8);
      s.dispose();
    });
  });

  group('current', () {
    test('describes a session nobody has touched yet', () {
      final tokens = [
        const Token(text: 'Alpha', charOffset: 0),
        const Token(text: 'beta', charOffset: 6),
        const Token(text: 'gamma', charOffset: 11),
      ];

      final session = PlaybackSession(
        tokens: tokens,
        profile: Presets.standard,
        startIndex: 1,
      );
      addTearDown(session.dispose);

      // The stream has emitted nothing, because nothing has changed. A
      // renderer with only the stream to go on draws a blank surface.
      expect(session.current.token, tokens[1]);
      expect(session.current.index, 1);
      expect(session.current.state, PlaybackState.idle);
      expect(session.current.inGap, isFalse);
    });

    test('carries no token when there is nothing to read', () {
      final session = PlaybackSession(tokens: [], profile: Presets.standard);
      addTearDown(session.dispose);

      expect(session.current.state, PlaybackState.finished);
      expect(session.current.token, isNull);
    });
  });
}
