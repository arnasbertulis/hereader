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

/// Mirrors AuthRateLimitFilterTest: a real embedded server, since
/// `X-Forwarded-For` translation only happens in the servlet container's own
/// filter, which `MockMvc` never invokes.
///
/// `requests-per-minute` is overridden to 2 for this class alone, so the
/// budget can be exhausted in a handful of calls. The Gutenberg CSV URL is
/// left at its default — this budget guards `/catalogue/search`, which
/// answers without any Ingestion ever having run.
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "hereader.catalogue-search-rate-limit.requests-per-minute=2")
@ActiveProfiles("test")
class CatalogueSearchRateLimitFilterTest {

    @LocalServerPort
    private int port;

    private final HttpClient http = HttpClient.newHttpClient();

    @Test
    void aThirdSearchInAMinuteFromTheSameIpIsThrottled() throws Exception {
        search(null);
        search(null);
        var third = search(null);

        assertThat(third.statusCode()).isEqualTo(429);
        assertThat(third.headers().firstValue("Retry-After")).isPresent();
    }

    // Cross-budget independence is RateLimitFilterTest's job, generically,
    // against the filter directly. What is specific to this class is that
    // /catalogue/search is actually wired to its own budget in SecurityConfig
    // — the two tests below are that proof, end to end.

    @Test
    void twoForwardedIpsGetIndependentBudgets() throws Exception {
        search("203.0.113.10");
        search("203.0.113.10");

        var fromAnotherIp = search("203.0.113.20");

        assertThat(fromAnotherIp.statusCode()).isNotEqualTo(429);
    }

    private HttpResponse<String> search(String forwardedFor) throws Exception {
        var requestBuilder = HttpRequest.newBuilder(
                URI.create("http://localhost:" + port + "/api/catalogue/search"))
                .GET();
        if (forwardedFor != null) {
            requestBuilder.header("X-Forwarded-For", forwardedFor);
        }
        return http.send(requestBuilder.build(), HttpResponse.BodyHandlers.ofString());
    }
}
