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

/// Mirrors CatalogueCategoriesRateLimitFilterTest: proof that
/// /catalogue/languages carries its own budget in SecurityConfig rather than
/// falling through RateLimitFilter unthrottled, or sharing categories'
/// budget by accident. Cross-budget independence in general is
/// RateLimitFilterTest's job; what is specific here is that this path is
/// actually wired up, and that exhausting it leaves /catalogue/search alone.
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "hereader.catalogue-languages-rate-limit.requests-per-minute=2",
                "hereader.catalogue-search-rate-limit.requests-per-minute=2"
        })
@ActiveProfiles("test")
class CatalogueLanguagesRateLimitFilterTest {

    @LocalServerPort
    private int port;

    private final HttpClient http = HttpClient.newHttpClient();

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

    private HttpResponse<String> get(String path, String forwardedFor) throws Exception {
        return http.send(
                HttpRequest.newBuilder(URI.create("http://localhost:" + port + "/api" + path))
                        .header("X-Forwarded-For", forwardedFor)
                        .GET()
                        .build(),
                HttpResponse.BodyHandlers.ofString());
    }
}
