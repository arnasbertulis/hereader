package lt.hereader.server.catalogue;

/// The Catalogue search criteria, normalised, defaulted and capped once here
/// rather than re-derived at every hop (CatalogueController, CatalogueService,
/// CatalogueRepository) — see #213. Package-private, like CatalogueController:
/// nothing outside this package builds one, and every caller inside it goes
/// through [of], which is where the rules live — the canonical constructor
/// itself does no defaulting.
record CatalogueQuery(
        String query,
        String category,
        String language,
        int page,
        int size,
        CatalogueDtos.Sort sort,
        CatalogueDtos.Direction direction) {

    private static final int MAX_PAGE_SIZE = 50;
    private static final int DEFAULT_PAGE_SIZE = 20;

    /// [requestedSort] and [requestedDirection] are null when the caller
    /// named no explicit value — CatalogueController turns request text into
    /// these enums or a 400 before this is called, so by the time either
    /// reaches here it is already valid or absent. A blank [query] defaults
    /// to POPULARITY (so opening the Catalogue with no search text is a shelf
    /// of what's actually being read, not an alphabetical database dump) and
    /// a non-blank one to TITLE; [direction] then defaults per the *resolved*
    /// sort: DESCENDING for POPULARITY (most downloaded first), ASCENDING
    /// otherwise (alphabetical, oldest first) — each field's own existing
    /// default. [size] clamps between 1 and MAX_PAGE_SIZE, defaulting to
    /// DEFAULT_PAGE_SIZE when absent. [category] and [language] are trimmed
    /// and left blank for "no filter" — an unrecognized value of either
    /// narrows the result to nothing rather than failing, since
    /// CatalogueRepository.search treats them as ordinary equality/existence
    /// conditions, never as a fixed vocabulary.
    static CatalogueQuery of(
            String query, String category, String language,
            int page, Integer size,
            CatalogueDtos.Sort requestedSort, CatalogueDtos.Direction requestedDirection) {

        var normalizedQuery = normalize(query);
        var sort = requestedSort != null
                ? requestedSort
                : normalizedQuery.isEmpty() ? CatalogueDtos.Sort.POPULARITY : CatalogueDtos.Sort.TITLE;
        var direction = requestedDirection != null
                ? requestedDirection
                : sort == CatalogueDtos.Sort.POPULARITY
                        ? CatalogueDtos.Direction.DESCENDING
                        : CatalogueDtos.Direction.ASCENDING;
        var cappedSize = Math.min(Math.max(size == null ? DEFAULT_PAGE_SIZE : size, 1), MAX_PAGE_SIZE);

        return new CatalogueQuery(
                normalizedQuery, normalize(category), normalize(language), page, cappedSize, sort, direction);
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim();
    }
}
