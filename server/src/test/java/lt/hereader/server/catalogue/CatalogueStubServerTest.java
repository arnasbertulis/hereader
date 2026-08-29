package lt.hereader.server.catalogue;

import com.sun.net.httpserver.HttpServer;
import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream;
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorOutputStream;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;

/// Shared bootstrap for the three catalogue integration test classes
/// (controller, popularity ingestion, proxy): one local HTTP stub standing
/// in for every Gutenberg endpoint any of them exercises, with its port and
/// the cover cache directory published as plain JVM system properties rather
/// than through `@DynamicPropertySource`.
///
/// `@DynamicPropertySource` was ruled out because it is not just a way to
/// pass a value in: `DynamicPropertiesContextCustomizer.equals` (spring-test)
/// compares the *set of declaring methods*, so any class that carries one —
/// even inherited from this base, even resolving to the same values as
/// another class's — gets a context cache key distinct from a class that
/// carries none, such as `SyncControllerIntegrationTest`. That is what
/// forked the catalogue classes' key from sync's before this change, and a
/// shared `@DynamicPropertySource` here would still fork it from sync's,
/// just no longer from each other. A system property carries no such
/// footprint: Spring's `Environment` reads it like any other property, but
/// nothing about the test context's cache key changes because of it, so all
/// four classes now match sync's plain, override-free key exactly (#231).
///
/// A system property only wins if it is set *before* the context is built,
/// which is why `CatalogueStubSessionListener` forces this class to
/// initialize before JUnit executes anything — see `ensureStarted` below.
/// Sharing one context is what makes that ordering load-bearing: the context
/// is built once, by whichever class runs first, and every later class
/// reuses it. Surefire orders alphabetically, so that class is
/// AuthControllerIntegrationTest, which never references this one. Relying
/// on the static initializer alone left the shared context bound to
/// `application.properties`' production defaults, and the catalogue tests
/// then ran against gutenberg.org for real, ingesting the full ~50k-entry
/// catalogue in place of the fixture.
///
/// The stub and the cover cache directory are created once, in static
/// initializers, and deliberately never stopped or deleted: they are now
/// shared by every class extending this one for the life of the JVM, and
/// there is no single "last" class whose `@AfterAll` could safely tear them
/// down without risking a class that runs later in the same suite. Both are
/// local, in-process resources the OS reclaims when the test JVM exits.
abstract class CatalogueStubServerTest {

    static volatile byte[] csvBody = readCsvFixture();
    static volatile int csvStatus = 200;

    static volatile byte[] rdfArchiveBody =
            buildArchive("pg11.rdf", "pg15.rdf", "pg98.rdf");
    static volatile int rdfArchiveStatus = 200;

    static volatile byte[] coverBody = "cover-bytes".getBytes(StandardCharsets.UTF_8);
    static volatile int coverStatus = 200;
    static volatile byte[] noImagesBody = "epub-noimages-bytes".getBytes(StandardCharsets.UTF_8);
    static volatile int noImagesStatus = 200;
    static volatile byte[] imagesBody = "epub-images-bytes".getBytes(StandardCharsets.UTF_8);
    static volatile int imagesStatus = 200;
    // When true, the cover (or no-images book file) handler declares a body
    // longer than what it actually writes, simulating a connection Gutenberg
    // drops mid-response.
    static volatile boolean truncateCover = false;
    static volatile boolean truncateNoImages = false;

    static final Path coverCacheDir = createCoverCacheDir();

    static final HttpServer stub = startStub();

    static {
        var base = "http://localhost:" + stub.getAddress().getPort();
        System.setProperty("hereader.catalogue.gutenberg-catalog-csv-url", base + "/pg_catalog.csv");
        System.setProperty("hereader.catalogue.gutenberg-rdf-archive-url", base + "/rdf-files.tar.bz2");
        System.setProperty("hereader.catalogue.gutenberg-cover-url-template", base + "/covers/{id}");
        System.setProperty("hereader.catalogue.gutenberg-epub-noimages-url-template", base + "/noimages/{id}");
        System.setProperty("hereader.catalogue.gutenberg-epub-images-url-template", base + "/images/{id}");
        System.setProperty("hereader.catalogue.gutenberg-http-timeout-seconds", "1");
        System.setProperty("hereader.catalogue.cover-cache-dir", coverCacheDir.toString());
    }

    /// Called by CatalogueStubSessionListener before JUnit executes any
    /// test. The body is empty on purpose: reaching it at all means this
    /// class's static initializers have already run, which is the whole
    /// point — the stub is listening and its port is in the system
    /// properties before Spring builds the one shared context.
    static void ensureStarted() {
    }

