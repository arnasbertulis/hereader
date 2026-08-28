package lt.hereader.server.auth;

import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/// Runs against a real embedded server, not `MockMvc`: `X-Forwarded-For`
/// translation (`server.forward-headers-strategy=framework`) only happens in
/// the servlet container's own filter, which `MockMvc`'s `webAppContextSetup`
/// never invokes.
///
/// One class, one context, one embedded server for all six budgets
/// (`/auth`, `/catalogue/categories`, `/catalogue/languages`,
/// `/catalogue/cover`, `/catalogue/download`, `/catalogue/search`) — the five
/// classes this replaces each set a different combination of these
/// properties, and since a `properties` override is part of Spring's context
/// cache key, no two ever matched closely enough to share a context. All six
/// are set together here, once, so the key stops forking. `requests-per-minute`
/// is 2 for every budget, so each can be exhausted in a handful of calls
/// instead of ten.
///
/// All eleven tests below share one `RateLimitFilter` instance and its
/// in-memory per-IP counters, so each test uses its own synthetic
/// `X-Forwarded-For` octet — reusing one within the same path would let an
/// earlier test's requests count against a later test's budget. The same
/// octet is safe to reuse across *different* paths, since budgets are
/// tracked per path as well as per IP.
///
/// Cross-budget independence in general is `RateLimitFilterTest`'s job, as a
/// plain unit test against the filter directly; nested classes below prove
/// only that each configured path enforces its own budget through the real
/// filter chain, grouped the same way the original five classes were split.
/// Nested classes share the outer instance's `port`/`http` and this context.
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "hereader.auth-rate-limit.requests-per-minute=2",
                "hereader.catalogue-categories-rate-limit.requests-per-minute=2",
                "hereader.catalogue-languages-rate-limit.requests-per-minute=2",
                "hereader.catalogue-cover-rate-limit.requests-per-minute=2",
                "hereader.catalogue-download-rate-limit.requests-per-minute=2",
                "hereader.catalogue-search-rate-limit.requests-per-minute=2"
        })
@ActiveProfiles("test")
class AuthRateLimitFilterTest {

    @LocalServerPort
    private int port;

    private final HttpClient http = HttpClient.newHttpClient();

    @Nested
    class Auth {

        @Test
        void aThirdRequestInAMinuteFromTheSameIpIsThrottled() throws Exception {
            registerAttempt(null);
            registerAttempt(null);
            var third = registerAttempt(null);

            assertThat(third.statusCode()).isEqualTo(429);
            assertThat(third.headers().firstValue("Retry-After")).isPresent();
            assertThat(third.body()).contains("Too many requests");
        }

        @Test
        void twoForwardedIpsGetIndependentBudgets() throws Exception {
            registerAttempt("203.0.113.10");
            registerAttempt("203.0.113.10");

            // Same budget as the pair above would be exhausted by a third call;
            // a different X-Forwarded-For must still be allowed through.
            var fromAnotherIp = registerAttempt("203.0.113.20");

            assertThat(fromAnotherIp.statusCode()).isNotEqualTo(429);
        }
    }

    /// Proof that /catalogue/categories carries its own budget in
    /// SecurityConfig rather than falling through RateLimitFilter unthrottled
    /// (#188 — it matched no configured prefix before this budget was added),
    /// and that exhausting it leaves /catalogue/search alone.
    @Nested
    class CatalogueCategories {

        @Test
        void aThirdCategoriesRequestInAMinuteFromTheSameIpIsThrottled() throws Exception {
            get("/catalogue/categories", "203.0.113.40");
            get("/catalogue/categories", "203.0.113.40");
            var third = get("/catalogue/categories", "203.0.113.40");

            assertThat(third.statusCode()).isEqualTo(429);
            assertThat(third.headers().firstValue("Retry-After")).isPresent();
        }

