// Measures how far the playback timer chain drifts from its schedule on the
// real clock.
//
// A one-off script, not a test: `dart test` and CI never run it, because it
// takes minutes of wall time and its answer depends on the machine.
//
//   dart run tool/measure_drift.dart [--wpm 300] [--tokens 2000]
//
// It drives a [PlaybackSession] from play to finished over a synthetic run of
// tokens (a clause pause every 7th token, a sentence pause every 13th, a
// paragraph pause every 61st), sums the holds the pacing model asked for, and
// compares that with the wall time the session actually took. The drift is
// the difference, as a percentage of the schedule and as milliseconds per
// token.
import 'dart:async';
import 'dart:io';

import 'package:rsvp_engine/rsvp_engine.dart';

Future<void> main(List<String> args) async {
  final wpm = double.parse(_option(args, '--wpm') ?? '300');
  final count = int.parse(_option(args, '--tokens') ?? '2000');

  final tokens = [
    for (var i = 0; i < count; i++)
      Token(
        text: 'word$i',
        charOffset: i * 8,
        pauseAfter: (i + 1) % 61 == 0
            ? PauseAfter.paragraph
            : (i + 1) % 13 == 0
            ? PauseAfter.sentence
            : (i + 1) % 7 == 0
            ? PauseAfter.clause
            : PauseAfter.none,
      ),
  ];
  final profile = ReadingProfile(
    id: 'measure',
    name: 'Measure',
    pacing: PacingConfig(kind: PacingModelKind.constant, baseWpm: wpm),
  );

  // The schedule: what the pacing model asked for, token by token. Both the
  // display and the gap after it are separate timers when the gap is nonzero.
  final model = PacingModel.of(profile.pacing.kind);
  var scheduled = Duration.zero;
  var timers = 0;
  for (final token in tokens) {
    final decision = model.decide(token, profile.pacing) as Hold;
    scheduled += decision.total;
    timers += decision.pauseAfter > Duration.zero ? 2 : 1;
  }

  final session = PlaybackSession(tokens: tokens, profile: profile);
  final finished = Completer<void>();
  final sub = session.updates.listen((u) {
    if (u.state == PlaybackState.finished && !finished.isCompleted) {
      finished.complete();
    }
  });

  final watch = Stopwatch()..start();
  session.play();
  await finished.future;
  watch.stop();
  await sub.cancel();
  session.dispose();

  final drift = watch.elapsed - scheduled;
  final percent = drift.inMicroseconds / scheduled.inMicroseconds * 100;
  final perToken = drift.inMicroseconds / 1000 / count;
  final perTimer = drift.inMicroseconds / 1000 / timers;

  stdout.writeln('platform:   ${Platform.operatingSystem}');
  stdout.writeln('wpm:        $wpm');
  stdout.writeln('tokens:     $count ($timers timers)');
  stdout.writeln('scheduled:  ${scheduled.inMilliseconds} ms');
  stdout.writeln('elapsed:    ${watch.elapsedMilliseconds} ms');
  stdout.writeln('drift:      ${drift.inMilliseconds} ms');
  stdout.writeln('drift %:    ${percent.toStringAsFixed(3)} %');
  stdout.writeln('ms / word:  ${perToken.toStringAsFixed(3)}');
  stdout.writeln('ms / timer: ${perTimer.toStringAsFixed(3)}');
}

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}
