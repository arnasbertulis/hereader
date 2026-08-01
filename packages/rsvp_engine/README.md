# rsvp_engine

The reading core of hereader: tokenizing, pacing, profiles, and the playback
state machine.

Pure Dart, no Flutter dependency. The whole suite runs under `dart test` in
about a second with no widget harness.

## Scope

This package answers four questions and nothing else:

1. Given a block of text, what are the tokens and where does each one start?
2. Given a token, how long does it stay on screen?
3. What does the reading surface look like while it does?
4. Which token is current, and where in the book is that?

Rendering, persistence and EPUB parsing live elsewhere. The pacing layer knows
nothing about presentation, so a fixed-anchor single word and a shifting
context window would consume the same decisions.

## Usage

```dart
import 'package:rsvp_engine/rsvp_engine.dart';

// Blocks come from anywhere with an id and some text; this package does not
// know what an EPUB is.
final text = TokenizedText.from(
  blocks.map((b) => (id: b.id, text: b.text)),
  parserVersion: kParserVersion,
);

final session = PlaybackSession(
  tokens: text.tokens,
  profile: Presets.centralFieldLoss,
  startIndex: text.indexOf(savedLocator) ?? 0,
);

session.updates.listen((update) {
  // update.token is null during a punctuation gap: blank the anchor rather
  // than holding the word longer.
});

session.play();

// Save this, not the token index.
final locator = text.locatorAt(session.index);
```

## Tokenizer

Punctuation stays attached to its token, so `"Hello,"` is one token. This keeps
`1,234.56`, `don't` and `e.g.` working without special cases, and it means a
token's pause classification comes from its own trailing characters.

Numeric units are folded into the number before them, so `2005 m.` is one
token rather than a number followed by a bare `m.` that means nothing on
screen. Both the abbreviation set and the suffix set are constructor
parameters, because they are language-specific.

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

## Profiles

A `ReadingProfile` bundles a `PacingConfig` with a `PresentationConfig`:
anchor position, type size, letter spacing, contrast polarity, transition
duration, and how many words to step back when resuming.

`PresentationMode` is a separate axis from `PacingModelKind`. Pacing decides
*when* to advance; presentation decides *what is visible*. Only fixed-position
single-token rendering is implemented.

Profiles are plain data and round-trip through JSON, including colours, which
are stored as ARGB integers so this package stays free of Flutter. That is
what lets them be persisted and synced without the app being involved.

`Presets.all` holds the built-in profiles. They live in code rather than
storage, so improving one takes effect without a migration; a reader who edits
one is really forking it into a stored profile of their own.

## Playback

`PlaybackSession` drives a token list according to a profile. States are
`idle`, `playing`, `paused`, `awaitingAdvance` and `finished`.

`awaitingAdvance` is deliberately not `paused`. Under reader-elicited pacing
the reader is actively reading, just not on a timer. Collapsing the two would
make the pause button meaningless in that mode and would fire the profile's
rewind on every single word.

Resuming from `paused` steps back by `rewindWords`; an explicit `rewind()` does
not, so holding a back button does not compound one on top of the other.

## Locators

`TokenizedText` holds a flat token stream alongside the mapping back to
`(blockId, charOffset)`. Playback wants a list; persistence and sync want a
position that survives re-parsing.

Positions are stored as `{blockId, charOffset, parserVersion}` rather than a
word index, because a tokenizer change would otherwise shift every saved
position silently. See
[ADR 0002](../../docs/adr/0002-locator-format.md).

`indexOf` does not refuse a `parserVersion` mismatch. Landing a sentence away
from where the reader stopped beats refusing to resume; a caller that needs a
migration should compare versions itself.

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

Playback is tested against a virtual clock through `fake_async`, so a
five-minute reading session at 250 wpm runs in microseconds and the suite
still finishes in about a second.

A few tests in `presets` pin research-driven decisions rather than code: the
central field loss preset asserts reader-elicited pacing because Arditi 1999
says so. If someone changes it, the failure should prompt them to check the
evidence rather than the implementation.

## Status

Built: `Token`, `Tokenizer`, three pacing models, `ReadingProfile` and
presets, `PlaybackSession`, `TokenizedText` and `Locator`.

Not yet built: chunk sizes above one token, which need pacing to decide over a
group rather than a single token, and presentation modes beyond a fixed
anchor.