        @Test
        void exhaustingCategoriesDoesNotThrottleSearch() throws Exception {
            get("/catalogue/categories", "203.0.113.41");
            get("/catalogue/categories", "203.0.113.41");
            get("/catalogue/categories", "203.0.113.41"); // exhausts categories' budget of 2

            var search = get("/catalogue/search", "203.0.113.41");

            assertThat(search.statusCode()).isNotEqualTo(429);
        }
    }

    /// Proof that /catalogue/languages carries its own budget in
    /// SecurityConfig rather than falling through RateLimitFilter unthrottled,
    /// or sharing categories' budget by accident, and that exhausting it
    /// leaves /catalogue/search alone.
    @Nested
    class CatalogueLanguages {

        @Test
        void aThirdLanguagesRequestInAMinuteFromTheSameIpIsThrottled() throws Exception {
            get("/catalogue/languages", "203.0.113.50");
            get("/catalogue/languages", "203.0.113.50");
            var third = get("/catalogue/languages", "203.0.113.50");

            assertThat(third.statusCode()).isEqualTo(429);
            assertThat(third.headers().firstValue("Retry-After")).isPresent();
        }

        @Test
        void exhaustingLanguagesDoesNotThrottleSearch() throws Exception {
            get("/catalogue/languages", "203.0.113.51");
            get("/catalogue/languages", "203.0.113.51");
            get("/catalogue/languages", "203.0.113.51"); // exhausts languages' budget of 2

            var search = get("/catalogue/search", "203.0.113.51");

            assertThat(search.statusCode()).isNotEqualTo(429);
        }
    }

    /// Proof that /catalogue/cover and /catalogue/download are actually
    /// wired to their own budgets in SecurityConfig, each independent of the
    /// other and of search's (ADR 0029's amendment to ADR 0026).
    ///
    /// The book number used throughout does not need to exist in the
    /// Catalogue — RateLimitFilter runs before CatalogueController ever
    /// checks, so a request that will 404 downstream still counts against the
    /// budget on its way past.
    @Nested
    class CatalogueProxy {

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
    }

    /// A real embedded server, since `X-Forwarded-For` translation only
    /// happens in the servlet container's own filter, which `MockMvc` never
    /// invokes. The Gutenberg CSV URL is left at its default — this budget
    /// guards /catalogue/search, which answers without any Ingestion ever
    /// having run.
    @Nested
    class CatalogueSearch {

        @Test
        void aThirdSearchInAMinuteFromTheSameIpIsThrottled() throws Exception {
            get("/catalogue/search", null);
            get("/catalogue/search", null);
            var third = get("/catalogue/search", null);

            assertThat(third.statusCode()).isEqualTo(429);
            assertThat(third.headers().firstValue("Retry-After")).isPresent();
        }

        @Test
        void twoForwardedIpsGetIndependentBudgets() throws Exception {
            get("/catalogue/search", "203.0.113.10");
            get("/catalogue/search", "203.0.113.10");

            var fromAnotherIp = get("/catalogue/search", "203.0.113.20");

            assertThat(fromAnotherIp.statusCode()).isNotEqualTo(429);
        }
    }

    private HttpResponse<String> registerAttempt(String forwardedFor) throws Exception {
        var email = "user-" + UUID.randomUUID() + "@example.com";
        var body = """
                {"email": "%s", "password": "password123"}
                """.formatted(email);

        var requestBuilder = HttpRequest.newBuilder()
                .uri(URI.create("http://localhost:" + port + "/api/auth/register"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body));
        if (forwardedFor != null) {
            requestBuilder.header("X-Forwarded-For", forwardedFor);
        }

        return http.send(requestBuilder.build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> get(String path, String forwardedFor) throws Exception {
        var requestBuilder = HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api" + path))
                .GET();
        if (forwardedFor != null) {
            requestBuilder.header("X-Forwarded-For", forwardedFor);
        }
        return http.send(requestBuilder.build(), HttpResponse.BodyHandlers.ofString());
    }
}
