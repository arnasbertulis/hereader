package lt.hereader.server.catalogue;

import com.sun.net.httpserver.HttpServer;
import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream;
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorOutputStream;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;

/// End to end against a real Postgres and two local HTTP stubs standing in
/// for Gutenberg's catalogue CSV and its bulk RDF archive (ADR 0029, #177).
///
/// `rdf/pg11.rdf`, `rdf/pg15.rdf` and `rdf/pg98.rdf` are real per-book
/// records, trimmed; see `src/test/resources/catalogue/README.md` for
/// provenance, download counts and why id 98 is deliberately absent from
/// `pg_catalog_sample.csv`. This class packs them into a tar.bz2 itself at
/// setup rather than committing a binary archive fixture.
@SpringBootTest
@ActiveProfiles("test")
class CataloguePopularityIngestionIntegrationTest {

    private static final HttpServer stub = startStub();

    private static volatile byte[] csvBody = readCsvFixture();
    private static volatile byte[] rdfArchiveBody = buildArchive("pg11.rdf", "pg15.rdf", "pg98.rdf");
    private static volatile int rdfArchiveStatus = 200;

    @DynamicPropertySource
    static void upstreamUrls(DynamicPropertyRegistry registry) {
        registry.add("hereader.catalogue.gutenberg-catalog-csv-url",
                () -> "http://localhost:" + stub.getAddress().getPort() + "/pg_catalog.csv");
        registry.add("hereader.catalogue.gutenberg-rdf-archive-url",
                () -> "http://localhost:" + stub.getAddress().getPort() + "/rdf-files.tar.bz2");
    }

    @Autowired private WebApplicationContext context;
    @Autowired private CatalogueIngestionService catalogueIngestion;
    @Autowired private CataloguePopularityIngestionService popularityIngestion;
    @Autowired private JdbcClient jdbc;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .apply(springSecurity())
                .build();

