package lt.hereader.server.catalogue;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/// Weekly, because a volunteer archive does not move at the pace of a news
/// feed (ADR 0029). The refresh policy itself — what runs, in what order, and
/// what happens when a step fails — lives in `CatalogueRefresh`, shared with
/// `CatalogueIngestionRunner`'s manual trigger.
@Component
class CatalogueIngestionScheduler {

    private final CatalogueRefresh refresh;

    CatalogueIngestionScheduler(CatalogueRefresh refresh) {
        this.refresh = refresh;
    }

    @Scheduled(cron = "0 0 3 * * MON", zone = "UTC")
    void scheduledRefresh() {
        refresh.runAll();
    }
}
