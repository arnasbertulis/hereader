package lt.hereader.server.catalogue;

import java.time.LocalDate;
import java.util.List;

/// Wire shapes for the Catalogue's read side.
public final class CatalogueDtos {

    private CatalogueDtos() {}

    /// One listing as returned to a caller. Never the row's ingestion_run —
    /// that column exists purely to let a refresh find what it wrote.
    public record Entry(
            int gutenbergId,
            String title,
            String authors,
            String language,
            String subjects,
            LocalDate issued) {}

    /// TITLE and AUTHOR are alphabetical; ISSUED is oldest first; POPULARITY
    /// orders by download count, most downloaded first. Under POPULARITY an
    /// Entry carrying no count sorts last, and under ISSUED an Entry with no
    /// date sorts last too (CatalogueRepository.search), rather than either
    /// dropping out of the page.
    public enum Sort { TITLE, AUTHOR, ISSUED, POPULARITY }

    /// [catalogueReady] is false only when no Ingestion has ever completed —
    /// see CatalogueRepository.hasAnyEntries. A caller uses it to tell "the
    /// Catalogue is not available yet" apart from "nothing matched".
    public record SearchResponse(
            boolean catalogueReady,
            List<Entry> results,
            int page,
            boolean hasMore) {}

    /// One row of the Category browse list — see CatalogueRepository
    /// .categoryCounts. [count] is how many Catalogue Entries carry
    /// [category], so a reader can judge whether it's worth opening before
    /// they do.
    public record CategoryCount(String category, long count) {}
}
