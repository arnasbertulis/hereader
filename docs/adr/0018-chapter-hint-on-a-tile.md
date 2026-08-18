# 0018. The chapter on a tile is a device-local hint written with the position

Date: 2026-08-18

## Status

Accepted.

## Context

Home's continue tile says where the reader is and roughly how long is left,
and both answers are about the whole book (ADR 0014). The question a reader
picking a book up actually asks first is narrower — whether this chapter fits
in the time they have — and nothing in the app could answer it.

The obstacle is structural. ADR 0010 resolves chapters at parse time and says
outright that a chapter is never stored. ADR 0004 does not parse a book until
it is opened. So the reader screen is the only thing in the app that has ever
known what chapter a position is in, and it knows it for the length of one
sitting.

Working it out on the library screen instead means parsing a book to draw a
tile. ADR 0013 already rejected that shape for the token count, on the web
target specifically: `compute()` runs synchronously on the main thread there,
so a library of twelve books parses twelve books on the frame thread.

## Decision

### Two columns on `ReadingPositions`, written by the reader and nobody else

`chapterTitle` and `chapterEndIndex`, added in schema version 10. Nullable,
no default, no backfill — a chapter comes out of a parse, so there is nothing
to backfill *from* without doing the parse this document exists to avoid.

`ReadingResult` carries both out of the reader screen alongside the token
index it already carried, and `savePosition` writes all three in one
statement. They describe the same moment and are never half-written.

### An end index, not a start and not a chapter id

The screens reading this hold no table of contents to index into — that is
the whole reason the value is stored. They are asking how much of the chapter
is ahead, and they already have the index the reader is at, so the end is the
only other number needed. Exclusive, so a chapter's span is `end - start` and
the tokens ahead are `end - (index + 1)`, matching how `BookSummary.progress`
counts words already seen.

### Every write path that is not the reader clears it

This is the substantive part, and it is ADR 0013's "written even when null"
argument applied to a second pair of columns — for a reason that is sharper
here.

`savePosition` and `applyRemotePosition` both use `insertOnConflictUpdate`,
which leaves columns the companion omits **untouched** on the update branch.
A remote position carries no chapter, because nothing chapter-shaped is on
the wire. So a companion built without these columns would let a title from
where the reader used to be survive beside a locator for where they are now —
and it would survive on the one device that had recorded a chapter, which is
the device most likely to be trusted.

`applyRemotePosition` and `_drainPendingPosition` therefore pass
`Value(null)` explicitly. `SyncEngine.resolveConflict` routes through
`applyRemotePosition` and clears them with everything else, which needs no
special case: after settling a divergence the tile falls back to the book
figure until the next save, at most fifteen seconds of reading away
(ADR 0011).

`PendingPositions` gains no columns at all. A held position came off the wire
and never had a chapter, and the book it names is not on this device yet.

### Nothing goes on the wire

The outbox payload is unchanged and the server schema is untouched. A chapter
is a fact about *this device's parse of this copy of the book*; the service
holds no copy, and another device holding a different edition would be handed
a title that does not describe where it would land.

### This does not reverse ADR 0010

That document rejects storing the table of contents: derived data, invalidated
by every parser change, recomputed anyway on every open. All of that still
holds and nothing here stores a table of contents. One resolved entry is
stored, as a display hint, under exactly the rules ADR 0013 set for the token
index sitting in the next column — including that a `kParserVersion` bump
leaves it stale until the next save, and that nothing may navigate by it.

### The scope is a preference, and the chapter shows either way

`ui.time_left_scope`, device-local like every other `ui.` key, holding
`chapter` or `book`. `Preferences` is one row per key by design, so this cost
no migration.

Two figures, both honest, answering different questions: whether this chapter
fits in the time available, and how large the remaining commitment is. Neither
is the obvious default.

The chapter name is drawn whichever scope is set. It is the label on the
figure as much as a fact of its own — with it beside them, `4 min left` and
`1 h 12 min left` cannot be confused for one another, and the cases where the
app has no chapter are exactly the cases where the figure silently falls back
to the book. A reader can always tell which they are looking at.

### It lives in Settings › Reading, which now writes a preference

That screen's own comment said "Nothing on this page writes a preference", and
gave the reason: a switch that turns off position saving would be a setting
whose wrong value costs the reader their place. The reason is narrower than
the sentence. Which of two honest figures a tile shows is not that kind of
setting, so the comment was rewritten to rule out what it actually rules out.

