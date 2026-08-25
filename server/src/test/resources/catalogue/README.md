# Test fixtures

## pg_catalog_sample.csv

Thirteen rows taken verbatim from Project Gutenberg's own bulk catalogue
export, `https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv`.

Captured 2026-08-25. At capture the full export was 21,188,767 bytes across
90,581 lines (rows plus embedded newlines), with 79,252 records of which
78,001 were of type Text — the same figures ADR 0029 cites.

Selected, not synthesized, so the format's real edge cases are exercised
rather than assumed: a title spanning two physical lines inside its quotes
(id 2), a blank Authors field (id 7), multiple authors joined with `; `,
some carrying a bracketed role such as `[Illustrator]` (ids 79435, 79438), a
non-ASCII author name (id 79438), a non-English Language value (id 79438,
`fr`), and titles containing their own semicolons and commas inside quotes
(ids 15, 83, 84). Ids 3002 (Sound), 4749 (Image) and 50 (Dataset) are the
non-Text types Ingestion must discard.

`CatalogueControllerIntegrationTest` derives its "a book vanished upstream"
and "the export was truncated mid-download" scenarios by slicing this same
file's rows in memory rather than committing second and third fixture files
for states that are not really a second upstream snapshot.

## rdf/pg11.rdf, rdf/pg15.rdf, rdf/pg98.rdf

One real per-book record each, captured 2026-08-25 from
`https://www.gutenberg.org/cache/epub/<id>/pg<id>.rdf` — the same per-book
file Gutenberg's bulk `rdf-files.tar.bz2` archive packs one of per book
(ADR 0029, #177). Trimmed to the elements `GutenbergRdfEntryReader` actually
reads (`pgterms:ebook`'s `rdf:about`, `pgterms:downloads`) plus enough
surrounding structure — creator, title, type — to stand in for a real entry
rather than a synthetic one; the `dcterms:hasFormat` blocks real records carry
one of per file format are omitted since nothing here parses them.

`id 11` (Alice's Adventures in Wonderland, 94,492 downloads) and `id 15`
(Moby-Dick, 2,826 downloads) are both in `pg_catalog_sample.csv`, so a
popularity refresh has an existing Catalogue Entry to join each to. `id 98`
(A Tale of Two Cities, 29,682 downloads) is deliberately **not** in that CSV
sample — it exercises "the archive names a book the Catalogue doesn't have",
which `CatalogueRepository.updateDownloads` treats as a no-op rather than an
insert, since the two exports join on the Gutenberg book number with no
fuzzy matching.

`CataloguePopularityIngestionIntegrationTest` packs these three into a
`tar.bz2` in memory with commons-compress at test setup, rather than
committing a binary archive fixture that would not be diff-reviewable; its
"archive truncated mid-download" scenario cuts that constructed byte array,
the same technique `CatalogueControllerIntegrationTest` uses on the CSV text.
