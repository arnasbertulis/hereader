package lt.hereader.server.catalogue;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import static org.assertj.core.api.Assertions.assertThat;

/// Mirrors CatalogueSearchRateLimitFilterTest: proof that /catalogue/cover
/// and /catalogue/download are actually wired to their own budgets in
/// SecurityConfig, each independent of the other and of search's (ADR 0029's
/// amendment to ADR 0026). Cross-budget independence in general is
/// RateLimitFilterTest's job; what is specific here is that these two paths
/// carry the budgets #179 claims for them.
///
/// The book number used throughout does not need to exist in the Catalogue —
/// RateLimitFilter runs before CatalogueController ever checks, so a request
/// that will 404 downstream still counts against the budget on its way past.
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "hereader.catalogue-cover-rate-limit.requests-per-minute=2",
                "hereader.catalogue-download-rate-limit.requests-per-minute=2"
        })
@ActiveProfiles("test")
class CatalogueProxyRateLimitFilterTest {

    @LocalServerPort
    private int port;

    private final HttpClient http = HttpClient.newHttpClient();

    // Each test uses its own synthetic X-Forwarded-For address. The three
    // tests share one Spring context and therefore one RateLimitFilter
    // instance and its in-memory per-IP counters; without distinct
    // addresses, whichever test ran first would exhaust a real budget of 2
    // before the next test's own requests were counted (CatalogueSearchRate
    // LimitFilterTest establishes the same pattern for /catalogue/search).

    @Test
    void aThirdCoverRequestInAMinuteFromTheSameIpIsThrottled() throws Exception {
        get("/catalogue/cover/1", "203.0.113.30");
        get("/catalogue/cover/1", "203.0.113.30");
        var third = get("/catalogue/cover/1", "203.0.113.30");

        assertThat(third.statusCode()).isEqualTo(429);
        assertThat(third.headers().firstValue("Retry-After")).isPresent();
    }

    @Test
    void aThirdDownloadRequestInAMinuteFromTheSameIpIsThrottled() throws Exception {
        get("/catalogue/download/1", "203.0.113.31");
        get("/catalogue/download/1", "203.0.113.31");
        var third = get("/catalogue/download/1", "203.0.113.31");

        assertThat(third.statusCode()).isEqualTo(429);
    }

    @Test
    void exhaustingCoverDoesNotThrottleDownload() throws Exception {
        get("/catalogue/cover/1", "203.0.113.32");
        get("/catalogue/cover/1", "203.0.113.32");
        get("/catalogue/cover/1", "203.0.113.32"); // exhausts cover's budget of 2

        var download = get("/catalogue/download/1", "203.0.113.32");

        assertThat(download.statusCode()).isNotEqualTo(429);
    }

    private HttpResponse<String> get(String path, String forwardedFor) throws Exception {
        return http.send(
                HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api" + path))
                        .header("X-Forwarded-For", forwardedFor)
                        .GET()
                        .build(),
                HttpResponse.BodyHandlers.ofString());
    }
}
