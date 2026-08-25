-- One row per Project Gutenberg Text record (ADR 0029). Audio, image and
-- dataset records never reach this table — they are filtered out before a
-- row is ever built, because offering one as a book would produce an import
-- that cannot be read.
create table catalogue_entries (
                                    gutenberg_id  integer     primary key,
                                    title         text        not null,
                                    authors       text        not null default '',
                                    language      text        not null,
                                    subjects      text        not null default '',
                                    issued        date,

    -- Set to a fresh id on every row written during one refresh. A refresh
    -- sweeps every row whose ingestion_run does not match once the write
    -- phase finishes, which is what implements "delete what vanished
    -- upstream" without ever building an in-clause of ~78,000 ids.
                                    ingestion_run uuid        not null,

                                    updated_at    timestamptz not null default now()
);

-- Search matches on title or on authors (CatalogueRepository.search); both
-- go through lower(...) so the index actually gets used.
create index catalogue_entries_title_lower on catalogue_entries (lower(title));
create index catalogue_entries_authors_lower on catalogue_entries (lower(authors));
create index catalogue_entries_ingestion_run on catalogue_entries (ingestion_run);
