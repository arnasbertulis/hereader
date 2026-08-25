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
