-- Download count per book, streamed from Gutenberg's bulk RDF metadata
-- archive (ADR 0029, #177). Null until a popularity refresh has run, or when
-- the archive carries no count for that book — CatalogueRepository.search
-- sorts nulls last under popularity, so an Entry without one stays
-- searchable rather than dropping out of a popularity-ordered page.
alter table catalogue_entries add column downloads integer;

-- Supports the default and explicit popularity sort; nulls last matches the
-- query's own ordering so the index is actually usable for it.
create index catalogue_entries_downloads on catalogue_entries (downloads desc nulls last);
