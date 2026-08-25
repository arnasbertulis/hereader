package lt.hereader.server.catalogue;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/// Weekly, because a volunteer archive does not move at the pace of a news
/// feed (ADR 0029). A failed refresh is logged and swallowed rather than
/// rethrown — there is no caller here to hand it to, and the existing
/// Catalogue is already untouched by the time refresh() can fail.
@Component
class CatalogueIngestionScheduler {

    private static final Logger log =
            LoggerFactory.getLogger(CatalogueIngestionScheduler.class);

    private final CatalogueIngestionService ingestion;

    CatalogueIngestionScheduler(CatalogueIngestionService ingestion) {
        this.ingestion = ingestion;
    }

    @Scheduled(cron = "0 0 3 * * MON", zone = "UTC")
    void scheduledRefresh() {
        try {
            ingestion.refresh();
            log.info("Catalogue refresh completed.");
        } catch (RuntimeException e) {
            log.error("Catalogue refresh failed; the existing Catalogue is unchanged.", e);
        }
    }
}
