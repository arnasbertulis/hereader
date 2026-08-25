package lt.hereader.server.catalogue;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;

/// Cover image and book file pass-through for the Catalogue (ADR 0029,
/// #179). Neither file is ever written to the database; a cover is cached on
/// a bounded disk volume because it is immutable for a given book, a book
/// file is not cached at all.
///
/// A response is read fully into memory before anything is sent to the
/// caller, rather than piped through as it arrives. That is a deliberate
/// difference from CataloguePopularityIngestionService's true streaming: a
/// single cover or no-images EPUB is small enough to hold (the CSV-fetching
/// sibling already holds a larger export in memory), and reading fully is
/// what lets a connection Gutenberg drops mid-response surface as an
/// IOException here — caught below and turned into a 502 — instead of a
/// truncated body already committed to the client with a 200 status.
@Service
public class CatalogueProxyService {

    record ProxyFile(byte[] bytes, MediaType contentType) {}

    private static final MediaType EPUB_MEDIA_TYPE = MediaType.parseMediaType("application/epub+zip");

    private final CatalogueRepository repository;
    private final HttpClient http;
    private final Duration timeout;
    private final String coverUrlTemplate;
    private final String noImagesEpubUrlTemplate;
    private final String imagesEpubUrlTemplate;
    private final Path coverCacheDir;

    CatalogueProxyService(
            CatalogueRepository repository,
            @Value("${hereader.catalogue.gutenberg-cover-url-template:"
                    + "https://www.gutenberg.org/cache/epub/{id}/pg{id}.cover.medium.jpg}")
            String coverUrlTemplate,
            // Addressed by URL convention rather than announced in upstream
            // metadata (ADR 0029) — a book without this edition 404s here,
            // and the images edition below is tried next.
            @Value("${hereader.catalogue.gutenberg-epub-noimages-url-template:"
                    + "https://www.gutenberg.org/cache/epub/{id}/pg{id}.epub}")
            String noImagesEpubUrlTemplate,
            @Value("${hereader.catalogue.gutenberg-epub-images-url-template:"
                    + "https://www.gutenberg.org/cache/epub/{id}/pg{id}-images.epub}")
            String imagesEpubUrlTemplate,
            @Value("${hereader.catalogue.gutenberg-http-timeout-seconds:10}")
            long timeoutSeconds,
            @Value("${hereader.catalogue.cover-cache-dir:"
                    + "${java.io.tmpdir}/hereader-catalogue-covers}")
            String coverCacheDir) {

        this.repository = repository;
        this.coverUrlTemplate = coverUrlTemplate;
        this.noImagesEpubUrlTemplate = noImagesEpubUrlTemplate;
        this.imagesEpubUrlTemplate = imagesEpubUrlTemplate;
        this.timeout = Duration.ofSeconds(timeoutSeconds);
        this.http = HttpClient.newBuilder().connectTimeout(this.timeout).build();
        this.coverCacheDir = Path.of(coverCacheDir);
        try {
            Files.createDirectories(this.coverCacheDir);
        } catch (IOException e) {
            throw new UncheckedIOException(
                    "Could not create the cover cache directory at " + coverCacheDir, e);
        }
    }

    /// Serves a cached cover when one is already on disk, otherwise fetches,
    /// caches, and serves it. Rejects a book number never ingested (ADR
    /// 0029) before either touches Gutenberg.
    public ProxyFile fetchCover(int gutenbergId) {
        requireIngested(gutenbergId);

        var cached = readCached(gutenbergId);
        if (cached != null) {
            return new ProxyFile(cached, MediaType.IMAGE_JPEG);
        }

        var bytes = fetch(expand(coverUrlTemplate, gutenbergId));
        writeCached(gutenbergId, bytes);
        return new ProxyFile(bytes, MediaType.IMAGE_JPEG);
    }

    /// The no-images edition first, falling back to the advertised
    /// (illustrated) edition only when the no-images one 404s — the
    /// distinction the app cares about (a smaller download) is server-side
    /// so it exists in one place rather than being reimplemented per
    /// platform (ADR 0029).
    public ProxyFile fetchBookFile(int gutenbergId) {
        requireIngested(gutenbergId);

        try {
            return new ProxyFile(
                    fetch(expand(noImagesEpubUrlTemplate, gutenbergId)),
                    EPUB_MEDIA_TYPE);
        } catch (ResponseStatusException e) {
            if (e.getStatusCode() != HttpStatus.NOT_FOUND) {
                throw e;
            }
        }
        return new ProxyFile(
                fetch(expand(imagesEpubUrlTemplate, gutenbergId)),
                EPUB_MEDIA_TYPE);
    }

    private void requireIngested(int gutenbergId) {
        if (!repository.existsByGutenbergId(gutenbergId)) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND, "No such book in the Catalogue.");
        }
    }

    private byte[] fetch(URI uri) {
        HttpResponse<byte[]> response;
        try {
            response = http.send(
                    HttpRequest.newBuilder(uri).timeout(timeout).GET().build(),
                    HttpResponse.BodyHandlers.ofByteArray());
        } catch (HttpTimeoutException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY, "Gutenberg did not respond in time.");
        } catch (IOException e) {
            // Covers a dropped connection mid-response as much as one that
            // never opened — either way nothing partial reaches the caller,
            // because response.body() above is never reached.
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY, "Could not reach Gutenberg.");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY, "Interrupted while reaching Gutenberg.");
        }

        if (response.statusCode() == 404) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND, "Gutenberg has nothing at this location.");
        }
        if (response.statusCode() != 200) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    "Gutenberg returned HTTP " + response.statusCode() + ".");
        }
        return response.body();
    }

    private static URI expand(String template, int gutenbergId) {
        return URI.create(template.replace("{id}", Integer.toString(gutenbergId)));
    }

    private byte[] readCached(int gutenbergId) {
        var path = coverCacheDir.resolve(gutenbergId + ".jpg");
        if (!Files.isRegularFile(path)) {
            return null;
        }
        try {
            return Files.readAllBytes(path);
        } catch (IOException e) {
            // A damaged cache entry is refetched rather than failing the
            // request — the cache exists to save a round trip, not to be
            // load-bearing for correctness.
            return null;
        }
    }

    /// Writes to a temporary name and renames into place, so a second
    /// request racing the first on an uncached id never reads a
    /// partially-written file.
    private void writeCached(int gutenbergId, byte[] bytes) {
        var path = coverCacheDir.resolve(gutenbergId + ".jpg");
        var tmp = coverCacheDir.resolve(gutenbergId + ".jpg.tmp-" + Thread.currentThread().threadId());
        try {
            Files.write(tmp, bytes);
            Files.move(tmp, path, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            // Serving the cover the caller asked for matters more than
            // caching it for the next one.
        }
    }
}
