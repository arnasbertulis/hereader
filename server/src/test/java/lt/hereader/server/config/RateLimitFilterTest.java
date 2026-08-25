package lt.hereader.server.config;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/// Plain unit tests against the filter directly, no Spring context: budget
/// independence across paths is a property of the filter's own bookkeeping,
/// not of anything Spring wires around it. `AuthRateLimitFilterTest` still
/// covers the `/auth` budget end to end through a real embedded server.
class RateLimitFilterTest {

    private final RateLimitFilter filter = new RateLimitFilter(
            List.of(
                    new RateLimitFilter.PathBudget("/auth", 2),
                    new RateLimitFilter.PathBudget("/covers", 2)),
            JsonMapper.builder().build());

    @Test
    void exhaustingOnePathsBudgetLeavesAnotherConfiguredPathUnaffected() throws Exception {
        send("/auth", "10.0.0.1");
        send("/auth", "10.0.0.1");
        var thirdAuthCall = send("/auth", "10.0.0.1");
        assertThat(thirdAuthCall.getStatus()).isEqualTo(429);

        var coversCall = send("/covers", "10.0.0.1");
        assertThat(coversCall.getStatus()).isNotEqualTo(429);
    }

    @Test
    void aPathWithNoConfiguredBudgetPassesThroughUnlimited() throws Exception {
        for (int i = 0; i < 5; i++) {
            var response = send("/health", "10.0.0.2");
            assertThat(response.getStatus()).isNotEqualTo(429);
        }
    }

    private MockHttpServletResponse send(String servletPath, String remoteAddr) throws Exception {
        var request = new MockHttpServletRequest();
        request.setServletPath(servletPath);
        request.setRemoteAddr(remoteAddr);
        var response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        return response;
    }
}
