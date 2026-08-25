package lt.hereader.server.catalogue;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.util.Comparator;
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
class CatalogueProxyIntegrationTest {

    private static final int INGESTED_ID = 11;
    private static final int NOT_INGESTED_ID = 999999;

    private static final HttpServer stub = startStub();

    private static volatile byte[] coverBody = "cover-bytes".getBytes(StandardCharsets.UTF_8);
    private static volatile int coverStatus = 200;
    private static volatile byte[] noImagesBody = "epub-noimages-bytes".getBytes(StandardCharsets.UTF_8);
    private static volatile int noImagesStatus = 200;
    private static volatile byte[] imagesBody = "epub-images-bytes".getBytes(StandardCharsets.UTF_8);
    private static volatile int imagesStatus = 200;
    // When true, the cover (or no-images book file) handler declares a body
    // longer than what it actually writes, simulating a connection Gutenberg
    // drops mid-response.
    private static volatile boolean truncateCover = false;
    private static volatile boolean truncateNoImages = false;

    @DynamicPropertySource
    static void gutenbergUrls(DynamicPropertyRegistry registry) {
        var base = "http://localhost:" + stub.getAddress().getPort();
        registry.add("hereader.catalogue.gutenberg-cover-url-template", () -> base + "/covers/{id}");
        registry.add("hereader.catalogue.gutenberg-epub-noimages-url-template", () -> base + "/noimages/{id}");
        registry.add("hereader.catalogue.gutenberg-epub-images-url-template", () -> base + "/images/{id}");
        registry.add("hereader.catalogue.gutenberg-http-timeout-seconds", () -> "1");
    }

    @TempDir
    static Path coverCacheDir;

    @DynamicPropertySource
    static void coverCacheDir(DynamicPropertyRegistry registry) {
        registry.add("hereader.catalogue.cover-cache-dir", () -> coverCacheDir.toString());
    }

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

    @AfterAll
    static void tearDown() {
        stub.stop(0);
    }

    /// coverCacheDir is created once for the whole class (DynamicPropertySource
    /// runs at context startup, not per test), so a file a caching test wrote
    /// would otherwise leak into the next test and make it order-dependent —
    /// e.g. aMissingCoverUpstreamIsAClean404 would see a cache hit instead of
    /// reaching the stub's 404.
    private static void clearCoverCache() {
        try (var files = Files.walk(coverCacheDir)) {
            files.filter(path -> !path.equals(coverCacheDir))
                    .sorted(Comparator.reverseOrder())
                    .forEach(path -> {
                        try {
                            Files.delete(path);
                        } catch (IOException e) {
                            throw new UncheckedIOException(e);
                        }
                    });
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    // -- stub server -----------------------------------------------------

    private static HttpServer startStub() {
        try {
            var server = HttpServer.create(new InetSocketAddress("localhost", 0), 0);
            server.createContext("/covers/", exchange -> {
                var body = coverBody;
                if (truncateCover) {
                    // Declares the full length but writes half of it, then
                    // closes — the shape of a dropped connection.
                    exchange.sendResponseHeaders(coverStatus, body.length);
                    try (var out = exchange.getResponseBody()) {
                        out.write(body, 0, body.length / 2);
                    }
                    return;
                }
                exchange.sendResponseHeaders(coverStatus, coverStatus == 200 ? body.length : -1);
                try (var out = exchange.getResponseBody()) {
                    if (coverStatus == 200) {
                        out.write(body);
                    }
                }
            });
            server.createContext("/noimages/", exchange -> {
                var body = noImagesBody;
                if (truncateNoImages) {
                    exchange.sendResponseHeaders(noImagesStatus, body.length);
                    try (var out = exchange.getResponseBody()) {
                        out.write(body, 0, body.length / 2);
                    }
                    return;
                }
                exchange.sendResponseHeaders(noImagesStatus, noImagesStatus == 200 ? body.length : -1);
                try (var out = exchange.getResponseBody()) {
                    if (noImagesStatus == 200) {
                        out.write(body);
                    }
                }
            });
            server.createContext("/images/", exchange -> {
                var body = imagesBody;
                exchange.sendResponseHeaders(imagesStatus, imagesStatus == 200 ? body.length : -1);
                try (var out = exchange.getResponseBody()) {
                    if (imagesStatus == 200) {
                        out.write(body);
                    }
                }
            });
            server.start();
            return server;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
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