## Consequences

The library screen now watches the active profile, which it did not before —
the second screen to do so, for the reason ADR 0014 gives for the first: the
pointer is a preference and the profile it names is a row, so a figure derived
from it goes stale on two separate writes.

`_textBlockHeight` moved from 96 to 114. A grid tile is measured rather than
laid out to fit, so a line added below the bar without a number added there is
a line the grid clips.

Four cases show a book figure under the chapter scope, and each is legible
because no chapter is drawn beside it: a note, a book declaring no table of
contents, a reader still in front matter, and a position that has just arrived
from another device. The last of these will look like the chapter
disappearing, and it is: this device has not read that book since the place in
it moved.

`semanticsForBook` takes the pacing now, so the chapter and the figure are
announced as well as drawn. It was the only way to add them without making the
screen-reader label a smaller version of the tile.

The migration test's `_revertTo` needed a case for version 10. ADR 0013's
consequences section predicted this for every future additive step, and the
suite failed in exactly the way it described before the case was added.

## Alternatives considered

**Parsing the book on the library screen.** Rejected on the web target, the
same ground ADR 0013 rejected counting tokens there. A tile is not worth a
parse on the frame thread, and the real version of this idea is a web worker,
which is listed as its own piece of work.

**Syncing the chapter with the position.** Rejected. It describes this
device's parse of this copy. Another device on a different edition would draw
a chapter title that does not name where its own locator resolves, and the
reader would have no way to tell that from a correct one — the same failure
mode ADR 0010 refuses when it declines to build a chapter list out of heading
blocks.

**Storing a chapter index into the table of contents.** Rejected: the screens
reading it hold no table of contents, so an index is a pointer into something
they do not have.

**Storing the chapter's start rather than its end.** Rejected. The question
being asked is how much is ahead, and the index the reader is at is already in
the next column, so a start would have to be paired with a *second* lookup to
be useful.

**Always counting the chapter, with no preference.** Rejected on the request
and on the merits. The whole-book figure is the one that answers how large a
commitment is left, it is what the tile said before this change, and taking it
away to replace it with a narrower one is a loss dressed as a feature.

**A tap on the line to toggle between the two.** Rejected: the tile's tap
target is the whole tile and it opens the book, so this would need a second
target inside the primary one, on the screen whose premise is that targets are
hard to hit.

**Storing the chapter on `Books`.** Rejected on the grounds ADR 0013 used for
the token index: it is written on the position cadence, every fifteen seconds
while reading, and that row also holds the EPUB blob.

## Verification

`flutter test` in `app/`, 932 passing, with:

- `chapter_hint_test.dart` on the repository paths — a save keeps its chapter,
  a save without one clears the previous, a remote position clears it, a stale
  remote position that loses on stamp does *not* clear it, a drained pending
  position has none, and the outbox payload contains no chapter. The clearing
  cases are the ones that matter; the others would pass against a companion
  that never wrote the columns.
- `schema_migration_test.dart` building a version 9 database, upgrading it,
  and asserting that the place survives, that both columns are null rather
  than defaulted, and that a save *after* the upgrade stores them.
- `chapter_navigation_test.dart` on `chapterIndexAt` and `chapterEndAt`,
  including entries sharing a start — the case where taking the next entry
  blindly reports a chapter of zero tokens.
- `book_place_test.dart` on the arithmetic and the wording, including the
  fallback when a stored end is behind the reader.
- `reading_display_test.dart` on the preference, including an unrecognised
  stored value and the absence of an outbox event.

`dart test` and `dart test -p chrome` in both pure packages, unchanged and
passing — the check that nothing arithmetic leaked out of the app layer.

**Not yet run, and this section will be rewritten when it has been:** the
check by hand on Windows against Romeo and Juliet — reading into a scene,
closing, and watching the tile name it; flipping the setting in Settings and
watching the figure grow while the chapter stays; a note and a book still in
front matter falling back. Nothing above establishes that the line renders
where it is meant to or truncates the half it is meant to.

Also outstanding: the sync case on two real devices, which is the failure this
whole design is arranged around and which no suite here can reach; and Android
Chrome, where this adds text that has to ellipsize at phone width.
