package lt.hereader.server.catalogue;

import org.springframework.stereotype.Service;

import java.util.List;

/// Search only — ingestion lives in CatalogueIngestionService, a separate
/// concern with a separate seam (a scheduled job and a hand-run one, neither
/// reachable over HTTP).
@Service
public class CatalogueService {

    private final CatalogueRepository repository;

    CatalogueService(CatalogueRepository repository) {
        this.repository = repository;
    }

    /// [query] carries the normalisation, defaulting and size capping
    /// already applied (CatalogueQuery.of), so this only orchestrates the
    /// "empty Catalogue" short-circuit and the one-extra-row hasMore trick.
    public CatalogueDtos.SearchResponse search(CatalogueQuery query) {

        if (!repository.hasAnyEntries()) {
            return new CatalogueDtos.SearchResponse(false, List.of(), query.page(), false);
        }

        // One extra row, so hasMore is known without a second, count-only
        // query — the same trick SyncRepository.eventsSince uses.
        var fetched = repository.search(query, query.page() * query.size(), query.size() + 1);
        var hasMore = fetched.size() > query.size();
        var results = hasMore ? fetched.subList(0, query.size()) : fetched;

        return new CatalogueDtos.SearchResponse(true, results, query.page(), hasMore);
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
}
