package lt.hereader.server.catalogue;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import tools.jackson.databind.ObjectMapper;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.hamcrest.Matchers.hasSize;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/// End to end through the real filter chain and a real Postgres, against a
/// local HTTP stub standing in for Gutenberg's export (upstream locations
/// are a configuration property — see CatalogueStubServerTest).
///
/// `pg_catalog_sample.csv` is thirteen real rows; see
/// `src/test/resources/catalogue/README.md` for provenance and which
/// format edge case each row exercises. The "a book vanished upstream" and
/// "the export was truncated mid-download" scenarios below slice that same
/// text in memory rather than committing separate fixtures for states that
/// are not really a second upstream snapshot.
///
/// The tests are in two groups (#232). The ones directly below either need a
/// catalogue in a state they build themselves — empty, ingested twice,
/// ingested from a damaged export — or write to it, so each pays for its own
/// ingestion. Everything in `OverAnIngestedCatalogue` only reads, so that
/// group ingests once for all of it.
@SpringBootTest
@ActiveProfiles("test")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class CatalogueControllerIntegrationTest extends CatalogueStubServerTest {

    @Autowired private WebApplicationContext context;
    @Autowired private CatalogueIngestionService ingestion;
    @Autowired private JdbcClient jdbc;
    @Autowired private ObjectMapper json;

    private MockMvc mvc;

    /// MockMvc is built from the shared application context and holds no
    /// per-test state, so one instance serves the whole class.
    @BeforeAll
    void buildMockMvc() {
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .apply(springSecurity())
                .build();
    }

    /// The stub's response state is static and shared with the other
    /// catalogue classes, so it is restored before every test — including the
    /// tests below that leave it holding a damaged export or a 503.
    @BeforeEach
    void resetStub() {
        csvBody = csvFixture;
        csvStatus = 200;
    }

    private void emptyCatalogue() {
        jdbc.sql("delete from catalogue_entries").update();
    }

    /// Truncate, then ingest the fixture export from scratch — what the
    /// per-test setup used to do for all thirty-seven tests. It resets the
    /// stub first so it does not matter which test ran before.
    private void ingestFromEmpty() {
        resetStub();
        emptyCatalogue();
        ingestion.refresh();
    }

    /// A checksum over the whole row text of both catalogue tables, so any
    /// insert, update or delete changes it — a re-ingestion included, since
    /// that rewrites every row's `ingestion_run` and `updated_at`.
    private String catalogueFingerprint() {
        return jdbc.sql("""
                        select md5(
                            coalesce((select string_agg(e::text, '|' order by e.gutenberg_id)
                                      from catalogue_entries e), '')
                            || coalesce((select string_agg(c::text, '|' order by c.gutenberg_id, c.category)
                                         from catalogue_entry_categories c), ''))
                        """)
                .query(String.class)
                .single();
    }

    // -- readiness ---------------------------------------------------------

    @Test
    void searchBeforeAnyIngestionIsDistinguishableFromNoMatches() throws Exception {
        emptyCatalogue();

        mvc.perform(get("/catalogue/search?q=Alice"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.catalogueReady").value(false))
                .andExpect(jsonPath("$.results", hasSize(0)));
    }

    @Test
    void afterARefreshTheCatalogueIsReady() throws Exception {
        // Ingesting from empty is the point: "ready" has to be the refresh's
        // doing, not a catalogue an earlier test left behind.
        ingestFromEmpty();

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.catalogueReady").value(true));
    }

    // -- authentication ------------------------------------------------

    @Test
    void noAccountIsNeeded() throws Exception {
        mvc.perform(get("/catalogue/search")).andExpect(status().isOk());
    }

    // -- direction toggle over a value that can be absent --------------------

    @Test
    void popularityNullsSortLastRegardlessOfDirection() throws Exception {
        ingestFromEmpty();

        // Every entry starts with downloads null (no popularity refresh has
        // run); give two of them a real count so the rest stay "no value"
        // rather than "zero" — the distinction CatalogueDtos.Sort documents.
        jdbc.sql("update catalogue_entries set downloads = 5 where gutenberg_id = 12").update();
        jdbc.sql("update catalogue_entries set downloads = 100 where gutenberg_id = 11").update();

        var ascending = idsOf(mvc.perform(get("/catalogue/search?sort=popularity&direction=ascending")));
        var descending = idsOf(mvc.perform(get("/catalogue/search?sort=popularity&direction=descending")));

        assertThat(ascending.subList(0, 2)).containsExactly(12, 11);
        assertThat(descending.subList(0, 2)).containsExactly(11, 12);
        // The other eight, all still null, fill out both directions' tails.
        assertThat(ascending.subList(2, ascending.size()))
                .isEqualTo(descending.subList(2, descending.size()));
    }

    @Test
    void issuedNullsSortLastRegardlessOfDirection() throws Exception {
        ingestFromEmpty();

        // Every fixture row carries an Issued date; null one out so "no
        // value" is exercised rather than only "the oldest/newest date".
        jdbc.sql("update catalogue_entries set issued = null where gutenberg_id = 1").update();

        var ascending = idsOf(mvc.perform(get("/catalogue/search?sort=issued&direction=ascending")));
        var descending = idsOf(mvc.perform(get("/catalogue/search?sort=issued&direction=descending")));

        assertThat(ascending.get(ascending.size() - 1)).isEqualTo(1);
        assertThat(descending.get(descending.size() - 1)).isEqualTo(1);
    }

    // -- refresh: upsert and delete ---------------------------------------

    @Test
    void aRecordThatVanishesUpstreamIsDeletedRatherThanKept() throws Exception {
        ingestFromEmpty();
        mvc.perform(get("/catalogue/search?q=Alice"))
                .andExpect(jsonPath("$.results", hasSize(1)));

        // Alice's Adventures in Wonderland (id 11) is absent from the next
        // export, standing in for a book Gutenberg has withdrawn.
        csvBody = withoutRow(csvFixture, "11,Text,");
        ingestion.refresh();

        mvc.perform(get("/catalogue/search?q=Alice"))
                .andExpect(jsonPath("$.results", hasSize(0)));
        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(9)));
    }

    @Test
    void aRecordThatVanishesUpstreamAlsoDropsFromItsCategoryCounts() throws Exception {
        ingestFromEmpty();
        mvc.perform(get("/catalogue/categories"))
                .andExpect(jsonPath("$[?(@.category=='British Literature')].count").value(3));

        // Alice's Adventures in Wonderland (id 11) carries British Literature
        // — its category rows must go with it, via the FK's cascade delete.
        csvBody = withoutRow(csvFixture, "11,Text,");
        ingestion.refresh();

        mvc.perform(get("/catalogue/categories"))
                .andExpect(jsonPath("$[?(@.category=='British Literature')].count").value(2));
    }

    @Test
    void aRecordThatVanishesUpstreamAlsoDropsFromItsLanguageCounts() throws Exception {
        ingestFromEmpty();
        mvc.perform(get("/catalogue/languages"))
                .andExpect(jsonPath("$[?(@.language=='fr')].count").value(1));

        // Les morts qui parlent (79438) is the fixture's only fr entry.
        csvBody = withoutRow(csvFixture, "79438,Text,");
        ingestion.refresh();

        mvc.perform(get("/catalogue/languages"))
                .andExpect(jsonPath("$[?(@.language=='fr')]").isEmpty());
    }

    @Test
    void aRepeatedRefreshWithTheSameExportChangesNothing() throws Exception {
        ingestFromEmpty();
        ingestion.refresh();

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(10)));
    }

    // -- malformed and truncated input ------------------------------------

    @Test
    void aRefreshThatEndsInsideAQuotedFieldAbortsAndLeavesTheOldCatalogueIntact()
            throws Exception {

        ingestFromEmpty();
        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(10)));

        // Cut partway through id 15's quoted Subjects field, as a dropped
        // connection mid-download would.
        var text = new String(csvFixture, StandardCharsets.UTF_8);
        var cutAt = text.indexOf("\"Whaling");
        csvBody = text.substring(0, cutAt).getBytes(StandardCharsets.UTF_8);

        assertThatThrownBy(ingestion::refresh)
                .isInstanceOf(CatalogueIngestionException.class);

        mvc.perform(get("/catalogue/search"))
                .andExpect(jsonPath("$.results", hasSize(10)));
    }

    @Test
    void aRowWithFewerColumnsThanTheHeaderAbortsTheRefresh() {
        var text = new String(csvFixture, StandardCharsets.UTF_8);
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

    /// Every test here queries one ingested copy of the fixture export and
    /// writes nothing, so the ingestion is the group's, not each test's — one
    /// fetch, parse and insert instead of twenty-five identical ones (#232).
    ///
    /// `assertNothingWasWritten` is what keeps that a checked precondition
    /// rather than a convention: a test added here that writes to the
    /// catalogue fails on its own name instead of silently changing what the
    /// tests after it read.
    @Nested
    @TestInstance(TestInstance.Lifecycle.PER_CLASS)
    class OverAnIngestedCatalogue {

        private String ingested;

        @BeforeAll
        void ingestOnce() {
            ingestFromEmpty();
            ingested = catalogueFingerprint();
        }

        @AfterEach
        void assertNothingWasWritten() {
            assertThat(catalogueFingerprint())
                    .as("this test wrote to the catalogue, so the tests after "
                            + "it no longer run against the ingested fixture")
                    .isEqualTo(ingested);
        }

        // -- ingestion filters record types --------------------------------

        @Test
        void onlyTextRecordsAreKept() throws Exception {
            // 13 fixture rows, 3 of them Sound/Image/Dataset.
            mvc.perform(get("/catalogue/search"))
                    .andExpect(jsonPath("$.results", hasSize(10)));
        }

        // -- search --------------------------------------------------------

        @Test
        void searchMatchesTitle() throws Exception {
            mvc.perform(get("/catalogue/search?q=Alice"))
                    .andExpect(jsonPath("$.results", hasSize(1)))
                    .andExpect(jsonPath("$.results[0].gutenbergId").value(11));
        }

        @Test
        void searchMatchesAuthorCaseInsensitively() throws Exception {
            // Both Alice's Adventures in Wonderland and Through the Looking-Glass.
            mvc.perform(get("/catalogue/search?q=carroll"))
                    .andExpect(jsonPath("$.results", hasSize(2)));
        }

        @Test
        void aQueryWithNoMatchReturnsAnEmptyResultOnAReadyCatalogue() throws Exception {
            mvc.perform(get("/catalogue/search?q=nonexistentbookzzz"))
                    .andExpect(jsonPath("$.catalogueReady").value(true))
                    .andExpect(jsonPath("$.results", hasSize(0)));
        }

        @Test
        void aLiteralPercentInAQueryIsNotTreatedAsAWildcard() throws Exception {
            // No fixture title or author literally contains "%". An escaped
            // ILIKE pattern therefore matches nothing; an unescaped one turns
            // the query itself into a bare wildcard and matches every row.
            mvc.perform(get("/catalogue/search").param("q", "%"))
                    .andExpect(jsonPath("$.results", hasSize(0)));
        }

        // -- paging ----------------------------------------------------------

        @Test
        void resultsArePagedAndHasMoreReflectsWhatIsLeft() throws Exception {
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
            // Novels: Alice (11), Looking-Glass (12), Moby-Dick (15),
            // From the Earth to the Moon (83), Frankenstein (84).
            mvc.perform(get("/catalogue/search").param("category", "Novels"))
                    .andExpect(jsonPath("$.results", hasSize(5)));
        }

        @Test
        void categoryFilterCombinesWithSearchText() throws Exception {
            // Both Carroll books carry Novels; only these two also match "carroll".
            mvc.perform(get("/catalogue/search")
                            .param("q", "carroll")
                            .param("category", "Novels"))
                    .andExpect(jsonPath("$.results", hasSize(2)));
        }

        @Test
        void anUnknownCategoryYieldsACleanEmptyResult() throws Exception {
            mvc.perform(get("/catalogue/search").param("category", "Nonexistent Shelf"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.catalogueReady").value(true))
                    .andExpect(jsonPath("$.results", hasSize(0)));
        }

        // -- language filter -----------------------------------------------------

        @Test
        void noLanguageFilterAppliedByDefaultReturnsEveryLanguage() throws Exception {
            // Ten Text entries: nine en, one fr (79438) — none excluded absent
            // an explicit language filter.
            mvc.perform(get("/catalogue/search"))
                    .andExpect(jsonPath("$.results", hasSize(10)));
        }

        @Test
        void resultsCanBeFilteredByLanguage() throws Exception {
            mvc.perform(get("/catalogue/search").param("language", "fr"))
                    .andExpect(jsonPath("$.results", hasSize(1)))
                    .andExpect(jsonPath("$.results[0].gutenbergId").value(79438));
        }

        @Test
        void anUnknownLanguageYieldsACleanEmptyResult() throws Exception {
            mvc.perform(get("/catalogue/search").param("language", "xx"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.catalogueReady").value(true))
                    .andExpect(jsonPath("$.results", hasSize(0)));
        }

        @Test
        void categoryAndLanguageFiltersCombine() throws Exception {
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
            // The Mayflower Compact (id 7) carries a blank Authors field, which
            // sorts first ascending.
            mvc.perform(get("/catalogue/search?sort=author"))
                    .andExpect(jsonPath("$.results[0].gutenbergId").value(7));
        }

        @Test
        void resultsCanBeSortedByIssueDate() throws Exception {
            // The Declaration of Independence (id 1, issued 1971-12-01) is the
            // oldest Issued date in the fixture.
            mvc.perform(get("/catalogue/search?sort=issued"))
                    .andExpect(jsonPath("$.results[0].gutenbergId").value(1));
        }

        @Test
        void sortMustBeARecognizedValue() throws Exception {
            mvc.perform(get("/catalogue/search?sort=nonsense"))
                    .andExpect(status().isBadRequest());
        }

        // -- direction toggle -----------------------------------------------------

        @Test
        void directionReversesTitleOrder() throws Exception {
            var ascending = idsOf(mvc.perform(get("/catalogue/search?sort=title&direction=ascending")));
            var descending = idsOf(mvc.perform(get("/catalogue/search?sort=title&direction=descending")));

            assertThat(descending).isEqualTo(reversed(ascending));
        }

        @Test
        void directionReversesAuthorOrder() throws Exception {
            // The Mayflower Compact (id 7) carries a blank Authors field: first
            // ascending (resultsCanBeSortedByAuthor above), so last descending.
            // The fixture's only untied Authors value, unlike "Carroll, Lewis"
            // (ids 11, 12) — checking a tied value here would really be
            // checking the tiebreak (title), which direction leaves unchanged.
            var descending = idsOf(mvc.perform(get("/catalogue/search?sort=author&direction=descending")));

            assertThat(descending.get(descending.size() - 1)).isEqualTo(7);
        }

        @Test
        void directionReversesIssuedOrder() throws Exception {
            // The Declaration of Independence (id 1, issued 1971-12-01) is the
            // fixture's unique oldest date: first ascending
            // (resultsCanBeSortedByIssueDate above), so last descending.
            var descending = idsOf(mvc.perform(get("/catalogue/search?sort=issued&direction=descending")));

            assertThat(descending.get(descending.size() - 1)).isEqualTo(1);
        }

        @Test
        void omittingDirectionKeepsTodaysDefaultForEverySort() throws Exception {
            // POPULARITY's own default is descending (most downloaded first);
            // every other field's is ascending — CatalogueService.search.
            assertThat(idsOf(mvc.perform(get("/catalogue/search?sort=popularity"))))
                    .isEqualTo(idsOf(mvc.perform(get("/catalogue/search?sort=popularity&direction=descending"))));
            assertThat(idsOf(mvc.perform(get("/catalogue/search?sort=title"))))
                    .isEqualTo(idsOf(mvc.perform(get("/catalogue/search?sort=title&direction=ascending"))));
            assertThat(idsOf(mvc.perform(get("/catalogue/search?sort=author"))))
                    .isEqualTo(idsOf(mvc.perform(get("/catalogue/search?sort=author&direction=ascending"))));
            assertThat(idsOf(mvc.perform(get("/catalogue/search?sort=issued"))))
                    .isEqualTo(idsOf(mvc.perform(get("/catalogue/search?sort=issued&direction=ascending"))));
        }

        @Test
        void directionMustBeARecognizedValue() throws Exception {
            mvc.perform(get("/catalogue/search?direction=sideways"))
                    .andExpect(status().isBadRequest());
        }

        // -- paging stays consistent under a filter and sort combination --------

        @Test
        void pagingThroughAFilteredAndSortedResultNeverRepeatsOrSkips() throws Exception {
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
            mvc.perform(get("/catalogue/categories"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[?(@.category=='Novels')].count").value(5));
        }

        @Test
        void categoriesIsUnaffectedByAnEntryCarryingNoCategory() throws Exception {
            // The brat (79435) and Les morts qui parlent (79438) carry no
            // Bookshelves at all, so they contribute no category rows.
            mvc.perform(get("/catalogue/categories"))
                    .andExpect(jsonPath("$[?(@.category=='Novels')].count").value(5))
                    .andExpect(jsonPath("$[?(@.category=='French Literature')].count").value(1));
        }

        // -- language counts endpoint --------------------------------------------

        @Test
        void languagesListsEveryLanguageWithItsEntryCount() throws Exception {
            // Ten Text entries: nine en, one fr (79438).
            mvc.perform(get("/catalogue/languages"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$[?(@.language=='en')].count").value(9))
                    .andExpect(jsonPath("$[?(@.language=='fr')].count").value(1));
        }
    }

    // -- helpers ---------------------------------------------------------

    /// gutenbergId of every result, in response order — the direction tests
    /// compare this rather than individual jsonPath assertions, since the
    /// property under test is the whole ordering, not one row of it.
    private List<Integer> idsOf(ResultActions result) throws Exception {
        var body = result.andReturn().getResponse().getContentAsString();
        var response = json.readValue(body, CatalogueDtos.SearchResponse.class);
        return response.results().stream().map(CatalogueDtos.Entry::gutenbergId).toList();
    }

    private static <T> List<T> reversed(List<T> list) {
        var copy = new ArrayList<>(list);
        Collections.reverse(copy);
        return copy;
    }

    /// Removes the one-line row starting with [rowPrefix]. None of the ids
    /// used this way in this file (11, 79438) are the multi-line title
    /// (id 2), so a start-of-line anchor is enough.
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
