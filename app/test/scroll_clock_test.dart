import 'package:app/reading/profile_presentation.dart';
import 'package:app/reading/scroll_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

ReadingProfile _scrollProfile() => ReadingProfile(
  id: 'test',
  name: 'Test',
  rewindWords: 2,
  pacing: PacingConfig(
    kind: PacingModelKind.constant,
    baseWpm: 300,
    paragraphPause: const Duration(milliseconds: 400),
  ),
  presentation: PresentationConfig(mode: PresentationMode.continuousScroll),
);

void main() {
  testWidgets('a font arriving re-measures the window', (tester) async {
    // On web a fallback face is fetched on demand, and a window measured
    // before it landed draws the characters it covers as nothing. The
    // engine announces the arrival as a `fontsChange` system message; the
    // clock must measure again then rather than at its next window, when the
    // missing glyphs would appear in place on screen.
    final text = TokenizedText.from([
      (id: 'one', text: List.generate(200, (i) => 'word$i').join(' ')),
    ], parserVersion: 1);
    final session = PlaybackSession(
      tokens: text.tokens,
      profile: _scrollProfile(),
    );
    final clock = ScrollClock(
      session: session,
      vsync: tester,
      tokens: text.tokens,
      isParagraphEnd: text.isParagraphEndAt,
      chapterStarts: const {},
    );
    addTearDown(() {
      clock.dispose();
      session.dispose();
    });

    clock.setViewportWidth(800);
    clock.applyPresentation(
      resolvePresentation(
        PresentationConfig(mode: PresentationMode.continuousScroll),
        Brightness.light,
      ),
    );
    final measured = clock.layout.value;
    expect(measured, isNotNull);

    await PaintingBinding.instance.handleSystemMessage(<String, Object?>{
      'type': 'fontsChange',
    });

    expect(clock.layout.value, isNotNull);
    expect(clock.layout.value, isNot(same(measured)));

    // The replaced window is disposed after a frame.
    await tester.pump();
  });
}
