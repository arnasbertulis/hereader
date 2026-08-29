package lt.hereader.server.catalogue;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class CatalogueQueryTest {

    @Test
    void blankQueryDefaultsToPopularity() {
        var query = CatalogueQuery.of("", "", "", 0, null, null, null);

        assertThat(query.sort()).isEqualTo(CatalogueDtos.Sort.POPULARITY);
    }

    @Test
    void nonBlankQueryDefaultsToTitle() {
        var query = CatalogueQuery.of("dracula", "", "", 0, null, null, null);

        assertThat(query.sort()).isEqualTo(CatalogueDtos.Sort.TITLE);
    }

    @Test
    void popularityDefaultsToDescending() {
        var query = CatalogueQuery.of("", "", "", 0, null, CatalogueDtos.Sort.POPULARITY, null);

        assertThat(query.direction()).isEqualTo(CatalogueDtos.Direction.DESCENDING);
    }

    @Test
    void everyOtherSortDefaultsToAscending() {
        var query = CatalogueQuery.of("", "", "", 0, null, CatalogueDtos.Sort.ISSUED, null);

        assertThat(query.direction()).isEqualTo(CatalogueDtos.Direction.ASCENDING);
    }

    @Test
    void directionDefaultsFromTheResolvedSortNotTheRequestedOne() {
        // No explicit sort, so a blank query resolves to POPULARITY — the
        // direction default has to follow that resolved sort, not TITLE's.
        var query = CatalogueQuery.of("", "", "", 0, null, null, null);

        assertThat(query.direction()).isEqualTo(CatalogueDtos.Direction.DESCENDING);
    }

    @Test
    void explicitDirectionIsNeverOverridden() {
        var query = CatalogueQuery.of(
                "", "", "", 0, null, CatalogueDtos.Sort.POPULARITY, CatalogueDtos.Direction.ASCENDING);

        assertThat(query.direction()).isEqualTo(CatalogueDtos.Direction.ASCENDING);
    }

    @Test
    void sizeClampsAtTheLowerBound() {
        var query = CatalogueQuery.of("", "", "", 0, 0, null, null);

        assertThat(query.size()).isEqualTo(1);
    }

    @Test
    void sizeClampsAtTheUpperBound() {
        var query = CatalogueQuery.of("", "", "", 0, 500, null, null);

        assertThat(query.size()).isEqualTo(50);
    }

    @Test
    void absentSizeDefaultsToTwenty() {
        var query = CatalogueQuery.of("", "", "", 0, null, null, null);

        assertThat(query.size()).isEqualTo(20);
    }

    @Test
    void queryCategoryAndLanguageAreTrimmed() {
        var query = CatalogueQuery.of("  dracula  ", "  fiction  ", "  en  ", 0, null, null, null);

        assertThat(query.query()).isEqualTo("dracula");
        assertThat(query.category()).isEqualTo("fiction");
        assertThat(query.language()).isEqualTo("en");
    }

    @Test
    void nullQueryCategoryAndLanguageBecomeBlank() {
        var query = CatalogueQuery.of(null, null, null, 0, null, null, null);

        assertThat(query.query()).isEmpty();
        assertThat(query.category()).isEmpty();
        assertThat(query.language()).isEmpty();
    }

    @Test
    void pageIsCarriedThroughUnchanged() {
        var query = CatalogueQuery.of("", "", "", 3, null, null, null);

        assertThat(query.page()).isEqualTo(3);
    }
}
