# 0010. Chapter navigation reads the book's own table of contents

Date: 2026-08-11

## Status

Accepted.

## Context

The reader could move a word at a time, five words back, and to a stored
position. It could not move to a named place in the book. For a work read
over several sittings that is the one navigation a reader actually asks for,
and it was first on the roadmap.

Two facts about this app make it less obvious than it looks in a
conventional reader.

**There is no page to scroll.** A paged reader can hand a chapter jump to its
layout engine and let the reader land approximately. Here a jump is a single
token index, and the word that appears is the only word visible. Landing at
the wrong place is not a scroll away from being right.

**Positions are blocks and offsets, never indices into anything derived**
(ADR 0002). A chapter list is another kind of position, and it has to resolve
through the same machinery or it will disagree with the reading position the
moment normalization changes.

A third fact turned up on reading the fixture rather than reasoning about the
format. `packages/epub_reader` did not read a table of contents at all, and
the navigation document is usually not in the spine, so nothing in the parser
had ever opened it.

## Decision

### The chapter list comes from the book, and only from the book

EPUB 3 declares a navigation document through `properties="nav"` in the
manifest. EPUB 2 declares an NCX through the spine's `toc` attribute. Both
are required by their respective specifications, so a book carrying neither
is malformed rather than merely old. The newer form wins where a book has
both, which is most books published this decade; they are not merged, because
they describe the same structure and merging would double every entry.

A book that declares nothing gets no chapter list and no button. Nothing is
inferred from heading blocks to fill the gap. A heading list looks like a
table of contents and is not one: it includes running heads, section labels
and the licence page's own title, in an order the publisher never endorsed. A
navigation panel is a promise about a book's structure, and a guessed promise
is worse than an absent one.

### Entries resolve to blocks inside the package, not to hrefs outside it

`TocEntry` carries a `blockId`, not a URL and a fragment. Only this package
knows how a document was normalized, so resolving an href anywhere else would
put that knowledge in a second place and let the two drift apart.

Entries that cannot be resolved are dropped rather than carried: a document
that produced no text, one the archive is missing, or one the spine marks
`linear="no"` and `readingOrder` therefore skips. An entry surviving with an
unresolvable id renders as a chapter that silently does nothing when tapped,
which is a worse failure than a list one entry short.

Reading the table of contents never throws. A book with a broken nav document
is still a readable book.

### The normalizer records fragment anchors

This is the substantive part, and it is the reason the feature needed a walk
change rather than only a new parser step.

The fixture makes the case concretely. Romeo and Juliet's five Act I scenes
all point into `1513-h-3.htm.xhtml`, differing only by fragment. Resolving an
entry to its document and stopping there would land all five on that
document's first block: five rows in the panel, one destination. The same
holds for every book whose converter chunks by act rather than by scene,
which is the common shape.

So `HtmlNormalizer.normalize` now returns a `NormalizedDocument` carrying
`blocks` and `anchors`, produced by one walk. An id is held pending until a
block is emitted, which resolves three shapes with one rule:

- an id on the block element itself,
- an id on a container wrapping several blocks, which is where Project
  Gutenberg's converter puts chapter fragments,
- an id on an empty inline anchor inside a block.

Anchors on a block dropped for length carry forward to the next block kept,
so a fragment aimed at a spacer paragraph reaches real text rather than
nothing. First claim wins, so a container and the heading inside it agree
rather than displace one another.

An unknown fragment falls back to the start of its document rather than
dropping the entry. The book says a chapter begins in this file; its start is
close, and losing the entry is not.

### A chapter is a token index, resolved at parse time and never stored

`Chapter` carries a token index, because that is what `seekToIndex` moves in.
It is not a `Locator` and it is not persisted. Storing one would mean keeping
a copy of every book's table of contents in the database and migrating it on
every `kParserVersion` bump, to hold data that is recomputed in the same
parse that already runs on every open (ADR 0004).

The block a chapter names can produce no tokens — `TokenizedText.from` drops
blocks that tokenize to nothing — so the mapping walks forward to the first
block that did. The same guard already exists a few lines above for
`contentStartIndex`. Landing a line late is invisible to a reader; a chapter
missing from the panel is not.

### The panel is a Scaffold drawer, and the reading surface stays a tap target

`Scaffold.drawer` brings the scrim, focus handling, screen-reader semantics
and dismissal behaviour that a hand-built panel would have to reimplement,
badly, in an app whose whole premise is accessibility.

