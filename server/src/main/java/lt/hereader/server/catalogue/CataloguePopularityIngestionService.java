package lt.hereader.server.catalogue;

import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

/// Streams Gutenberg's bulk RDF metadata archive and applies each book's
/// download count to the matching Catalogue Entry (ADR 0029). A separate
/// layer from CatalogueIngestionService on purpose: that service's refresh is
/// one short transaction because its whole export fits in memory first, but
/// this archive is 2 GB uncompressed and is never held in memory beyond one
/// entry, so there is nothing to parse-then-write-atomically. Every matched
/// entry is written as its own statement as the archive streams past, so a
/// failure partway through — a truncated download, a corrupt archive — keeps
/// whatever counts were already applied rather than rolling all of them back;
/// the Catalogue itself (title, authors, ...) is never touched here and is
/// unaffected either way.
@Service
public class CataloguePopularityIngestionService {

    private final CatalogueRepository repository;
    private final HttpClient http;
    private final URI rdfArchiveUri;

    CataloguePopularityIngestionService(
            CatalogueRepository repository,
            @Value("${hereader.catalogue.gutenberg-rdf-archive-url:"
                    + "https://www.gutenberg.org/cache/epub/feeds/rdf-files.tar.bz2}")
            String rdfArchiveUrl) {

        this.repository = repository;
        this.rdfArchiveUri = URI.create(rdfArchiveUrl);
        this.http = HttpClient.newHttpClient();
    }

    /// Fetches, decompresses and applies download counts. Throws
    /// CatalogueIngestionException on anything wrong with the upstream
    /// archive itself — unreachable, non-200, a truncated bzip2 or tar
    /// stream; the caller (CatalogueIngestionScheduler,
    /// CatalogueIngestionRunner) decides what to do with that. A malformed
    /// individual entry is not one of those — GutenbergRdfEntryReader skips
    /// it and streaming continues.
    public void refresh() {
        HttpResponse<InputStream> response;
        try {
            response = http.send(
                    HttpRequest.newBuilder(rdfArchiveUri).GET().build(),
                    HttpResponse.BodyHandlers.ofInputStream());
        } catch (IOException e) {
            throw new CatalogueIngestionException(
                    "Could not reach the Gutenberg RDF archive.", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new CatalogueIngestionException(
                    "Interrupted while fetching the Gutenberg RDF archive.", e);
        }

        if (response.statusCode() != 200) {
            throw new CatalogueIngestionException(
                    "Gutenberg RDF archive returned HTTP "
                            + response.statusCode() + ".");
        }

        try (var bzip2 = new BZip2CompressorInputStream(response.body());
             var tar = new TarArchiveInputStream(bzip2)) {

            TarArchiveEntry entry;
            while ((entry = tar.getNextEntry()) != null) {
                if (entry.isDirectory() || !entry.getName().endsWith(".rdf")) {
                    continue;
                }
                var record = GutenbergRdfEntryReader.read(tar);
                if (record != null) {
                    repository.updateDownloads(record.gutenbergId(), record.downloads());
                }
            }
        } catch (IOException e) {
            throw new CatalogueIngestionException(
                    "Gutenberg RDF archive ended unexpectedly.", e);
        }
    }
}
