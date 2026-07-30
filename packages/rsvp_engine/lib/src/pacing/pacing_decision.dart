sealed class PacingDecision {
  const PacingDecision();
}

final class Hold extends PacingDecision {
  final Duration display;
  final Duration pauseAfter;
  const Hold(this.display, {this.pauseAfter = Duration.zero});

  Duration get total => display + pauseAfter;
}

final class AwaitAdvance extends PacingDecision {
  const AwaitAdvance();
}