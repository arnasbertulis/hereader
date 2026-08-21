package lt.hereader.server.auth;

import tools.jackson.databind.ObjectMapper;
import jakarta.annotation.PreDestroy;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ProblemDetail;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/// Caps requests under `/auth/**` to a fixed number per minute per client IP.
///
/// `/auth/register` writes two rows and `/auth/login` runs a bcrypt
/// comparison at real cost (ADR 0026), so both are amplifiers for a caller
/// with no limit. Reads `getRemoteAddr()`, which only resolves to the real
/// caller because `server.forward-headers-strategy=framework`
/// (`application.properties`) makes Spring translate `X-Forwarded-For` before
/// this filter runs; without it every caller behind Caddy shares the Docker
/// bridge address and would be throttled as one client.
@Component
public class AuthRateLimitFilter extends OncePerRequestFilter {

    private static final long WINDOW_MILLIS = TimeUnit.MINUTES.toMillis(1);

    private record Window(long windowStartMillis, AtomicInteger count) {}

    private final int requestsPerMinute;
    private final ObjectMapper json;
    private final Map<String, Window> byIp = new ConcurrentHashMap<>();
    private final ScheduledExecutorService evictor =
            Executors.newSingleThreadScheduledExecutor(runnable -> {
                var thread = new Thread(runnable, "auth-rate-limit-evictor");
                thread.setDaemon(true);
                return thread;
            });

    AuthRateLimitFilter(
            @Value("${hereader.auth-rate-limit.requests-per-minute:10}")
            int requestsPerMinute,
            ObjectMapper json) {
        this.requestsPerMinute = requestsPerMinute;
        this.json = json;
        // Bounds the map to distinct IPs seen in the last two windows rather
        // than to total request volume, or the filter added to prevent a
        // resource-exhaustion attack becomes one itself.
        evictor.scheduleAtFixedRate(
                this::evictExpired, 5, 5, TimeUnit.MINUTES);
    }

    @PreDestroy
    void shutdown() {
        evictor.shutdownNow();
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {

        if (!request.getServletPath().startsWith("/auth")) {
            chain.doFilter(request, response);
            return;
        }

        var now = System.currentTimeMillis();
        var currentWindowStart = now - (now % WINDOW_MILLIS);
        var ip = request.getRemoteAddr();

        var window = byIp.compute(ip, (key, existing) ->
                (existing != null && existing.windowStartMillis() == currentWindowStart)
                        ? existing
                        : new Window(currentWindowStart, new AtomicInteger(0)));

        if (window.count().incrementAndGet() > requestsPerMinute) {
            var retryAfterSeconds =
                    (currentWindowStart + WINDOW_MILLIS - now + 999) / 1000;
            response.setStatus(429);
            response.setHeader("Retry-After", String.valueOf(retryAfterSeconds));
            response.setContentType("application/problem+json");
            var problem = ProblemDetail.forStatus(429);
            problem.setDetail("Too many requests. Try again shortly.");
            json.writeValue(response.getWriter(), problem);
            return;
        }

        chain.doFilter(request, response);
    }

    private void evictExpired() {
        var cutoff = System.currentTimeMillis() - (2 * WINDOW_MILLIS);
        byIp.entrySet().removeIf(entry -> entry.getValue().windowStartMillis() < cutoff);
    }
}
