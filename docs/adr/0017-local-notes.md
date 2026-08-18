# 0017 — Local notes

Status: Accepted
Date: 2026-08-18

## Context

Paste already let a reader try the engine against arbitrary text, but nothing
about it survived closing the app: no id, no stored position, no place in the
library. The gap was a genuine one — a reader who wants to keep something
short to read again, rather than try it once, had no way to.

The design was sketched before this work started and is recorded in earlier
project notes: a note as a row in `books`, its text as UTF-8 in the same
`bytes` column an EPUB's zip goes in, with a `sourceFormat` column deciding
how `bytes` gets parsed. What follows is what actually got built from that
sketch, including several things the sketch did not anticipate — editing,
a library filter, and where the app's add-something-to-read entry points
needed to converge rather than diverge further.

A table of its own for notes was ruled out before this ADR, on the same
cascade ADR 0007 already worked around: `reading_positions` has a foreign key
to `books`, and a second parent table forces either a second positions table
— duplicating outbox coalescing, the divergence rule, and the pending-position
drain — or no foreign key for any of them to rest on. One `books` table with a
format column was the only shape that did not multiply that machinery.

## Decision

**Storage.** `Books.sourceFormat` is a text column, `'epub'` or `'note'`,
defaulted to `'epub'` and backfilled at schema version 8 — every row on disk
before the column existed was an EPUB, and the default keeps it opening
through the same path it always has. `Books.updatedAt` is a separate,
nullable `DateTime` column added at schema 9, with no backfill and no
default: null means never edited, which is what every row predating the
column genuinely is, and conflating that with `importedAt` would claim an
edit that never happened.

**Parsing.** A note's raw text is not run through a bespoke tokenizer path.
It is split on blank lines into paragraphs, HTML-escaped, wrapped in `<p>`
tags, and handed to the same `HtmlNormalizer` a spine document goes through,
under a fixed `'note'` href. This gives a note real, stable block ids via
`Block.makeId('note', index)` and the same locator-stability guarantee ADR
0002 gives an EPUB — a saved position keeps resolving across reopens of the
same text — which pasted text's single, unversioned block never had and
never needed, since nothing about a pasted read is ever saved.

`BookSourceFormat` (`epub`/`note`) lives in `app/lib/reading/library_book.dart`,
not in `epub_reader`: it is an app-layer concept describing how a stored row
is opened, not something the pure parsing package has any reason to know.
`.fromName` falls back to `epub` for anything it does not recognise, the same
argument the schema migration's own default makes.

`BookImporter` gains `openNote` and `reopenStored`. Unlike an EPUB, a note's
id and title cannot be recovered from its own bytes — there is no OPF —
so both travel in from the caller: `openNote` takes them as parameters, and
`reopenStored` dispatches to `openNote` or to the existing `import` by the
stored `sourceFormat`, so `BookOpener` and the sync-conflict preview do not
need to know the difference.

**The editor.** `NoteEditorScreen` writes a new note or edits an existing
one, the same widget either way. Saving a new note calls `addBook` and opens
straight into the reader through the ordinary `BookOpener` path — the same
route every other book takes, which is what checks for a sync conflict,
re-reads whatever position sync may just have written, and wires up the save
callback ADR 0011 depends on, rather than a shorter route built only for
notes and duplicating all of it.

Editing calls a new `LibraryRepository.editNote`, a plain `update` rather
than `addBook`'s `insertOnConflictUpdate` — the upsert path rewrites
`importedAt` to now on every call, correct for re-importing an edition and
wrong for an edit, which changes when the text was last written, not when
the note first arrived. Whether the edit resets the reader's saved position
is the editor screen's decision, passed in as `resetProgress`, not something
`editNote` infers: the screen holds both the original bytes and the ones
about to be saved, and is the only place positioned to tell a title-only
change from one that actually moved the words underneath a saved place. When
`resetProgress` is true, `editNote` drops the stored position and coalesces
any unsent position event for the same book in the same transaction, so a
locator this reopen no longer produces cannot go out on the next sync drain.
The reader is asked to confirm only when the text changed *and* a position
existed to lose — editing a note nobody has started yet, or fixing a typo
and changing nothing else, never interrupts with a question about progress
that either does not exist or was never at risk.

**The library filter.** A format control — All, Books, Notes — sits beside
sort, filtering client-side over the same list `watchLibrary` already
streams for sorting rather than a second, format-scoped query: telling "the
whole library is empty" apart from "nothing matches this filter" needs the
unfiltered list either way, so a `where` clause would save nothing. The
choice persists like sort does. A filter with zero matches gets its own
empty state, distinct from the library's own: it stays on Books or Notes
rather than reporting the library as empty, offers a button straight to the
one action that filter is missing (an EPUB picker under Books, the note
editor under Notes) rather than the three-way menu asking the reader to
repeat a choice the filter already made, and leaves the controls row on
screen so All is always one tap back. The library's own fully-empty state is
untouched and takes priority: the filter row never renders before there is
at least one book or note to filter among, so a filter can never point at
nothing with no way out.

Saving into a filter the result would not appear under — an EPUB imported
while filtered to Notes, or a note written while filtered to Books — resets
the filter to All, so the reader sees what they just added rather than a
shelf that looks unchanged. This only fires on a genuine save that would
otherwise be invisible: an addition that already matches the current filter,
or a cancelled add, leaves the filter exactly where the reader left it.

