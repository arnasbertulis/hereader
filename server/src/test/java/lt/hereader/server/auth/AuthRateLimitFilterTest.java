package lt.hereader.server.auth;

import lt.hereader.server.config.RateLimitFilter;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.servlet.mvc.method.RequestMappingInfo;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

/// Runs against a real embedded server, not `MockMvc`: `X-Forwarded-For`
/// translation (`server.forward-headers-strategy=framework`) only happens in
/// the servlet container's own filter, which `MockMvc`'s `webAppContextSetup`
/// never invokes.
///
/// One class, one context, one embedded server for all six budgets
/// (`/auth`, `/catalogue/categories`, `/catalogue/languages`,
/// `/catalogue/cover`, `/catalogue/download`, `/catalogue/search`).
/// `requests-per-minute` is 2 for every budget, so each can be exhausted in a
/// handful of calls instead of ten.
///
/// Every test below shares one `RateLimitFilter` instance and its in-memory
/// per-IP counters, so each test uses its own synthetic `X-Forwarded-For`
/// octet from `freshIp()` — reusing one within the same path would let an
/// earlier test's requests count against a later test's budget. The same
/// octet is safe to reuse across *different* paths, since budgets are tracked
/// per path as well as per IP.
///
/// Cross-budget independence in general is `RateLimitFilterTest`'s job, as a
/// plain unit test against the filter directly. The parameterized tests below
/// drive the five catalogue budgets from `CATALOGUE_BUDGET_PATHS`, one entry
/// per prefix in `SecurityConfig.rateLimitBudgets`, so a sixth catalogue
/// budget added later needs only a new entry there rather than a new test
/// class. `everyCatalogueRequestMappingHasAConfiguredBudget` closes the gap
/// that list can't: it reads the actual registered `@GetMapping`s under
/// `/catalogue` and fails if one matches no configured prefix, which is
/// exactly how #188 happened — `/catalogue/categories` fell through
/// `RateLimitFilter` unthrottled before its budget existed.
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

    // Mirrors the five /catalogue prefixes in SecurityConfig.rateLimitBudgets;
    // cover and download carry a book number since RateLimitFilter matches on
    // the concrete request path, not the bare prefix.
    private static final List<String> CATALOGUE_BUDGET_PATHS = List.of(
            "/catalogue/categories",
            "/catalogue/languages",
            "/catalogue/cover/1",
            "/catalogue/download/1",
            "/catalogue/search");

    private static Stream<String> cataloguePaths() {
        return CATALOGUE_BUDGET_PATHS.stream();
    }

    @LocalServerPort
    private int port;

    @Autowired
    private List<RateLimitFilter.PathBudget> budgets;

    @Autowired
    private RequestMappingHandlerMapping requestMappingHandlerMapping;

    private final HttpClient http = HttpClient.newHttpClient();

    // Static: JUnit creates a fresh test instance per method, so an instance
    // field would reset to the same start value every time and every test
    // would collide on the same octet. Distinct per call regardless of test
    // execution order, so no two tests ever share an IP and
    // cross-contaminate each other's budget.
    private static final AtomicInteger nextOctet = new AtomicInteger(1);

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
            var ip = freshIp();
            registerAttempt(ip);
            registerAttempt(ip);

            // Same budget as the pair above would be exhausted by a third call;
            // a different X-Forwarded-For must still be allowed through.
            var fromAnotherIp = registerAttempt(freshIp());

            assertThat(fromAnotherIp.statusCode()).isNotEqualTo(429);
        }
    }

    @ParameterizedTest
    @MethodSource("cataloguePaths")
    void aThirdRequestInAMinuteFromTheSameIpIsThrottled(String path) throws Exception {
        var ip = freshIp();
        get(path, ip);
        get(path, ip);
        var third = get(path, ip);

        assertThat(third.statusCode()).isEqualTo(429);
        assertThat(third.headers().firstValue("Retry-After")).isPresent();
    }

    /// The book number used for cover/download does not need to exist in the
    /// Catalogue — RateLimitFilter runs before CatalogueController ever
    /// checks, so a request that will 404 downstream still counts against the
    /// budget on its way past.
    @ParameterizedTest
    @MethodSource("cataloguePaths")
    void exhaustingOneCataloguePathLeavesTheOthersUntouched(String exhaustedPath) throws Exception {
        var ip = freshIp();
        get(exhaustedPath, ip);
        get(exhaustedPath, ip);
        get(exhaustedPath, ip); // exhausts this path's budget of 2

        for (var otherPath : CATALOGUE_BUDGET_PATHS) {
            if (otherPath.equals(exhaustedPath)) {
                continue;
            }
            var response = get(otherPath, ip);
            assertThat(response.statusCode())
                    .as("%s should be unaffected by exhausting %s", otherPath, exhaustedPath)
                    .isNotEqualTo(429);
        }
    }

    /// Reads the real registered mappings rather than a hardcoded list, so a
    /// /catalogue endpoint added without a budget fails this test instead of
    /// silently passing through RateLimitFilter unthrottled (#188).
    @Test
    void everyCatalogueRequestMappingHasAConfiguredBudget() {
        var cataloguePaths = requestMappingHandlerMapping.getHandlerMethods().keySet().stream()
                .map(RequestMappingInfo::getPatternValues)
                .flatMap(Set::stream)
                .filter(path -> path.startsWith("/catalogue"))
                .toList();

        assertThat(cataloguePaths).isNotEmpty();
        for (var path : cataloguePaths) {
            assertThat(budgets.stream().anyMatch(budget -> path.startsWith(budget.pathPrefix())))
                    .as("no configured rate-limit budget covers mapping %s", path)
                    .isTrue();
        }
    }

    private String freshIp() {
        return "203.0.113." + nextOctet.getAndIncrement();
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
