package lt.hereader.server.catalogue;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@Repository
public class CatalogueRepository {

    private final JdbcClient jdbc;

    CatalogueRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /// Writes one row for the given refresh. On conflict, every column is
    /// overwritten, including ingestion_run — an entry present in this and
    /// the previous refresh survives the sweep in deleteNotWrittenBy below.
    public void upsert(
            int gutenbergId,
            String title,
            String authors,
            String language,
            String subjects,
            LocalDate issued,
            UUID ingestionRun) {

        jdbc.sql("""
                insert into catalogue_entries
                    (gutenberg_id, title, authors, language, subjects,
                     issued, ingestion_run, updated_at)
                values
                    (:id, :title, :authors, :language, :subjects,
                     :issued, :run, now())
                on conflict (gutenberg_id) do update set
                    title         = excluded.title,
                    authors       = excluded.authors,
                    language      = excluded.language,
                    subjects      = excluded.subjects,
                    issued        = excluded.issued,
                    ingestion_run = excluded.ingestion_run,
                    updated_at    = now()
                """)
                .param("id", gutenbergId)
                .param("title", title)
                .param("authors", authors)
                .param("language", language)
                .param("subjects", subjects)
                .param("issued", issued)
                .param("run", ingestionRun)
                .update();
    }

    /// Deletes every row a refresh did not touch — the upstream records that
    /// vanished. One statement rather than an `in (...)` of every id present,
    /// which would need a placeholder per id for a catalogue of roughly
    /// 78,000 rows.
    public void deleteNotWrittenBy(UUID ingestionRun) {
        jdbc.sql("delete from catalogue_entries where ingestion_run <> :run")
                .param("run", ingestionRun)
                .update();
    }

    /// False only when no Ingestion has ever completed — the signal
    /// CatalogueService uses to tell that state apart from a search that
    /// ran and matched nothing.
    public boolean hasAnyEntries() {
        return Boolean.TRUE.equals(jdbc.sql("select exists(select 1 from catalogue_entries)")
                .query(Boolean.class)
                .single());
    }

    /// The check CatalogueProxyService uses to reject a book number that was
    /// never ingested, before it is ever used to build a Gutenberg URL — what
    /// keeps the cover and download endpoints from being pointed anywhere
    /// that has not already been ingested (ADR 0029).
    public boolean existsByGutenbergId(int gutenbergId) {
        return Boolean.TRUE.equals(jdbc.sql(
                        "select exists(select 1 from catalogue_entries where gutenberg_id = :id)")
                .param("id", gutenbergId)
                .query(Boolean.class)
                .single());
    }

    /// Matches [query] against title or authors, case-insensitively, when
    /// non-blank; otherwise every entry. Ordered by title, or by download
    /// count under [sort] POPULARITY — either way [gutenberg_id] breaks ties
    /// so paging is stable.
    ///
    /// Asks for one more row than the caller wants, so hasMore is known
    /// without a second, count-only query.
    ///
    /// [sort] is never caller-supplied text — CatalogueController parses it
    /// into the enum before this is called — so building the order-by clause
    /// from it here is safe.
    public List<CatalogueDtos.Entry> search(
            String query, int offset, int limit, CatalogueDtos.Sort sort) {

        var pattern = "%" + escapeLike(query) + "%";
        var orderBy = sort == CatalogueDtos.Sort.POPULARITY
                ? "downloads desc nulls last, title, gutenberg_id"
                : "title, gutenberg_id";

        return jdbc.sql("""
                select gutenberg_id, title, authors, language, subjects, issued
                from catalogue_entries
                where :query = ''
                   or title ilike :pattern escape '\\'
                   or authors ilike :pattern escape '\\'
                order by\s""" + orderBy + """

                limit :limit offset :offset
                """)
                .param("query", query)
                .param("pattern", pattern)
                .param("limit", limit)
                .param("offset", offset)
                .query((rs, _) -> new CatalogueDtos.Entry(
                        rs.getInt("gutenberg_id"),
                        rs.getString("title"),
                        rs.getString("authors"),
                        rs.getString("language"),
                        rs.getString("subjects"),
                        rs.getObject("issued", LocalDate.class)))
                .list();
    }

    /// Updates the download count for an existing row only. A book number
    /// present in the RDF archive but absent from catalogue_entries — the CSV
    /// hasn't been ingested yet, or Gutenberg withdrew the book — has nothing
    /// to join to, and this is a no-op: no fuzzy matching, and popularity
    /// Ingestion never inserts a Catalogue Entry (ADR 0029, #177).
    public void updateDownloads(int gutenbergId, int downloads) {
        jdbc.sql("update catalogue_entries set downloads = :downloads where gutenberg_id = :id")
                .param("downloads", downloads)
                .param("id", gutenbergId)
                .update();
    }

    /// Escapes ILIKE's own wildcard characters out of caller input, so a
    /// reader searching for "50%" or "under_score" gets a literal match
    /// rather than one or two characters of their query being treated as
    /// pattern syntax.
    private static String escapeLike(String value) {
        return value
                .replace("\\", "\\\\")
                .replace("%", "\\%")
                .replace("_", "\\_");
    }
}
