# 0004. Store book files, not parsed text

Date: 2026-08-02

## Status

Accepted.

## Context

The app needs books to survive a restart. Two things could be persisted: the
original EPUB bytes, or the parsed output — normalized blocks, or the token
stream, or both.

Caching the parsed output is the obvious performance answer. Parsing Romeo and
Juliet takes about 240 ms, and tokenizing on top of that adds more. Doing that
work on every open is visible.

Against it: parsed output is derived data. `kParserVersion` exists precisely
because normalization can change, and every change invalidates every cached
copy. Block ids derive from position within a document, so a change to the
walk shifts them all. A cache would need either a migration path or a
wholesale rebuild on every parser change, and the rebuild needs the original
file anyway.

Separately, the bytes have to go somewhere: the filesystem, or a column in the
database.

## Decision

### Store the EPUB bytes, re-parse on open

The parser is the single source of truth for blocks, ids and offsets. A
normalizer improvement applies to books already in the library rather than
leaving them on a stale cache.

240 ms behind a loading indicator is acceptable for an operation the reader
performs once per sitting. If it stops being acceptable — long books, slow
devices — the fix is caching parsed output *keyed by* `kParserVersion`, with
the file still present as the rebuild source. That is strictly more work than
today's design, not different from it.

### Bytes live in a blob column, not on disk

Filesystem paths are not stable across platforms. iOS moves the application
container between installs, so a stored absolute path breaks on update. The
web has no filesystem at all, and the app targets it.

A blob column behaves identically everywhere and makes deletion atomic: no
orphaned files left behind when a row goes away.

### Reading positions are a separate table

Not columns on the books table. Positions are written constantly and read
once; book metadata is written once and read constantly. They sync under
different conflict rules — last-write-wins is fine for a font size and wrong
for a reading position. And the outbox references them independently.

### The outbox ships in schema version 1

Nothing drains it yet. Adding it later would mean migrating a table that is
already being written to on every pause, so the empty table costs nothing now
and saves a migration later.

## Consequences

Every book open pays a parse. The loading indicator is not cosmetic.

Large books make large rows. This is fine for text; a heavily illustrated
volume would put tens of megabytes in a single blob, which SQLite handles but
does not enjoy. Noted as a limitation rather than solved.

Books do not follow the reader between devices, because the server never
receives them. Position sync works regardless: a reader who imports the same
book on two devices gets a shared position. File transfer, if it happens, will
be device-to-device or through the platform share sheet rather than through
the server. Relaying book files would make this project a service that
transmits copyrighted content, which is exactly what storing them on-device
avoids.

Deleting a book cascades to its position, which requires
`PRAGMA foreign_keys = ON`. SQLite disables foreign keys by default, so this
is set in `beforeOpen` rather than assumed.

## Alternatives considered

**Cache the token stream.** Rejected: largest of the three representations,
invalidated by both parser and tokenizer changes, and the tokenizer is the
part most likely to keep changing as more languages are handled.

**Cache normalized blocks, re-tokenize on open.** Rejected for now. It is the
sensible middle option and the one to reach for if parse time becomes a
problem, but it still needs version-keyed invalidation, and there is no
evidence yet that 240 ms is a problem worth that complexity.

**Files on disk with a path column.** Rejected: breaks on iOS container
moves, impossible on web, and leaves orphans when deletion half-fails.