        csvBody = readCsvFixture();
        rdfArchiveBody = buildArchive("pg11.rdf", "pg15.rdf", "pg98.rdf");
        rdfArchiveStatus = 200;
        jdbc.sql("delete from catalogue_entries").update();
        catalogueIngestion.refresh();
    }

    @AfterAll
    static void tearDown() {
        stub.stop(0);
    }

    // -- stub server -----------------------------------------------------

    private static HttpServer startStub() {
        try {
            var server = HttpServer.create(new InetSocketAddress("localhost", 0), 0);
            server.createContext("/pg_catalog.csv", exchange -> {
                var body = csvBody;
                exchange.getResponseHeaders().add("Content-Type", "text/csv; charset=utf-8");
                exchange.sendResponseHeaders(200, body.length);
                try (var out = exchange.getResponseBody()) {
                    out.write(body);
                }
            });
            server.createContext("/rdf-files.tar.bz2", exchange -> {
                var status = rdfArchiveStatus;
                if (status != 200) {
                    exchange.sendResponseHeaders(status, -1);
                    exchange.close();
                    return;
                }
                var body = rdfArchiveBody;
                exchange.getResponseHeaders().add("Content-Type", "application/x-bzip2");
                exchange.sendResponseHeaders(200, body.length);
                try (var out = exchange.getResponseBody()) {
                    out.write(body);
                }
            });
            server.start();
            return server;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static byte[] readCsvFixture() {
        try (InputStream in = CataloguePopularityIngestionIntegrationTest.class
                .getResourceAsStream("/catalogue/pg_catalog_sample.csv")) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /// Packs the named `rdf/*.rdf` fixtures into a tar.bz2 byte array, one
    /// entry per file, named the way the real archive names them
    /// (`cache/epub/<id>/pg<id>.rdf`) — CataloguePopularityIngestionService
    /// does not depend on that name, only on the ".rdf" suffix, but matching
    /// it keeps the fixture honest about what it stands in for.
    private static byte[] buildArchive(String... rdfFileNames) {
        var bytes = new ByteArrayOutputStream();
        try (var bzip2 = new BZip2CompressorOutputStream(bytes);
             var tar = new TarArchiveOutputStream(bzip2)) {

            for (var fileName : rdfFileNames) {
                var id = fileName.substring("pg".length(), fileName.length() - ".rdf".length());
                writeEntry(tar, "cache/epub/" + id + "/" + fileName, readRdfFixture(fileName));
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return bytes.toByteArray();
    }

    /// Same shape as buildArchive, but the entry between pg11.rdf and
    /// pg15.rdf is XML that never closes its root element — proving
    /// GutenbergRdfEntryReader's documented "skip this one, keep streaming"
    /// contract rather than just asserting it in a comment.
    private static byte[] buildArchiveWithOneMalformedEntry() {
        var bytes = new ByteArrayOutputStream();
        try (var bzip2 = new BZip2CompressorOutputStream(bytes);
             var tar = new TarArchiveOutputStream(bzip2)) {

            writeEntry(tar, "cache/epub/11/pg11.rdf", readRdfFixture("pg11.rdf"));
            writeEntry(tar, "cache/epub/9999/pg9999.rdf",
                    "<rdf:RDF><pgterms:ebook rdf:about=\"ebooks/9999\">"
                            .getBytes(StandardCharsets.UTF_8));
            writeEntry(tar, "cache/epub/15/pg15.rdf", readRdfFixture("pg15.rdf"));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return bytes.toByteArray();
    }

    private static void writeEntry(TarArchiveOutputStream tar, String name, byte[] content) throws IOException {
        var entry = new TarArchiveEntry(name);
        entry.setSize(content.length);
        tar.putArchiveEntry(entry);
        tar.write(content);
        tar.closeArchiveEntry();
    }

    private static byte[] readRdfFixture(String fileName) {
        try (InputStream in = CataloguePopularityIngestionIntegrationTest.class
                .getResourceAsStream("/catalogue/rdf/" + fileName)) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    // -- join ------------------------------------------------------------

    @Test
    void popularityRefreshAppliesDownloadCountsToMatchingEntries() throws Exception {
        popularityIngestion.refresh();

        mvc.perform(get("/catalogue/search?sort=popularity"))
                .andExpect(jsonPath("$.results[0].gutenbergId").value(11))
                .andExpect(jsonPath("$.results[1].gutenbergId").value(15));
    }

    @Test
    void anArchiveRecordWithNoMatchingCatalogueEntryIsNotInserted() throws Exception {
        // 10 Text entries from the CSV fixture; id 98 (in the archive, not
        // the CSV) must not become an 11th.
        popularityIngestion.refresh();

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(10)));
    }

    // -- sorting -----------------------------------------------------------

    @Test
    void aSearchWithNoQueryTextReturnsTheMostDownloadedEntriesFirst() throws Exception {
        popularityIngestion.refresh();

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results[0].gutenbergId").value(11));
    }

    @Test
    void popularityIsAvailableAsAnExplicitSort() throws Exception {
        popularityIngestion.refresh();

        mvc.perform(get("/catalogue/search?sort=popularity"))
                .andExpect(jsonPath("$.results[0].gutenbergId").value(11))
                .andExpect(jsonPath("$.results[1].gutenbergId").value(15));
    }

    @Test
    void anExplicitTitleSortOverridesTheBlankQueryPopularityDefault() throws Exception {
        popularityIngestion.refresh();

        // id 11 leads either way (alphabetically first and most downloaded),
        // so the real check is the second row: id 15 (second-most downloads)
        // under the popularity default, but id 84 ("Frankenstein...", the
        // second Text title alphabetically) once sort=title is explicit.
        mvc.perform(get("/catalogue/search?sort=title"))
                .andExpect(jsonPath("$.results[0].gutenbergId").value(11))
                .andExpect(jsonPath("$.results[1].gutenbergId").value(84));
    }

    @Test
    void anEntryWithNoDownloadCountRemainsSearchableAndSortsLastUnderPopularity() throws Exception {
        popularityIngestion.refresh();

        // 10 Text entries total, only ids 11 and 15 have a download count;
        // the other 8 sort by title among themselves, last of which is
        // "Through the Looking-Glass" (id 12).
        mvc.perform(get("/catalogue/search?sort=popularity&size=10"))
                .andExpect(jsonPath("$.results", hasSize(10)))
                .andExpect(jsonPath("$.results[9].gutenbergId").value(12));
    }

    @Test
    void anEntryWithMalformedXmlIsSkippedWithoutAbortingTheRefresh() throws Exception {
        rdfArchiveBody = buildArchiveWithOneMalformedEntry();

        popularityIngestion.refresh();

        // Both real entries either side of the malformed one still applied —
        // the archive kept streaming past it rather than aborting.
        mvc.perform(get("/catalogue/search?sort=popularity"))
                .andExpect(jsonPath("$.results[0].gutenbergId").value(11))
                .andExpect(jsonPath("$.results[1].gutenbergId").value(15));
    }

    // -- failure isolation -------------------------------------------------

    @Test
    void aPopularityRefreshThatEndsMidArchiveAbortsButLeavesTheCatalogueIntact() throws Exception {
        // Valid bzip2/tar framing up to a point, then nothing — the shape a
        // connection dropped mid-download takes.
        var full = rdfArchiveBody;
        rdfArchiveBody = java.util.Arrays.copyOf(full, full.length / 2);

        assertThatThrownBy(popularityIngestion::refresh)
                .isInstanceOf(CatalogueIngestionException.class);

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.catalogueReady").value(true))
                .andExpect(jsonPath("$.results", hasSize(10)));
    }

    @Test
    void aMalformedArchiveAbortsThePopularityRefreshButLeavesTheCatalogueIntact() throws Exception {
        // Not bzip2 at all, from the first byte — distinct from the
        // mid-download truncation above, which is valid framing that just
        // stops.
        rdfArchiveBody = "not a bzip2 archive".getBytes(StandardCharsets.UTF_8);

        assertThatThrownBy(popularityIngestion::refresh)
                .isInstanceOf(CatalogueIngestionException.class);

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.catalogueReady").value(true))
                .andExpect(jsonPath("$.results", hasSize(10)));
    }

    @Test
    void aNonTwoHundredResponseAbortsThePopularityRefresh() {
        rdfArchiveStatus = 503;

        assertThatThrownBy(popularityIngestion::refresh)
                .isInstanceOf(CatalogueIngestionException.class);
    }
}
