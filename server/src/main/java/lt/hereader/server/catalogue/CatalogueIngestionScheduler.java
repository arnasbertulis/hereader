package lt.hereader.server.catalogue;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/// Weekly, because a volunteer archive does not move at the pace of a news
/// feed (ADR 0029). A failed refresh is logged and swallowed rather than
/// rethrown — there is no caller here to hand it to, and the existing
/// Catalogue is already untouched by the time refresh() can fail.
///
/// Popularity runs after the Catalogue refresh, in its own try, regardless of
/// whether the Catalogue refresh itself succeeded — the entries it joins
/// against may still be the previous run's, and its own failure mode is
/// already partial-application-tolerant (CataloguePopularityIngestionService).
@Component
class CatalogueIngestionScheduler {

    private static final Logger log =
            LoggerFactory.getLogger(CatalogueIngestionScheduler.class);

    private final CatalogueIngestionService ingestion;
    private final CataloguePopularityIngestionService popularity;

    CatalogueIngestionScheduler(
            CatalogueIngestionService ingestion, CataloguePopularityIngestionService popularity) {
        this.ingestion = ingestion;
        this.popularity = popularity;
    }

    @Scheduled(cron = "0 0 3 * * MON", zone = "UTC")
    void scheduledRefresh() {
        try {
            ingestion.refresh();
            log.info("Catalogue refresh completed.");
        } catch (RuntimeException e) {
            log.error("Catalogue refresh failed; the existing Catalogue is unchanged.", e);
        }

        try {
            popularity.refresh();
            log.info("Catalogue popularity refresh completed.");
        } catch (RuntimeException e) {
            log.error("Catalogue popularity refresh failed; counts already applied are unchanged.", e);
        }
    }
}
