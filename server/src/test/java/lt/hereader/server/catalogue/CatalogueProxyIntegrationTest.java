package lt.hereader.server.catalogue;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.UUID;

import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/// End to end through the real filter chain and a real Postgres, against a
/// local HTTP stub standing in for Gutenberg's per-book files — the same
/// shape as CatalogueControllerIntegrationTest, for the two proxy endpoints
/// #179 adds.
///
/// One ingested Entry (id 11) backs every test; the "not ingested" cases use
/// an id that was never written.
@SpringBootTest
@ActiveProfiles("test")
class CatalogueProxyIntegrationTest extends CatalogueStubServerTest {

    private static final int INGESTED_ID = 11;
    private static final int NOT_INGESTED_ID = 999999;

    @Autowired private WebApplicationContext context;
    @Autowired private CatalogueRepository repository;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .apply(springSecurity())
                .build();

        coverBody = "cover-bytes".getBytes(StandardCharsets.UTF_8);
        coverStatus = 200;
        noImagesBody = "epub-noimages-bytes".getBytes(StandardCharsets.UTF_8);
        noImagesStatus = 200;
        imagesBody = "epub-images-bytes".getBytes(StandardCharsets.UTF_8);
        imagesStatus = 200;
        truncateCover = false;
        truncateNoImages = false;
        clearCoverCache();

        repository.upsert(
                INGESTED_ID, "Alice's Adventures in Wonderland", "Carroll, Lewis",
                "en", "Fantasy fiction", LocalDate.of(2008, 6, 27), UUID.randomUUID());
    }

    // -- book number gating ------------------------------------------------

    @Test
    void aBookNumberNeverIngestedIsRejectedOnCover() throws Exception {
        mvc.perform(get("/catalogue/cover/" + NOT_INGESTED_ID))
                .andExpect(status().isNotFound());
    }

    @Test
    void aBookNumberNeverIngestedIsRejectedOnDownload() throws Exception {
        mvc.perform(get("/catalogue/download/" + NOT_INGESTED_ID))
                .andExpect(status().isNotFound());
    }

    // -- cover ---------------------------------------------------------

    @Test
    void aCoverIsFetchedWithoutAnAccount() throws Exception {
        mvc.perform(get("/catalogue/cover/" + INGESTED_ID))
                .andExpect(status().isOk())
                .andExpect(content().bytes(coverBody))
                .andExpect(header().exists("Cache-Control"));
    }

    @Test
    void aMissingCoverUpstreamIsAClean404() throws Exception {
        coverStatus = 404;

        mvc.perform(get("/catalogue/cover/" + INGESTED_ID))
                .andExpect(status().isNotFound());
    }

    @Test
    void aSecondCoverRequestIsServedFromCacheRatherThanRefetched() throws Exception {
        mvc.perform(get("/catalogue/cover/" + INGESTED_ID))
                .andExpect(status().isOk())
                .andExpect(content().bytes(coverBody));

        // If the second request went to the stub again it would now fail —
        // proof the cache, not Gutenberg, answered it.
        coverStatus = 500;

        mvc.perform(get("/catalogue/cover/" + INGESTED_ID))
                .andExpect(status().isOk())
                .andExpect(content().bytes(coverBody));
    }

    // -- download: no-images edition preferred ------------------------------

    @Test
    void aDownloadServesTheNoImagesEditionWhenItExists() throws Exception {
        mvc.perform(get("/catalogue/download/" + INGESTED_ID))
                .andExpect(status().isOk())
                .andExpect(content().bytes(noImagesBody));
    }

    @Test
    void aDownloadFallsBackToTheImagesEditionWhenNoImagesIsMissing() throws Exception {
        noImagesStatus = 404;

        mvc.perform(get("/catalogue/download/" + INGESTED_ID))
                .andExpect(status().isOk())
                .andExpect(content().bytes(imagesBody));
    }

    @Test
    void aDownloadIsAClean404WhenNeitherEditionExists() throws Exception {
        noImagesStatus = 404;
        imagesStatus = 404;

        mvc.perform(get("/catalogue/download/" + INGESTED_ID))
                .andExpect(status().isNotFound());
    }

    // -- upstream failure and truncation -------------------------------

    @Test
    void anUpstreamServerErrorIsReportedRatherThanRelayed() throws Exception {
        noImagesStatus = 503;
        imagesStatus = 503;

        mvc.perform(get("/catalogue/download/" + INGESTED_ID))
                .andExpect(status().isBadGateway());
    }

    @Test
    void aTruncatedUpstreamCoverNeverReachesTheCallerAsA200() throws Exception {
        truncateCover = true;

        mvc.perform(get("/catalogue/cover/" + INGESTED_ID))
                .andExpect(status().isBadGateway());
    }

    @Test
    void aTruncatedUpstreamBookFileNeverReachesTheCallerAsA200() throws Exception {
        truncateNoImages = true;

        mvc.perform(get("/catalogue/download/" + INGESTED_ID))
                .andExpect(status().isBadGateway());
    }
}
