# rsvp_engine

Tokenization and pacing for hereader's RSVP reading mode.

Pure Dart, no Flutter dependency. The whole suite runs under `dart test` in
about a second with no widget harness.

## Scope

This package answers two questions and nothing else:

1. Given a block of text, what are the tokens and where does each one start?
2. Given a token, how long does it stay on screen?

Rendering, persistence, EPUB parsing and playback state live elsewhere. The
pacing layer knows nothing about presentation, so a fixed-anchor single word
and a shifting context window consume the same decisions.

## Usage

```dart
import 'package:rsvp_engine/rsvp_engine.dart';

final tokens = Tokenizer().tokenize(text);

const config = PacingConfig(
  kind: PacingModelKind.lengthScaled,
  baseWpm: 250,
);
final model = PacingModel.of(config.kind);

for (final token in tokens) {
  switch (model.decide(token, config)) {
    case Hold(:final display, :final pauseAfter):
      // show token.text for `display`, then blank the anchor for `pauseAfter`
    case AwaitAdvance():
      // show token.text until the reader presses advance
  }
}
```

## Tokenizer

Punctuation stays attached to its token, so `"Hello,"` is one token. This keeps
`1,234.56`, `don't` and `e.g.` working without special cases, and it means a
token's pause classification comes from its own trailing characters.

Each token carries a `charOffset` into the source block. Positions are stored
as `{bookId, blockId, charOffset, parserVersion}` rather than a word index,
because a tokenizer change would otherwise shift every saved position silently.
See [ADR 0002](../../docs/adr/0002-locator-format.md).

Line-break hyphenation (`co-\noperate`) is rejoined during the walk rather than
by preprocessing the string, which keeps offsets pointing at the original text.

`PauseAfter` classifies what follows a token: `none`, `clause`, `sentence` or
`paragraph`. The tokenizer classifies. The pacing model decides what each class
costs in milliseconds.

## Pacing models

| Kind | Behaviour | Intended for |
|---|---|---|
| `constant` | Every token holds for `60000 / baseWpm` ms | Default. Normally-sighted readers were fastest at a constant rate (Aquilante et al. 2001) |
| `lengthScaled` | Duration scales with letter count, normalized against `referenceLetterCount` | Central-field-loss readers gained 33% from length scaling (Aquilante et al. 2001) |
| `elicited` | No timer. Returns `AwaitAdvance` and waits for the reader | Slow low-vision readers beat fixed-rate RSVP by 47% with reader-driven advance (Arditi 1999) |

`decide` returns a sealed `PacingDecision` rather than a `Duration`, because
reader-driven advance has no duration to return. See
[ADR 0003](../../docs/adr/0003-pacing-decision-model.md).

Setting `lengthScaleStrength` to 0 makes `lengthScaled` behave identically to
`constant`, so the two are ends of one continuous knob rather than separate
modes.

## Evidence

Every claim above traces to a source verified against its PMID or DOI in
[`docs/research/rsvp-evidence.md`](../../docs/research/rsvp-evidence.md). The
same file records what the literature does not support: RSVP is not a
speed-reading technique for normally-sighted readers, and no study measures
comprehension rather than reading rate.

hereader is an accessibility tool. It does not treat, manage or improve any
medical condition.

## Testing

```bash
dart test
```

Unit tests cover each pacing model in isolation with hand-built tokens.
`test/pacing_paragraph_test.dart` runs real prose through the tokenizer and
asserts the resulting effective rate, which catches punctuation pauses eating
reading time in a way that single-token tests cannot.

## Status

Built: `Token`, `Tokenizer`, three pacing models.

Not yet built: presentation profiles, playback state machine with
rewind-on-pause.
