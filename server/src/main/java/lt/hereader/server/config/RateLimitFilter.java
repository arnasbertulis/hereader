package lt.hereader.server.config;

import tools.jackson.databind.ObjectMapper;
import jakarta.annotation.PreDestroy;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.ProblemDetail;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/// Caps requests under a configured set of path prefixes to a fixed number
/// per minute per client IP. Each prefix carries its own budget and its own
/// tracking map, so exhausting one path's budget from an IP has no effect on
/// that IP's access to another configured path. A request whose path matches
/// none of them passes through unlimited.
///
/// Reads `getRemoteAddr()`, which only resolves to the real caller because
/// `server.forward-headers-strategy=framework` (`application.properties`)
/// makes Spring translate `X-Forwarded-For` before this filter runs; without
/// it every caller behind Caddy shares the Docker bridge address and would be
/// throttled as one client.
@Component
public class RateLimitFilter extends OncePerRequestFilter {

    private static final long WINDOW_MILLIS = TimeUnit.MINUTES.toMillis(1);

    /// One entry in the configured budget list — see `SecurityConfig` for
    /// where the list is assembled.
    public record PathBudget(String pathPrefix, int requestsPerMinute) {}

    private record Window(long windowStartMillis, AtomicInteger count) {}

    private record TrackedBudget(PathBudget budget, Map<String, Window> byIp) {}

    private final ObjectMapper json;
    private final List<TrackedBudget> budgets;
    private final ScheduledExecutorService evictor =
            Executors.newSingleThreadScheduledExecutor(runnable -> {
                var thread = new Thread(runnable, "rate-limit-evictor");
                thread.setDaemon(true);
                return thread;
            });

    RateLimitFilter(List<PathBudget> pathBudgets, ObjectMapper json) {
        this.budgets = pathBudgets.stream()
                .map(budget -> new TrackedBudget(budget, new ConcurrentHashMap<String, Window>()))
                .toList();
        this.json = json;
        // Bounds each budget's map to distinct IPs seen in the last two
        // windows rather than to total request volume, or the filter added
        // to prevent a resource-exhaustion attack becomes one itself.
        evictor.scheduleAtFixedRate(this::evictExpired, 5, 5, TimeUnit.MINUTES);
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

        var path = request.getServletPath();
        var budget = budgets.stream()
                .filter(candidate -> path.startsWith(candidate.budget().pathPrefix()))
                .findFirst()
                .orElse(null);

        if (budget == null) {
            chain.doFilter(request, response);
            return;
        }

        var now = System.currentTimeMillis();
        var currentWindowStart = now - (now % WINDOW_MILLIS);
        var ip = request.getRemoteAddr();

        var window = budget.byIp().compute(ip, (key, existing) ->
                (existing != null && existing.windowStartMillis() == currentWindowStart)
                        ? existing
                        : new Window(currentWindowStart, new AtomicInteger(0)));

        if (window.count().incrementAndGet() > budget.budget().requestsPerMinute()) {
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
        for (var budget : budgets) {
            budget.byIp().entrySet().removeIf(
                    entry -> entry.getValue().windowStartMillis() < cutoff);
        }
    }
}
