package lt.hereader.server.catalogue;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

/// Plain unit tests: no Spring context. `CatalogueRefresh` is the single
/// place the "run one full Catalogue refresh" policy lives, so its invariant
/// — popularity refreshes regardless of whether the Catalogue refresh
/// succeeded — is tested here rather than through either caller.
class CatalogueRefreshTest {

    private final CatalogueIngestionService ingestion = mock(CatalogueIngestionService.class);
    private final CataloguePopularityIngestionService popularity =
            mock(CataloguePopularityIngestionService.class);

    private final CatalogueRefresh refresh = new CatalogueRefresh(ingestion, popularity);

    @Test
    void popularityStillRunsWhenTheCatalogueRefreshFailsAndTheOutcomeReportsFailure() {
        doThrow(new RuntimeException("upstream unreachable")).when(ingestion).refresh();

        var outcome = refresh.runAll();

        verify(popularity).refresh();
        assertThat(outcome.succeeded()).isFalse();
    }

    @Test
    void theOutcomeReportsSuccessWhenBothStepsSucceed() {
        var outcome = refresh.runAll();

        verify(ingestion).refresh();
        verify(popularity).refresh();
        assertThat(outcome.succeeded()).isTrue();
    }
}
