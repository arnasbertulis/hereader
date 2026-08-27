package lt.hereader.server.catalogue;

import com.sun.net.httpserver.HttpServer;
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

import tools.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/// End to end through the real filter chain and a real Postgres, against a
/// local HTTP stub standing in for Gutenberg's export (upstream locations
/// are a configuration property — see catalogueCsvUrl below).
///
/// `pg_catalog_sample.csv` is thirteen real rows; see
/// `src/test/resources/catalogue/README.md` for provenance and which
/// format edge case each row exercises. The "a book vanished upstream" and
/// "the export was truncated mid-download" scenarios below slice that same
/// text in memory rather than committing separate fixtures for states that
/// are not really a second upstream snapshot.
@SpringBootTest
@ActiveProfiles("test")
class CatalogueControllerIntegrationTest {

    private static final HttpServer stub = startStub();

    private static volatile byte[] csvBody = readFixture();
    private static volatile int csvStatus = 200;

    @DynamicPropertySource
    static void catalogueCsvUrl(DynamicPropertyRegistry registry) {
        registry.add("hereader.catalogue.gutenberg-catalog-csv-url",
                () -> "http://localhost:" + stub.getAddress().getPort()
                        + "/pg_catalog.csv");
    }

    @Autowired private WebApplicationContext context;
    @Autowired private CatalogueIngestionService ingestion;
    @Autowired private JdbcClient jdbc;
    @Autowired private ObjectMapper json;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .apply(springSecurity())
                .build();

        csvBody = readFixture();
        csvStatus = 200;
        jdbc.sql("delete from catalogue_entries").update();
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
                exchange.sendResponseHeaders(csvStatus, body.length);
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

