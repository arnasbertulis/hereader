import 'package:rsvp_engine/rsvp_engine.dart';
import 'package:test/test.dart';

void main() {
  const run = TokenRun(firstIndex: 10, advances: [20, 30, 40], meanAdvance: 25);

  test('reports the window it covers', () {
    expect(run.firstIndex, 10);
    expect(run.lastIndex, 12);
    expect(run.contains(9), isFalse);
    expect(run.contains(10), isTrue);
    expect(run.contains(12), isTrue);
    expect(run.contains(13), isFalse);
  });

  test('measured advances come back exactly', () {
    expect(run.advanceAt(10), 20);
    expect(run.advanceAt(11), 30);
    expect(run.advanceAt(12), 40);
  });

  test('a token outside the window falls back to the mean', () {
    expect(run.advanceAt(0), 25);
    expect(run.advanceAt(999), 25);
    expect(run.advanceAt(-1), 25);
  });

  test('a zero-width measurement falls back rather than returning zero', () {
    // A caller walks a distance by repeated subtraction, so a zero advance
    // would spin forever rather than crossing a token.
    const degenerate = TokenRun(
      firstIndex: 0,
      advances: [0, 10],
      meanAdvance: 8,
    );
    expect(degenerate.advanceAt(0), 8);
  });

  test('the empty run has no window and a usable divisor', () {
    expect(TokenRun.empty.contains(0), isFalse);
    expect(TokenRun.empty.advanceAt(0), greaterThan(0));
  });
}
