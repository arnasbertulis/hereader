package lt.hereader.server.auth;

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
/// `requests-per-minute` is overridden to 2 for this class alone, so the
/// budget can be exhausted in a handful of calls instead of ten.
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "hereader.auth-rate-limit.requests-per-minute=2")
@ActiveProfiles("test")
class AuthRateLimitFilterTest {

    @LocalServerPort
    private int port;

    private final HttpClient http = HttpClient.newHttpClient();

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
}
