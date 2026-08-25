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

    /// Matches [query] against title or authors, case-insensitively, when
    /// non-blank; otherwise every entry. Ordered by title so paging is
    /// stable — popularity ordering is a later layer (#177).
    ///
    /// Asks for one more row than the caller wants, so hasMore is known
    /// without a second, count-only query.
    public List<CatalogueDtos.Entry> search(String query, int offset, int limit) {
        var pattern = "%" + escapeLike(query) + "%";

        return jdbc.sql("""
                select gutenberg_id, title, authors, language, subjects, issued
                from catalogue_entries
                where :query = ''
                   or title ilike :pattern escape '\\'
                   or authors ilike :pattern escape '\\'
                order by title, gutenberg_id
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
