# rsvp_engine

The reading core of hereader: tokenizing, pacing, profiles, and the playback
state machine.

Pure Dart, no Flutter dependency. The whole suite runs under `dart test` in
about a second with no widget harness, and again under `dart test -p chrome`,
which is what makes this the right home for anything whose arithmetic depends
on the compilation target. See
[ADR 0009](../../docs/adr/0009-web-platform-coverage.md).

## Scope

This package answers four questions about reading:

1. Given a block of text, what are the tokens and where does each one start?
2. Given a token, how long does it stay on screen?
3. What does the reading surface look like while it does?
4. Which token is current, and where in the book is that?

Rendering, persistence and EPUB parsing live elsewhere. The pacing layer knows
nothing about presentation, so a fixed-anchor single word and a shifting
context window would consume the same decisions.

Three smaller things live here for a reason rather than by topic: hybrid
logical clock stamps, WCAG contrast maths, and the remaining-time estimate.
Each is described below, and each is here because it is either plain data the
profile carries or arithmetic that has to be exact in a browser.

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

`PlaybackSession.current` exists so a renderer can seed itself. The stream
carries *changes*, and an untouched session has not changed, so a book opened
at a stored position drew a blank surface until the reader tapped.

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
reader-driven advance has no duration to return. `Hold` carries `display` and
`pauseAfter` separately, so a renderer can blank the anchor through a
punctuation gap rather than holding the word longer. See
[ADR 0003](../../docs/adr/0003-pacing-decision-model.md).

Setting `lengthScaleStrength` to 0 makes `lengthScaled` behave identically to
`constant`, so the two are ends of one continuous knob rather than separate
modes. Length scaling normalises against `referenceLetterCount` (default 5.0)
so a configured words-per-minute means roughly the same thing across
languages.

`remainingReadingTime` multiplies the tokens still ahead by `referenceDisplay`,
the same function the fade warning measures against, so the two cannot
disagree about how long a word is shown. It returns null under elicited
pacing, for the reason `AwaitAdvance` carries no duration: nothing moves until
the reader presses, and a figure in minutes would describe the reader rather
than the book. It is short by a few percent by construction, since punctuation
pauses are a property of a parse the caller does not have. See
[ADR 0014](../../docs/adr/0014-reading-time-estimate.md).

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

Deserialisation clamps rather than throws. The constructors assert on ranges,
which is right for catching a bug in app code and wrong at the wire boundary:
a throw there is counted as a skipped event and the sequence number moves past
it, so the change is never retried. Values outside range move to the nearest
bound instead.

Two fields on `PresentationConfig` are nullable, and null means something on
each. `tintArgb` null says the background follows the polarity. `polarity` null
says the profile states no preference at all and whoever draws it decides:
this package holds no notion of a platform theme and cannot look one up, so
`resolvedWith(Polarity fallback)` takes the answer from the caller and leaves a
profile that states one alone. The app passes the brightness it is running in.
See [ADR 0016](../../docs/adr/0016-reader-theme-follows-the-app.md).

Neither nullable field appears in `copyWith`, which reads a null argument as an
instruction to keep the current value and so could never put either back to
unset. `withPolarity` and `withTint` each set one field, null included.

On the wire an unset field is an absent key rather than a null one, and
`fromJson` reads a missing `polarity` and a name from some later build the same
way: as a value this build should not guess at.

`Presets.all` holds the built-in profiles. They live in code rather than
storage, so improving one takes effect without a migration; a reader who edits
one is really forking it into a stored profile of their own. `Standard` and
`Spaced type` state no polarity, since nothing in the evidence behind either
picks a surface. The three whose reasoning does pick one write it out.

Whether a profile is built in is derived from the `builtInIdPrefix` namespace
rather than stored, so nothing arriving over the wire can claim to be a preset.
`ReadingProfile.newId` mints an id for a fork: a millisecond plus 32 random
bits, never inside that namespace. It lives here rather than in the app both
because the rule it satisfies does, and because its entropy is drawn as two
16-bit values multiplied together — `nextInt(1 << 32)` is `nextInt(0)` under
`dart2js`, which throws, and this is the package whose suite runs in a browser.

