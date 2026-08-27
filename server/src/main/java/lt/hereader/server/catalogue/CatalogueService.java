package lt.hereader.server.catalogue;

import org.springframework.stereotype.Service;

import java.util.List;

/// Search only — ingestion lives in CatalogueIngestionService, a separate
/// concern with a separate seam (a scheduled job and a hand-run one, neither
/// reachable over HTTP).
@Service
public class CatalogueService {

    private static final int MAX_PAGE_SIZE = 50;
    private static final int DEFAULT_PAGE_SIZE = 20;

    private final CatalogueRepository repository;

    CatalogueService(CatalogueRepository repository) {
        this.repository = repository;
    }

    /// [requestedSort] is null when the caller named no explicit sort —
    /// CatalogueController is where "sort=popularity" text becomes the enum
    /// or a 400, so by the time it reaches here it is already valid. Left
    /// unset, a blank query defaults to POPULARITY (so opening the Catalogue
    /// with no search text is a shelf of what's actually being read, not an
    /// alphabetical database dump) and a non-blank one defaults to TITLE.
    ///
    /// [requestedDirection] is likewise null when the caller named no
    /// explicit direction, and defaults per the resolved [sort]: DESCENDING
    /// for POPULARITY (most downloaded first), ASCENDING otherwise
    /// (alphabetical, oldest first) — each field's existing default,
    /// unchanged for every caller that predates the direction parameter.
    ///
    /// [category] and [language] are trimmed here and left blank for "no
    /// filter" — an unrecognized value of either narrows the result to
    /// nothing rather than failing, since CatalogueRepository.search treats
    /// them as ordinary equality/existence conditions, never as a fixed
    /// vocabulary. No language is applied unless the caller names one, so a
    /// reader is never defaulted into a language they didn't ask for.
    public CatalogueDtos.SearchResponse search(
            String query, String category, String language,
            int page, Integer size, CatalogueDtos.Sort requestedSort,
            CatalogueDtos.Direction requestedDirection) {

        var normalizedQuery = normalize(query);
        var normalizedCategory = normalize(category);
        var normalizedLanguage = normalize(language);
        var cappedSize = Math.min(Math.max(size == null ? DEFAULT_PAGE_SIZE : size, 1), MAX_PAGE_SIZE);
        var sort = requestedSort != null
                ? requestedSort
                : normalizedQuery.isEmpty() ? CatalogueDtos.Sort.POPULARITY : CatalogueDtos.Sort.TITLE;
        var direction = requestedDirection != null
                ? requestedDirection
                : sort == CatalogueDtos.Sort.POPULARITY
                        ? CatalogueDtos.Direction.DESCENDING
                        : CatalogueDtos.Direction.ASCENDING;

        if (!repository.hasAnyEntries()) {
            return new CatalogueDtos.SearchResponse(false, List.of(), page, false);
        }

        // One extra row, so hasMore is known without a second, count-only
        // query — the same trick SyncRepository.eventsSince uses.
        var fetched = repository.search(
                normalizedQuery, normalizedCategory, normalizedLanguage,
                page * cappedSize, cappedSize + 1, sort, direction);
        var hasMore = fetched.size() > cappedSize;
        var results = hasMore ? fetched.subList(0, cappedSize) : fetched;

        return new CatalogueDtos.SearchResponse(true, results, page, hasMore);
    }

    /// Every Category at least one Catalogue Entry carries, with its count —
    /// unaffected by search text or the filters above, since this is the
    /// list a reader picks a filter *from*, not a summary of a filtered page.
    public List<CatalogueDtos.CategoryCount> categories() {
        return repository.categoryCounts();
    }

    /// Every Language at least one Catalogue Entry carries, with its count —
    /// unaffected by search text or the filters above, since this is the
    /// list a reader picks a filter *from*, not a summary of a filtered page.
    public List<CatalogueDtos.LanguageCount> languages() {
        return repository.languageCounts();
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim();
    }
}
