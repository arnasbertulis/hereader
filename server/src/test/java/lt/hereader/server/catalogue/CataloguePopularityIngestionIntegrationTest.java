package lt.hereader.server.catalogue;

import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream;
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorOutputStream;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;

/// End to end against a real Postgres and CatalogueStubServerTest's shared
/// local HTTP stub, standing in for Gutenberg's catalogue CSV and its bulk
/// RDF archive (ADR 0029, #177).
///
/// `rdf/pg11.rdf`, `rdf/pg15.rdf` and `rdf/pg98.rdf` are real per-book
/// records, trimmed; see `src/test/resources/catalogue/README.md` for
/// provenance, download counts and why id 98 is deliberately absent from
/// `pg_catalog_sample.csv`. CatalogueStubServerTest packs them into a tar.bz2
/// once for the JVM rather than committing a binary archive fixture.
///
/// Every test here runs against the same ingested catalogue: the ten Text
/// entries from the CSV fixture, each with a null download count. Building
/// that is `@BeforeAll` work, not `@BeforeEach` work — the only thing a test
/// changes about it is the `downloads` column, which the popularity refresh
/// under test writes, so that column is what gets reset between tests rather
/// than the whole table (#232).
@SpringBootTest
@ActiveProfiles("test")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class CataloguePopularityIngestionIntegrationTest extends CatalogueStubServerTest {

    @Autowired private WebApplicationContext context;
    @Autowired private CatalogueIngestionService catalogueIngestion;
    @Autowired private CataloguePopularityIngestionService popularityIngestion;
    @Autowired private JdbcClient jdbc;

    private MockMvc mvc;

    @BeforeAll
    void ingestTheCatalogueOnce() {
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .apply(springSecurity())
                .build();

        resetStub();
        jdbc.sql("delete from catalogue_entries").update();
        catalogueIngestion.refresh();
    }

    @BeforeEach
    void resetWhatATestCanChange() {
        resetStub();
        // No test here inserts or deletes an entry — CataloguePopularityIngestionService
        // only ever calls updateDownloads — so restoring that one column is
        // the whole of this class's per-test isolation.
        jdbc.sql("update catalogue_entries set downloads = null").update();
    }

    /// The stub's response state is static and shared with the other
    /// catalogue classes, and CatalogueControllerIntegrationTest has a test
    /// that leaves the CSV route on 503, so the CSV side is reset here even
    /// though nothing in this class changes it.
    private static void resetStub() {
        csvBody = csvFixture;
        csvStatus = 200;
        rdfArchiveBody = rdfArchiveFixture;
        rdfArchiveStatus = 200;
    }

    /// Same shape as CatalogueStubServerTest.buildArchive, but the entry between pg11.rdf and
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