**One add menu, not two.** `AddChoice` and the `AddMenu` dialog moved out of
`library_screen.dart` into their own file, `add_menu.dart`. Home's empty
state used to carry two buttons of its own — EPUB and paste, with no way to
reach the note editor at all — which was never a deliberate decision to
leave notes out of Home; it was a second, shorter copy of a choice the
library already owned, and the two drifted the moment a third option was
added to one of them and not the other. Home now opens the identical dialog
the library's add button does. The floating add button on the library hides
once the library is genuinely empty, where `_EmptyLibrary`'s own button
already covers the same action and a second control offering it reads as
that one being broken rather than redundant; it stays visible whenever the
library has content, even if the current filter's shelf is empty, since the
reader may well want it there.

## Alternatives considered

**A table of its own for notes.** Rejected before this ADR, on the ADR
0007 cascade described under Context.

**Deriving a note's id and title from its bytes**, the way an EPUB's come
from its OPF. Rejected: there is nothing in plain UTF-8 text playing that
role, and inventing a header format inside the note's own bytes to hold them
would mean parsing back out exactly what the caller already has in hand.

**Resetting a note's progress unconditionally on every save from the
editor.** Rejected. Opening a note to fix a typo and deciding against it,
then tapping Save, would silently wipe a reading position that the text
never actually threatened. Comparing the saved bytes against the ones being
written was cheap enough that there was no reason to skip it.

**A confirmation dialog on every progress-resetting edit**, whether or not
there was anything to lose. Rejected: a note nobody has started reading has
no progress a dialog is protecting, and asking anyway would be the kind of
interruption this project's own "warn, don't block" pattern exists to avoid
manufacturing.

**Auto-opening the add menu the instant Home or the library mounts with
nothing in the library**, rather than requiring one tap on a visible button
first. Rejected: a dialog stealing focus before a low-vision or
screen-reader user has gotten their bearings on a freshly loaded screen is a
worse experience than a static screen with one clearly labelled button, and
it would refire every time the reader navigated to an empty tab — after
removing their last book, say — which reads as nagging rather than as help.
The screen is never blank either way: both empty states already carry a
heading, an explanation, and the one button before it is ever pressed.

**Hiding the floating add button whenever the current filter's shelf is
empty**, not only when the library itself is. Rejected: a reader who has
filtered to Notes and has none yet may still want to add one from the
floating button as much as from the empty state's own — the button's
redundancy argument only holds against `_EmptyLibrary`, which is the
library's own empty state, not the filtered one.

**Resetting the filter to All on every save, regardless of whether the
addition would already be visible.** Rejected: it would reset a filter the
reader deliberately chose even when nothing about their view was actually
about to change, which is a worse surprise than the invisible-add problem
this exists to fix.

## Consequences

A note's content never crosses the sync wire, the same as an EPUB's never
has: `addBook` and `editNote` do not enqueue an outbox event, because book
content has never been a synced entity under ADR 0005. A note written on one
device is a device-local object exactly the way an imported EPUB already is.
Positions for a note do sync and wait in `pending_positions` on a device
that lacks the note itself, which is the same shape a one-device book
already produces.

Every stored book row now carries an extra column the reader never sees
directly, and two migrations (`sourceFormat` at schema 8, `updatedAt` at
9) that every existing install runs once. Neither backfills a value beyond
what is already true of every row on disk.

`semanticsForBook` was not extended to announce a note's Added/Edited date,
so the fact reaches a low-vision reader looking at the tile and nobody
using a screen reader. Recorded in `app/README.md` under known limitations.

The full save-and-open path — writing a note, saving it, landing back on a
library that may have just reset its filter — has no automated test
covering it end to end. It routes through a real `compute()` isolate, and
`tester.runAsync`, confirmed working for `compute()` on a minimal probe, did
not resolve reliably across this route's full depth within the time given
to it. The condition it would have tested was verified by reading the code
instead. See Verification.

## Verification

`flutter analyze` and `dart analyze` clean. `flutter test` and `dart test`
green — 894 tests in the app suite, including new coverage for: note
parsing (paragraph splitting, markup escaping, block-id stability across
reopens, the empty-note rejection), the schema 8 and 9 migrations against a
database built on the previous version, `editNote`'s position-reset
behaviour, the corrected progress formula, the format filter and its
distinct empty state, the floating button's visibility, and the finished-
state save fix below.

Two bugs surfaced during this work and were fixed inside it rather than
after. `BookSummary.progress` computed `tokenIndex / wordCount` while the
reader screen's own bar computed `TokenizedText.progressAt`, which is
`(tokenIndex + 1) / wordCount`; the mismatch meant a finished book or note
read as 99% everywhere outside the reader screen itself, for every book in
the library, since ADR 0013. Reported as a note that had been read
completely still showing as unread, which turned out to be a second, worse
bug: `ReaderScreen` seeds its "already saved" index to the resume position
at open so a glance-and-close writes nothing, and for a text of exactly one
token the index never moves away from that seed even after reaching
`finished`, so the save was silently skipped every time regardless of
format. Fixed by forcing the save through specifically on the transition
into `finished`, leaving the glance-and-close guard for an ordinary pause
untouched. Both fixes, and the tests that pin them, are described further
in project notes rather than repeated here.

Checked by hand on Windows: writing a note and reading it to the end;
reopening a stored note and confirming its saved position resolves; editing
a note's title only and confirming progress survives; editing a note's text
with a saved position and confirming the reset is asked for and honoured;
switching the library filter between All, Books and Notes with a mixed
library; the filtered-empty states for both Books and Notes, including
their buttons; the floating button disappearing on a fully empty library
and reappearing the moment anything is added; Home's empty state opening
the same three-way menu the library's does. Not yet checked on Android
Chrome — see `app/README.md`'s known limitations, which already carry this
gap for every UI change since the web performance investigation.
