package lt.hereader.server.catalogue;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.io.InputStreamReader;
import java.io.UncheckedIOException;
import java.net.URI;
import java.io.InputStream;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

/// Refreshes the Catalogue from Gutenberg's bulk catalogue CSV (ADR 0029).
///
/// Fetching and parsing happen entirely before any database write: the whole
/// export is small enough (roughly 21MB, ~78,000 Text records once the other
/// three record types are dropped) to hold as parsed rows in memory, and
/// doing so keeps the one write transaction short rather than held open for
/// as long as the network fetch takes. Anything wrong with the export —
/// unreachable, a non-200 status, a wrong column count, an unterminated
/// quote — throws before write() is ever called, which is what leaves the
/// existing Catalogue untouched on a bad refresh.
@Service
public class CatalogueIngestionService {

    /// Text#,Type,Issued,Title,Language,Authors,Subjects,LoCC,Bookshelves
    private static final int TYPE_COLUMN = 1;
    private static final int ISSUED_COLUMN = 2;
    private static final int TITLE_COLUMN = 3;
    private static final int LANGUAGE_COLUMN = 4;
    private static final int AUTHORS_COLUMN = 5;
    private static final int SUBJECTS_COLUMN = 6;
    private static final int BOOKSHELVES_COLUMN = 8;

    /// The Bookshelves column mixes curated Categories with looser,
    /// uncurated shelf names in one `; `-separated list — only the tokens
    /// carrying this prefix are the 72 curated shelves the browse screen
    /// filters by (CONTEXT.md's "Category" entry); the rest is discarded.
    private static final String CATEGORY_PREFIX = "Category: ";

    private record ParsedEntry(
            int gutenbergId, String title, String authors, String language,
            String subjects, LocalDate issued, List<String> categories) {}

    private final CatalogueRepository repository;
    private final HttpClient http;
    private final URI catalogueCsvUri;

    CatalogueIngestionService(
            CatalogueRepository repository,
            @Value("${hereader.catalogue.gutenberg-catalog-csv-url:"
                    + "https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv}")
            String catalogueCsvUrl) {

        this.repository = repository;
        this.catalogueCsvUri = URI.create(catalogueCsvUrl);
        this.http = HttpClient.newHttpClient();
    }

    /// Fetches, parses and replaces the Catalogue. Throws
    /// CatalogueIngestionException on anything that should abort the
    /// refresh; the caller (CatalogueIngestionScheduler,
    /// CatalogueIngestionRunner) decides what to do with that.
    public void refresh() {
        write(fetchAndParse());
    }

    private List<ParsedEntry> fetchAndParse() {
        HttpResponse<InputStream> response;
        try {
            response = http.send(
                    HttpRequest.newBuilder(catalogueCsvUri).GET().build(),
                    HttpResponse.BodyHandlers.ofInputStream());
        } catch (IOException e) {
            throw new CatalogueIngestionException(
                    "Could not reach the Gutenberg catalogue export.", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new CatalogueIngestionException(
                    "Interrupted while fetching the Gutenberg catalogue export.", e);
        }

        if (response.statusCode() != 200) {
            throw new CatalogueIngestionException(
                    "Gutenberg catalogue export returned HTTP "
                            + response.statusCode() + ".");
        }

        var entries = new ArrayList<ParsedEntry>();
        try (var csv = new GutenbergCsvReader(
                new InputStreamReader(response.body(), StandardCharsets.UTF_8))) {

            if (!csv.hasNext()) {
                throw new CatalogueIngestionException(
                        "Catalogue export has no header row.");
            }
            var columns = csv.next().size();

            while (csv.hasNext()) {
                var row = csv.next();
                if (row.size() != columns) {
                    throw new CatalogueIngestionException(
                            "Catalogue export row has " + row.size()
                                    + " columns, expected " + columns + ".");
                }
                // Audio, image and dataset records: none of them produce
                // something the app's EPUB parser can open.
                if (!"Text".equals(row.get(TYPE_COLUMN))) {
                    continue;
                }
                entries.add(toEntry(row));
            }
        } catch (UncheckedIOException | IllegalStateException e) {
            throw new CatalogueIngestionException(
                    "Catalogue export ended unexpectedly.", e);
        } catch (IOException e) {
            throw new CatalogueIngestionException(
                    "Could not close the catalogue export stream.", e);
        }
        return entries;
    }

    @Transactional
    void write(List<ParsedEntry> entries) {
        var run = UUID.randomUUID();
        for (var entry : entries) {
            repository.upsert(
                    entry.gutenbergId(), entry.title(), entry.authors(),
                    entry.language(), entry.subjects(), entry.issued(), run);
            repository.replaceCategories(entry.gutenbergId(), entry.categories());
        }
        repository.deleteNotWrittenBy(run);
    }

    private static ParsedEntry toEntry(List<String> row) {
        final int id;
        try {
            id = Integer.parseInt(row.get(0).trim());
        } catch (NumberFormatException e) {
            throw new CatalogueIngestionException(
                    "Catalogue export row has a non-numeric Text#: '"
                            + row.get(0) + "'.", e);
        }

        final LocalDate issued;
        try {
            issued = LocalDate.parse(row.get(ISSUED_COLUMN).trim());
        } catch (DateTimeParseException e) {
            throw new CatalogueIngestionException(
                    "Catalogue export row " + id
                            + " has an unparseable issue date: '"
                            + row.get(ISSUED_COLUMN) + "'.", e);
        }

        return new ParsedEntry(
                id,
                row.get(TITLE_COLUMN),
                row.get(AUTHORS_COLUMN),
                row.get(LANGUAGE_COLUMN),
                row.get(SUBJECTS_COLUMN),
                issued,
                parseCategories(row.get(BOOKSHELVES_COLUMN)));
    }

    private static List<String> parseCategories(String bookshelves) {
        if (bookshelves == null || bookshelves.isBlank()) {
            return List.of();
        }
        return Arrays.stream(bookshelves.split("; "))
                .map(String::trim)
                .filter(shelf -> shelf.startsWith(CATEGORY_PREFIX))
                .map(shelf -> shelf.substring(CATEGORY_PREFIX.length()))
                .distinct()
                .toList();
    }
}
