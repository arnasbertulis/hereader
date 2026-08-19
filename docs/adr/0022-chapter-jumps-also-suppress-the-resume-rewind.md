# 22. Chapter jumps also suppress the resume rewind

Date: 2026-08-19

## Status

Accepted. Closes the gap ADR 0020's Consequences recorded as open.

## Context

ADR 0020 gave every reader-driven move — the tap zones, and later the four
jump buttons in ADR 0021 — `PlaybackSession.stopAt`, which lands on the target
and suppresses exactly one resume rewind. Without that suppression, resuming
from `paused` applies `ReadingProfile.rewindWords`, and a step forward
followed by pressing play would leave the reader behind where they started.

`_goToChapter` and `_goToFrontMatter` never went through `stopAt`. Both used
`PlaybackSession.seekToIndex`, which carries no such suppression, so a reader
who opened the chapter panel, picked a chapter, and pressed play stepped back
by `rewindWords` on the way out and landed in the chapter they had just left —
`awaitingAdvance`, elicited pacing's active-reading state, is not a stop, and
`seekToIndex` also collapsed it to `paused` regardless, which is the second
half of the same gap: a reader under elicited pacing lost the advance mode
they were using on any chapter jump, not only the rewind.

ADR 0020 recorded the fault and left it, reasoning that `seekToIndex` kept
playing when the session was already playing, which is what chapter
navigation wants, and that moving onto `stopAt` would change two behaviours at
once. `_openChapters` always pauses before the panel opens, though, so
`_goToChapter` never runs against a playing session — the "keeps playing"
case `seekToIndex` was chosen for cannot happen at that call site. The two
behaviours turn out to be one.

## Decision

`_goToChapter` and `_goToFrontMatter` call `stopAt` instead of `seekToIndex`.

`stopAt` reschedules rather than pausing when the session is already
`awaitingAdvance`, and pauses everywhere else, setting the one-resume
suppression either way. `_goToChapter` only ever runs paused, since
`_openChapters` pauses first — same outcome as before, now with the
suppression set. `_goToFrontMatter` runs from whatever state the front-matter
offer was shown in, which `stopAt` now handles correctly instead of forcing to
`paused`.

`PlaybackSession.seekToIndex` itself is unchanged: `profile_edit_screen.dart`
still uses it to loop a finished preview back to the start, immediately
followed by `play()`, where no resume and no suppression are in play.

## Consequences

**None beyond the fix.** Both call sites already routed through the same
`_session` the other jump controls use, so no new state, no new widget, and no
layout change.

## Alternatives rejected

**Leave it recorded as an open gap.** ADR 0020's own reasoning for not fixing
it — that `seekToIndex` keeps playing when already playing — does not hold at
either call site: `_goToChapter` runs only after `_openChapters` has paused,
and `_goToFrontMatter`'s one caller is the front-matter offer, never mid-flight
playback. Rejected because the reasoning that justified leaving it open was
wrong, not because the fix grew harder.

## Verification

`flutter test` in `app/`: full suite green, including two new regression tests
in `chapter_navigation_test.dart`, each checked against the pre-fix
`seekToIndex` call to confirm it actually fails there before confirming it
passes against `stopAt`:

- "resuming after a chapter jump does not rewind by `rewindWords`" — the
  rewind symptom, against a standard profile.
- "the front matter offer" group's "accepting it under elicited pacing keeps
  advancing rather than pausing" — the `awaitingAdvance`-collapse symptom.
  Front matter's target is always index 0, where `rewindWords` clamps to
  nothing, so the rewind symptom itself does not show there; this is the
  distinct failure that call site actually produces.

`flutter analyze` clean.

**Not run: a manual pass.** The two new tests exercise the same landing and
resume path a manual check would, so none was done separately for this fix.
