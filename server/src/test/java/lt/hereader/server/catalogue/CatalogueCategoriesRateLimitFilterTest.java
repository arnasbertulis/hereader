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

/// Mirrors CatalogueSearchRateLimitFilterTest: proof that /catalogue/categories
/// carries its own budget in SecurityConfig rather than falling through
/// RateLimitFilter unthrottled (#188 — it matched no configured prefix before
/// this budget was added). Cross-budget independence in general is
/// RateLimitFilterTest's job; what is specific here is that this path is
/// actually wired up, and that exhausting it leaves /catalogue/search alone.
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "hereader.catalogue-categories-rate-limit.requests-per-minute=2",
                "hereader.catalogue-search-rate-limit.requests-per-minute=2"
        })
@ActiveProfiles("test")
class CatalogueCategoriesRateLimitFilterTest {

    @LocalServerPort
    private int port;

    private final HttpClient http = HttpClient.newHttpClient();

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

    private HttpResponse<String> get(String path, String forwardedFor) throws Exception {
        return http.send(
                HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api" + path))
                        .header("X-Forwarded-For", forwardedFor)
                        .GET()
                        .build(),
                HttpResponse.BodyHandlers.ofString());
    }
}