    /// coverCacheDir is created once for the whole JVM, not per test, so a
    /// file a caching test wrote would otherwise leak into the next test and
    /// make it order-dependent — e.g. a cover proxy test expecting a cache
    /// miss would see a stale hit instead.
    static void clearCoverCache() {
        try (var files = Files.walk(coverCacheDir)) {
            files.filter(path -> !path.equals(coverCacheDir))
                    .sorted(Comparator.reverseOrder())
                    .forEach(path -> {
                        try {
                            Files.delete(path);
                        } catch (IOException e) {
                            throw new UncheckedIOException(e);
                        }
                    });
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
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
            server.createContext("/rdf-files.tar.bz2", exchange -> {
                var status = rdfArchiveStatus;
                if (status != 200) {
                    exchange.sendResponseHeaders(status, -1);
                    exchange.close();
                    return;
                }
                var body = rdfArchiveBody;
                exchange.getResponseHeaders().add("Content-Type", "application/x-bzip2");
                exchange.sendResponseHeaders(200, body.length);
                try (var out = exchange.getResponseBody()) {
                    out.write(body);
                }
            });
            server.createContext("/covers/", exchange -> {
                var body = coverBody;
                if (truncateCover) {
                    // Declares the full length but writes half of it, then
                    // closes — the shape of a dropped connection.
                    exchange.sendResponseHeaders(coverStatus, body.length);
                    try (var out = exchange.getResponseBody()) {
                        out.write(body, 0, body.length / 2);
                    }
                    return;
                }
                exchange.sendResponseHeaders(coverStatus, coverStatus == 200 ? body.length : -1);
                try (var out = exchange.getResponseBody()) {
                    if (coverStatus == 200) {
                        out.write(body);
                    }
                }
            });
            server.createContext("/noimages/", exchange -> {
                var body = noImagesBody;
                if (truncateNoImages) {
                    exchange.sendResponseHeaders(noImagesStatus, body.length);
                    try (var out = exchange.getResponseBody()) {
                        out.write(body, 0, body.length / 2);
                    }
                    return;
                }
                exchange.sendResponseHeaders(noImagesStatus, noImagesStatus == 200 ? body.length : -1);
                try (var out = exchange.getResponseBody()) {
                    if (noImagesStatus == 200) {
                        out.write(body);
                    }
                }
            });
            server.createContext("/images/", exchange -> {
                var body = imagesBody;
                exchange.sendResponseHeaders(imagesStatus, imagesStatus == 200 ? body.length : -1);
                try (var out = exchange.getResponseBody()) {
                    if (imagesStatus == 200) {
                        out.write(body);
                    }
                }
            });
            server.start();
            return server;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static Path createCoverCacheDir() {
        try {
            return Files.createTempDirectory("hereader-catalogue-covers-test");
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    // -- fixtures ----------------------------------------------------------

    static byte[] readCsvFixture() {
        try (InputStream in = CatalogueStubServerTest.class
                .getResourceAsStream("/catalogue/pg_catalog_sample.csv")) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /// Packs the named `rdf/*.rdf` fixtures into a tar.bz2 byte array, one
    /// entry per file, named the way the real archive names them
    /// (`cache/epub/<id>/pg<id>.rdf`) — CataloguePopularityIngestionService
    /// does not depend on that name, only on the ".rdf" suffix, but matching
    /// it keeps the fixture honest about what it stands in for.
    static byte[] buildArchive(String... rdfFileNames) {
        var bytes = new ByteArrayOutputStream();
        try (var bzip2 = new BZip2CompressorOutputStream(bytes);
             var tar = new TarArchiveOutputStream(bzip2)) {

            for (var fileName : rdfFileNames) {
                var id = fileName.substring("pg".length(), fileName.length() - ".rdf".length());
                writeEntry(tar, "cache/epub/" + id + "/" + fileName, readRdfFixture(fileName));
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return bytes.toByteArray();
    }

    static void writeEntry(TarArchiveOutputStream tar, String name, byte[] content) throws IOException {
        var entry = new TarArchiveEntry(name);
        entry.setSize(content.length);
        tar.putArchiveEntry(entry);
        tar.write(content);
        tar.closeArchiveEntry();
    }

    static byte[] readRdfFixture(String fileName) {
        try (InputStream in = CatalogueStubServerTest.class
                .getResourceAsStream("/catalogue/rdf/" + fileName)) {
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