    private static byte[] readFixture() {
        try (InputStream in = CatalogueControllerIntegrationTest.class
                .getResourceAsStream("/catalogue/pg_catalog_sample.csv")) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    // -- readiness ---------------------------------------------------------

    @Test
    void searchBeforeAnyIngestionIsDistinguishableFromNoMatches() throws Exception {
        mvc.perform(get("/catalogue/search?q=Alice"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.catalogueReady").value(false))
                .andExpect(jsonPath("$.results", hasSize(0)));
    }

    @Test
    void afterARefreshTheCatalogueIsReady() throws Exception {
        ingestion.refresh();

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.catalogueReady").value(true));
    }

    // -- ingestion filters record types ------------------------------------

    @Test
    void onlyTextRecordsAreKept() throws Exception {
        ingestion.refresh();

        // 13 fixture rows, 3 of them Sound/Image/Dataset.
        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(10)));
    }

    // -- authentication ------------------------------------------------

    @Test
    void noAccountIsNeeded() throws Exception {
        mvc.perform(get("/catalogue/search")).andExpect(status().isOk());
    }

    // -- search --------------------------------------------------------

    @Test
    void searchMatchesTitle() throws Exception {
        ingestion.refresh();

        mvc.perform(get("/catalogue/search?q=Alice"))
                .andExpect(jsonPath("$.results", hasSize(1)))
                .andExpect(jsonPath("$.results[0].gutenbergId").value(11));
    }

    @Test
    void searchMatchesAuthorCaseInsensitively() throws Exception {
        ingestion.refresh();

        // Both Alice's Adventures in Wonderland and Through the Looking-Glass.
        mvc.perform(get("/catalogue/search?q=carroll"))
                .andExpect(jsonPath("$.results", hasSize(2)));
    }

    @Test
    void aQueryWithNoMatchReturnsAnEmptyResultOnAReadyCatalogue() throws Exception {
        ingestion.refresh();

        mvc.perform(get("/catalogue/search?q=nonexistentbookzzz"))
                .andExpect(jsonPath("$.catalogueReady").value(true))
                .andExpect(jsonPath("$.results", hasSize(0)));
    }

    @Test
    void aLiteralPercentInAQueryIsNotTreatedAsAWildcard() throws Exception {
        ingestion.refresh();

        // No fixture title or author literally contains "%". An escaped
        // ILIKE pattern therefore matches nothing; an unescaped one turns
        // the query itself into a bare wildcard and matches every row.
        mvc.perform(get("/catalogue/search").param("q", "%"))
                .andExpect(jsonPath("$.results", hasSize(0)));
    }

    // -- paging ----------------------------------------------------------

    @Test
    void resultsArePagedAndHasMoreReflectsWhatIsLeft() throws Exception {
        ingestion.refresh();

        mvc.perform(get("/catalogue/search?size=4&page=0"))
                .andExpect(jsonPath("$.results", hasSize(4)))
                .andExpect(jsonPath("$.hasMore").value(true));

        // 10 Text entries total: pages of 4 leave 2 on the third page.
        mvc.perform(get("/catalogue/search?size=4&page=2"))
                .andExpect(jsonPath("$.results", hasSize(2)))
                .andExpect(jsonPath("$.hasMore").value(false));
    }

    // -- category filter ---------------------------------------------------

    @Test
    void resultsCanBeFilteredByCategory() throws Exception {
        ingestion.refresh();

        // Novels: Alice (11), Looking-Glass (12), Moby-Dick (15),
        // From the Earth to the Moon (83), Frankenstein (84).
        mvc.perform(get("/catalogue/search").param("category", "Novels"))
                .andExpect(jsonPath("$.results", hasSize(5)));
    }

    @Test
    void categoryFilterCombinesWithSearchText() throws Exception {
        ingestion.refresh();

        // Both Carroll books carry Novels; only these two also match "carroll".
        mvc.perform(get("/catalogue/search")
                        .param("q", "carroll")
                        .param("category", "Novels"))
                .andExpect(jsonPath("$.results", hasSize(2)));
    }

    @Test
    void anUnknownCategoryYieldsACleanEmptyResult() throws Exception {
        ingestion.refresh();

        mvc.perform(get("/catalogue/search").param("category", "Nonexistent Shelf"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.catalogueReady").value(true))
                .andExpect(jsonPath("$.results", hasSize(0)));
    }

    // -- language filter -----------------------------------------------------

    @Test
    void noLanguageFilterAppliedByDefaultReturnsEveryLanguage() throws Exception {
        ingestion.refresh();

        // Ten Text entries: nine en, one fr (79438) — none excluded absent
        // an explicit language filter.
        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(10)));
    }

    @Test
    void resultsCanBeFilteredByLanguage() throws Exception {
        ingestion.refresh();

        mvc.perform(get("/catalogue/search").param("language", "fr"))
                .andExpect(jsonPath("$.results", hasSize(1)))
                .andExpect(jsonPath("$.results[0].gutenbergId").value(79438));
    }

    @Test
    void anUnknownLanguageYieldsACleanEmptyResult() throws Exception {
        ingestion.refresh();

        mvc.perform(get("/catalogue/search").param("language", "xx"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.catalogueReady").value(true))
                .andExpect(jsonPath("$.results", hasSize(0)));
    }

    @Test
    void categoryAndLanguageFiltersCombine() throws Exception {
        ingestion.refresh();

        // British Literature: Alice (11, en), Looking-Glass (12, en),
        // Frankenstein (84, en) — all en, so an fr filter leaves none.
        mvc.perform(get("/catalogue/search")
                        .param("category", "British Literature")
                        .param("language", "fr"))
                .andExpect(jsonPath("$.results", hasSize(0)));

        mvc.perform(get("/catalogue/search")
                        .param("category", "British Literature")
                        .param("language", "en"))
                .andExpect(jsonPath("$.results", hasSize(3)));
    }

    // -- additional sort orders ---------------------------------------------

    @Test
    void resultsCanBeSortedByAuthor() throws Exception {
        ingestion.refresh();

        // The Mayflower Compact (id 7) carries a blank Authors field, which
        // sorts first ascending.
        mvc.perform(get("/catalogue/search?sort=author"))
                .andExpect(jsonPath("$.results[0].gutenbergId").value(7));
    }

    @Test
    void resultsCanBeSortedByIssueDate() throws Exception {
        ingestion.refresh();

        // The Declaration of Independence (id 1, issued 1971-12-01) is the
        // oldest Issued date in the fixture.
        mvc.perform(get("/catalogue/search?sort=issued"))
                .andExpect(jsonPath("$.results[0].gutenbergId").value(1));
    }

    @Test
    void sortMustBeARecognizedValue() throws Exception {
        ingestion.refresh();

        mvc.perform(get("/catalogue/search?sort=nonsense"))
                .andExpect(status().isBadRequest());
    }

    // -- paging stays consistent under a filter and sort combination --------

    @Test
    void pagingThroughAFilteredAndSortedResultNeverRepeatsOrSkips() throws Exception {
        ingestion.refresh();

        var seen = new HashSet<Integer>();
        var page = 0;
        while (true) {
            var body = mvc.perform(get("/catalogue/search")
                            .param("category", "Novels")
                            .param("sort", "author")
                            .param("size", "2")
                            .param("page", String.valueOf(page)))
                    .andReturn().getResponse().getContentAsString();
            var response = json.readValue(body, CatalogueDtos.SearchResponse.class);

            for (var entry : response.results()) {
                assertThat(seen.add(entry.gutenbergId()))
                        .as("gutenbergId %d repeated on page %d", entry.gutenbergId(), page)
                        .isTrue();
            }
            if (!response.hasMore()) {
                break;
            }
            page++;
        }

        // Novels: 11, 12, 15, 83, 84.
        assertThat(seen).containsExactlyInAnyOrder(11, 12, 15, 83, 84);
    }

    // -- category counts endpoint --------------------------------------------

    @Test
    void categoriesListsEveryCategoryWithItsEntryCount() throws Exception {
        ingestion.refresh();

        mvc.perform(get("/catalogue/categories"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.category=='Novels')].count").value(5));
    }

    @Test
    void categoriesIsUnaffectedByAnEntryCarryingNoCategory() throws Exception {
        ingestion.refresh();

        // The brat (79435) and Les morts qui parlent (79438) carry no
        // Bookshelves at all, so they contribute no category rows.
        mvc.perform(get("/catalogue/categories"))
                .andExpect(jsonPath("$[?(@.category=='Novels')].count").value(5))
                .andExpect(jsonPath("$[?(@.category=='French Literature')].count").value(1));
    }

    // -- language counts endpoint --------------------------------------------

    @Test
    void languagesListsEveryLanguageWithItsEntryCount() throws Exception {
        ingestion.refresh();

        // Ten Text entries: nine en, one fr (79438).
        mvc.perform(get("/catalogue/languages"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.language=='en')].count").value(9))
                .andExpect(jsonPath("$[?(@.language=='fr')].count").value(1));
    }

    // -- refresh: upsert and delete ---------------------------------------

    @Test
    void aRecordThatVanishesUpstreamIsDeletedRatherThanKept() throws Exception {
        ingestion.refresh();
        mvc.perform(get("/catalogue/search?q=Alice"))
                .andExpect(jsonPath("$.results", hasSize(1)));

        // Alice's Adventures in Wonderland (id 11) is absent from the next
        // export, standing in for a book Gutenberg has withdrawn.
        csvBody = withoutRow(readFixture(), "11,Text,");
        ingestion.refresh();

        mvc.perform(get("/catalogue/search?q=Alice"))
                .andExpect(jsonPath("$.results", hasSize(0)));
        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(9)));
    }

    @Test
    void aRecordThatVanishesUpstreamAlsoDropsFromItsCategoryCounts() throws Exception {
        ingestion.refresh();
        mvc.perform(get("/catalogue/categories"))
                .andExpect(jsonPath("$[?(@.category=='British Literature')].count").value(3));

        // Alice's Adventures in Wonderland (id 11) carries British Literature
        // — its category rows must go with it, via the FK's cascade delete.
        csvBody = withoutRow(readFixture(), "11,Text,");
        ingestion.refresh();

        mvc.perform(get("/catalogue/categories"))
                .andExpect(jsonPath("$[?(@.category=='British Literature')].count").value(2));
    }

    @Test
    void aRecordThatVanishesUpstreamAlsoDropsFromItsLanguageCounts() throws Exception {
        ingestion.refresh();
        mvc.perform(get("/catalogue/languages"))
                .andExpect(jsonPath("$[?(@.language=='fr')].count").value(1));

        // Les morts qui parlent (79438) is the fixture's only fr entry.
        csvBody = withoutRow(readFixture(), "79438,Text,");
        ingestion.refresh();

        mvc.perform(get("/catalogue/languages"))
                .andExpect(jsonPath("$[?(@.language=='fr')]").isEmpty());
    }

    @Test
    void aRepeatedRefreshWithTheSameExportChangesNothing() throws Exception {
        ingestion.refresh();
        ingestion.refresh();

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(10)));
    }

    // -- malformed and truncated input ------------------------------------

    @Test
    void aRefreshThatEndsInsideAQuotedFieldAbortsAndLeavesTheOldCatalogueIntact()
            throws Exception {

        ingestion.refresh();
        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(10)));

        // Cut partway through id 15's quoted Subjects field, as a dropped
        // connection mid-download would.
        var text = new String(readFixture(), StandardCharsets.UTF_8);
        var cutAt = text.indexOf("\"Whaling");
        csvBody = text.substring(0, cutAt).getBytes(StandardCharsets.UTF_8);

        assertThatThrownBy(ingestion::refresh)
                .isInstanceOf(CatalogueIngestionException.class);

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(10)));
    }

    @Test
    void aRowWithFewerColumnsThanTheHeaderAbortsTheRefresh() {
        var text = new String(readFixture(), StandardCharsets.UTF_8);
        // Truncates id 50's row after its second column — no trailing
        // newline, so the reader reaches end of file mid-row rather than
        // mid-field, which is the other shape a truncated download takes.
        var cutAt = text.indexOf("50,Dataset,") + "50,Dataset,".length();
        csvBody = text.substring(0, cutAt).getBytes(StandardCharsets.UTF_8);

        assertThatThrownBy(ingestion::refresh)
                .isInstanceOf(CatalogueIngestionException.class);
    }

    @Test
    void aNonTwoHundredResponseAbortsTheRefresh() {
        csvStatus = 503;

        assertThatThrownBy(ingestion::refresh)
                .isInstanceOf(CatalogueIngestionException.class);
    }

    // -- helpers ---------------------------------------------------------

    /// Removes the one-line row starting with [rowPrefix]. None of the ids
    /// used this way in this file (11, 50) are the multi-line title (id 2),
    /// so a start-of-line anchor is enough.
    private static byte[] withoutRow(byte[] csv, String rowPrefix) {
        var text = new String(csv, StandardCharsets.UTF_8);
        var lines = text.split("\n", -1);
        var kept = new StringBuilder();
        for (var line : lines) {
            if (line.startsWith(rowPrefix)) {
                continue;
            }
            kept.append(line).append('\n');
        }
        // The split/join above adds one trailing newline too many.
        kept.setLength(Math.max(0, kept.length() - 1));
        return kept.toString().getBytes(StandardCharsets.UTF_8);
    }
}
