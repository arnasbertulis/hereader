package lt.hereader.server.catalogue;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/// The "run one full Catalogue refresh" policy, shared by
/// `CatalogueIngestionScheduler`'s weekly cron and `CatalogueIngestionRunner`'s
/// manual profile — the only two callers (ADR 0029).
///
/// Popularity runs after the Catalogue refresh, in its own try, regardless of
/// whether the Catalogue refresh itself succeeded — the entries it joins
/// against may still be the previous run's, and its own failure mode is
/// already partial-application-tolerant (CataloguePopularityIngestionService).
/// A failed refresh is logged and swallowed rather than rethrown, so a caller
/// with nothing meaningful to do with the exception — the Scheduler — and a
/// caller that only needs to know whether it happened — the Runner's exit
/// code — both get what they need from the outcome alone.
@Component
class CatalogueRefresh {

    private static final Logger log = LoggerFactory.getLogger(CatalogueRefresh.class);

    private final CatalogueIngestionService ingestion;
    private final CataloguePopularityIngestionService popularity;

    CatalogueRefresh(
            CatalogueIngestionService ingestion, CataloguePopularityIngestionService popularity) {
        this.ingestion = ingestion;
        this.popularity = popularity;
    }

    CatalogueRefreshOutcome runAll() {
        var ingestionSucceeded = true;
        try {
            ingestion.refresh();
            log.info("Catalogue refresh completed.");
        } catch (RuntimeException e) {
            log.error("Catalogue refresh failed; the existing Catalogue is unchanged.", e);
            ingestionSucceeded = false;
        }

        var popularitySucceeded = true;
        try {
            popularity.refresh();
            log.info("Catalogue popularity refresh completed.");
        } catch (RuntimeException e) {
            log.error("Catalogue popularity refresh failed; counts already applied are unchanged.", e);
            popularitySucceeded = false;
        }

        return new CatalogueRefreshOutcome(ingestionSucceeded && popularitySucceeded);
    }
}
