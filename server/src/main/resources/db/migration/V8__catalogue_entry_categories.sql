-- One row per (Catalogue Entry, Category) pair, extracted from the CSV's
-- Bookshelves column at ingestion (CatalogueIngestionService) — only the
-- tokens prefixed "Category: " are kept, the rest of that column is a
-- looser, uncurated shelf list this feature does not filter by (#178).
-- An Entry can carry more than one Category, hence the join table rather
-- than a column on catalogue_entries.
create table catalogue_entry_categories (
    gutenberg_id integer not null references catalogue_entries (gutenberg_id) on delete cascade,
    category     text    not null,
    primary key (gutenberg_id, category)
);

-- Supports both the category filter (CatalogueRepository.search) and the
-- per-category counts (CatalogueRepository.categoryCounts).
create index catalogue_entry_categories_category on catalogue_entry_categories (category);