`drawerEnableOpenDragGesture` is off. The entire surface is a tap target and
an edge drag is easy to start by accident on a phone; a panel opening
mid-sentence would read as the app interrupting the reader.

Opening the panel pauses playback, as switching profile already does. Leaving
the stream running behind it would return the reader to a paragraph they
never saw, and the position saved on close would be that one. Selecting a
chapter leaves the session paused there rather than resuming: arriving mid
flight at 250 wpm in a place the reader has not looked at yet means the first
words go past before they have.

The panel is flat with indentation rather than collapsible sections. A reader
looking for Act III Scene II wants to see it, not to expand Act III first.

### Escape and back are routed through one handler

The reader route sets `canPop: false` so it can return a `ReadingResult`.
`ModalRoute.popDisposition` reports `doNotPop` before the `LocalHistoryEntry`
the drawer registers is ever consulted, so the drawer's own back handling
never runs on this route. Without intervention, backing out of the chapter
list would exit the book and save a position the reader was in the middle of
changing.

Both Escape and the system back gesture therefore go through one handler that
closes the panel if it is open and closes the book otherwise. The keyboard
shortcuts for advance and rewind are gated on the same check: the scrim eats
taps, but the bindings sit above the Scaffold and stay live regardless.

## Consequences

`HtmlNormalizer.normalize` changed its return type. It is used in two places
— the parser and its own tests — so the churn is small, but it is a breaking
change to a public API of a package that could be published (ADR 0001).

Block ids and offsets are untouched. The walk emits exactly the blocks it
emitted before, in the same order, with the same indices; anchors are
recorded alongside. `kParserVersion` therefore does not move and no stored
reading position is affected. The golden test's block and character counts
are unchanged, which is the check that this is true.

Books without a declared table of contents show no chapter button. This is
correct rather than regrettable, but it does mean the feature is invisible on
some hand-converted files, and a reader has no way to tell that from the
feature being absent.

The panel does not scroll to the current chapter when it opens. The current
chapter is highlighted, so a reader deep in a long book has to scroll to find
it. Listed as a limitation rather than solved: the fix wants either measured
tile heights or an index-based scroll controller, and neither is worth the
fragility before a deadline.

Chapter titles come from the book and are shown as written. A book whose
navigation labels are badly cased or full of publisher noise shows exactly
that.

Two entries pointing at the same block both survive as separate rows. Books
do this — a cover entry and a title-page entry frequently resolve together —
and dropping one would mean second-guessing a structure the book declared.

## Alternatives considered

**Derive chapters from heading blocks.** Rejected as the primary mechanism
and as a fallback. `BlockKind.heading` is already recorded, so it is nearly
free, and that is its whole appeal. It produces running heads and section
labels alongside chapters, cannot tell an act from a scene except by tag
level, and includes the Gutenberg licence heading. It would also silently
produce a *different* list from the one the book declares, so a reader
comparing against a paper copy would find the app wrong with no explanation.

**Resolve entries to documents and ignore fragments.** Rejected on evidence:
in the one real book in the repository this collapses five scenes onto one
destination. It is also the version that would have looked correct in a demo
of the first chapter and failed in the second.

**Store the resolved table of contents in the database.** Rejected. Derived
data, invalidated by every parser change, recomputed anyway on every open by
ADR 0004's design. The same argument that keeps parsed blocks out of the
database keeps this out.

**A `Locator` per chapter rather than a token index.** Rejected as
indirection with no payoff: the value is consumed immediately by
`seekToIndex` within the same parse that produced it, and never crosses a
device, a restart or a version boundary, which is what locators exist for.

**Collapsible acts in the panel.** Rejected: an extra interaction between the
reader and the thing they opened the panel to reach.

**A bottom sheet, matching the profile switcher.** Rejected on the request
and on the shape of the content. A chapter list is long and vertical and
benefits from full height; a profile list is five rows.

## Verification

`dart test` and `dart test -p chrome` pass in `epub_reader`, with the golden
test reported as skipped on Chrome. `flutter test` passes in `app`.

The golden test still reads 1154 blocks and 157920 characters. That is the
check that the walk emits what it emitted before: block ids derive from
position within a document, so a change to either number would mean every
stored reading position on every device had silently moved, and
`kParserVersion` would have to move with it. Neither number changed, so
neither does it.

Confirmed on Windows against Romeo and Juliet. The panel lists all 35 entries
the book declares. Act I's five scenes land in five different places, which is
the case fragment resolution exists for and the case that would have failed
silently under an href-only resolution — five rows, one destination, and no
test anywhere would have caught it.

Escape with the panel open closes the panel and leaves the book open.