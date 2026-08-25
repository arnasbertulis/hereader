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

    public CatalogueDtos.SearchResponse search(String query, int page, Integer size) {
        var normalizedQuery = query == null ? "" : query.trim();
        var cappedSize = Math.min(Math.max(size == null ? DEFAULT_PAGE_SIZE : size, 1), MAX_PAGE_SIZE);

        if (!repository.hasAnyEntries()) {
            return new CatalogueDtos.SearchResponse(false, List.of(), page, false);
        }

        // One extra row, so hasMore is known without a second, count-only
        // query — the same trick SyncRepository.eventsSince uses.
        var fetched = repository.search(normalizedQuery, page * cappedSize, cappedSize + 1);
        var hasMore = fetched.size() > cappedSize;
        var results = hasMore ? fetched.subList(0, cappedSize) : fetched;

        return new CatalogueDtos.SearchResponse(true, results, page, hasMore);
    }
}