## Playback

`PlaybackSession` drives a token list according to a profile. States are
`idle`, `playing`, `paused`, `awaitingAdvance` and `finished`.

`awaitingAdvance` is deliberately not `paused`. Under reader-elicited pacing
the reader is actively reading, just not on a timer. Collapsing the two would
make the pause button meaningless in that mode and would fire the profile's
rewind on every single word.

Resuming from `paused` steps back by `rewindWords`; an explicit `rewind()` does
not, so holding a back button does not compound one on top of the other.

Timing chains `Timer` directly rather than driving from a `Ticker`, so
`fake_async` can step a whole paragraph in microseconds. The side effect is
that word onset does not quantise to frame delivery, which matters on the web,
where the browser decides how many frames a page gets. The cost is that each
timer is scheduled when the previous one fires rather than against an absolute
schedule, so lateness compounds across a book — probably under a percent, and
unmeasurable under a virtual clock that fires every timer exactly on time.

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

`progressAt` answers how far through the text an index is: `(index + 1) /
length`, the count of words already seen rather than the index of the one on
screen. The app's library tile cannot call it — it has a stored token index
and a word count, not a parsed text — so it repeats the formula, and the two
disagreed by one word long enough for every finished book to read as 99%. The
`+ 1` is stated in both places for that reason, and the app's copy names this
one.

## Clock stamps

`HybridLogicalClock` issues `HlcStamp`s for the sync event log, formatted
`{millis:013d}-{counter:05d}-{deviceId}`, fixed-width so lexicographic
comparison gives the same answer as comparing the parts. `observe` takes a
remote stamp forward, `issue` never moves backwards even if the system clock
does, and `restoreFrom` resumes after a restart.

It lives in this package because the format has to match the Java service's
byte for byte and because it is arithmetic on integers and strings with no
Flutter type in it — the same argument that keeps `newId` here.

## Contrast

`contrastRatio`, `relativeLuminance` and `rateContrast` implement WCAG's
maths over ARGB integers, alongside `redOf`/`greenOf`/`blueOf`/`argbFrom` for
taking those integers apart. `ContrastRating` is `high`, `adequate`, `low` or
`veryLow`.

They are here rather than in the app for the reason profiles hold colours as
integers: they touch no Flutter type, and the app is the one target the browser
test run cannot reach. The app maps them to `Color` at its boundary, in the
same file that holds the polarity constants, so a colour the app paints and a
colour it judges cannot drift apart.

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
dart test -p chrome
```

Both runs are required in CI. The browser run is not redundant: a 64-bit hash
constant fails to *compile* there while a 32-bit shift fails at *runtime*, and
only one of those is caught by a build.

Unit tests cover each pacing model in isolation with hand-built tokens.

`test/pacing_paragraph_test.dart` runs real prose through the tokenizer and
asserts the resulting effective rate, which catches punctuation pauses eating
reading time in a way that single-token tests cannot.

Playback is tested against a virtual clock through `fake_async`, so a
five-minute reading session at 250 wpm runs in microseconds and the suite
still finishes in about a second.

`test/profile_id_test.dart` asserts 200 distinct 8-hex-digit suffixes, which
is the regression test for the `nextInt(1 << 32)` bug rather than a test of
uniqueness in general.

A few tests pin research-driven decisions rather than code: the central field
loss preset asserts reader-elicited pacing because Arditi 1999 says so, and
`test/presentation_polarity_test.dart` asserts that the same preset keeps its
reversed surface rather than following a caller. If someone changes either, the
failure should prompt them to check the evidence rather than the
implementation.

`test/presentation_polarity_test.dart` also covers the wire format directly,
including a payload written before `polarity` became nullable. Every profile
stored by an earlier build carries the key, so this is what says those profiles
keep the surface their reader already reads on.

## Status

Built: `Token`, `Tokenizer`, three pacing models, `ReadingProfile` and
presets, `PlaybackSession`, `TokenizedText` and `Locator`, `HybridLogicalClock`,
the contrast maths, and the remaining-time estimate.

Not yet built: chunk sizes above one token, which need pacing to decide over a
group rather than a single token, and presentation modes beyond a fixed
anchor.
