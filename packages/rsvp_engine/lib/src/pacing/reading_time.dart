import 'pacing_config.dart';
import 'pacing_model.dart';

/// How long the tokens still ahead of the reader will take.
///
/// An estimate, and short by a few percent by construction. A real run adds
/// a clause, sentence or paragraph pause after some tokens, and which
/// tokens those are is a property of the parsed book. ADR 0004 stores the
/// EPUB rather than the parse, so a screen outside the reader has the count
/// and not the tokens, and asking for the tokens means parsing the book on
/// the main thread of the target where `compute()` does not offload.
///
/// Null under elicited pacing, and deliberately, for the reason ADR 0003
/// gives for `AwaitAdvance` carrying no duration: nothing moves until the
/// reader presses, so a figure in minutes would describe the reader rather
/// than the book. Filling it from an average reading rate is the guess ADR
/// 0010 refuses for chapter lists, in another place.
///
/// [referenceDisplay] supplies the per-token hold, so length-scaled pacing
/// is estimated at its reference length: shorter words come in under it and
/// longer words over, and a book of ordinary prose averages near it.
Duration? remainingReadingTime({
  required int remainingTokens,
  required PacingConfig config,
}) {
  if (remainingTokens <= 0) return Duration.zero;

  final display = referenceDisplay(config);
  if (display == null) return null;

  return display * remainingTokens;
}
