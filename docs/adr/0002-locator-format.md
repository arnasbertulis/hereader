# 0002. Reading positions as character offsets, not word indices

Status: accepted
Date: 2026-07-27

## Context

The app has to remember where a reader stopped, restore that position on
another device, and keep it correct when the reader switches between the
RSVP view and the conventional paged view.

Two things make this harder than it first appears.

The tokenizer will keep changing. Abbreviation handling, hyphenation
rules, and language-specific behaviour will all be revised over the life
of the project, and any change to how text is split alters how many
tokens a book contains.

The app is also intended to support formats beyond EPUB later, PDF in
particular. A position format tied to EPUB internals would have to be
replaced rather than extended.

## Options

1. **Global word index.** The token number counted from the start of the
   book. Simplest to implement.
2. **Block-scoped word index.** A block identifier plus the token number
   within that block.
3. **Block identifier plus character offset into that block's source
   text.** Anchored to the source, not to the tokenizer's output.
4. **EPUB Canonical Fragment Identifier (CFI).** The interoperable
   standard used by other readers.
5. **Percentage through the book.** Trivial to compute.

## Decision

Option 3. A position is stored as:

```
{ bookId, blockId, charOffset, parserVersion }
```

`blockId` is derived from the EPUB spine item href plus the block's index
within that item, hashed. It is deliberately not a sequential number
across the book, so reparsing or inserting one block does not shift the
identifiers of every block after it.

`charOffset` is a character index into the source text of that block.

`parserVersion` records which version of the normalisation pipeline
produced the block the offset was measured against.

Options 1 and 2 were rejected because a tokenizer change silently moves
every saved position, and the failure is invisible. Nobody reports "my
bookmark is forty words off"; they quietly lose their place.

Option 4 was rejected because CFI is substantially more work to implement
correctly and only solves the problem for EPUB. Interoperability with
other reading apps is not a goal.

Option 5 was rejected as too imprecise for resuming mid-paragraph, which
is what RSVP reading requires.

## Consequences

Positive:

- Tokenizer changes do not invalidate stored positions. The offset points
  into text the tokenizer reads, not text it produces.
- The format carries no EPUB-specific concepts, so a PDF or plain text
  source can reuse it unchanged.
- The same locator serves the RSVP view and the paged view, which is what
  makes switching between them mid-paragraph possible.
- Positions are small and comparable, keeping the sync payload cheap.

Negative and accepted:

- Resuming requires tokenizing the target block and finding the first
  token whose `charOffset` is at or beyond the stored value. Linear in
  block size, which is acceptable, but not a direct lookup.
- If normalisation changes such that a block's source text itself
  changes, offsets within that block become wrong. `parserVersion` exists
  so this is detected and migrated deliberately rather than failing
  silently.
- Positions are not portable to or from other reading apps.
- A different edition of the same book produces different block
  identifiers. A content fingerprint on the book record is needed to
  detect this, deferred until the sync work.
