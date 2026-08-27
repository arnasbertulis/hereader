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

**Amended by ADR 0029.** That reasoning is about relaying a reader's own
library — not this project's to redistribute, and frequently still under
copyright — and continues to hold for that case unchanged. It does not extend
to streaming a public-domain text from a third-party source with nothing
retained at any point: the service is a pipe there, not a host, and the file
was never the reader's to begin with. ADR 0029 is where that distinction is
put to work, streaming a Project Gutenberg import through the service with no
stored copy on either side of the request.

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

## Verification

The core decision — bytes stored, re-parsed on open — has held since the
app's original import work and is exercised by every Library and reader test
that opens a book; nothing here changed it.

The amendment's own claim, added by ADR 0029, is that streaming an unretained
Gutenberg file through the service is not the relaying this record's
*Consequences* section rejected. Read directly:
`CatalogueProxyService.fetchBookFile`
(`server/src/main/java/lt/hereader/server/catalogue/CatalogueProxyService.java:105`)
streams the response through with no call into the cache-writing path that
`fetchCover` (line 87) uses — a downloaded book file touches no disk on the
service. `CatalogueProxyIntegrationTest` (11 tests, part of the 67 in
`./mvnw --batch-mode -Dtest='lt.hereader.server.catalogue.**' test`, all
passing) exercises the endpoint this streams through, including that a book
number not already in the ingested Catalogue is rejected rather than
proxying an arbitrary URL. Once imported, the resulting Book writes through
the same blob column and re-parse path this record decided on, proven by
`app/test/catalogue_importer_test.dart`, part of the 26 passing tests in
`flutter test test/catalogue_client_test.dart test/catalogue_importer_test.dart
test/free_books_screen_test.dart`.
