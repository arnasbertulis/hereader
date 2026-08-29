package lt.hereader.server.config;

import lt.hereader.server.auth.JwtAuthFilter;
import lt.hereader.server.sync.SyncRequestSizeFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.intercept.AuthorizationFilter;
import org.springframework.http.HttpStatus;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.List;

@Configuration
class SecurityConfig {

    // Comma-separated. Defaults cover local Flutter web dev (random port
    // per run, hence the wildcard) and the live sslip.io deployment.
    // Overridable via env var so a future real domain doesn't need a
    // code change, just a new value in .env.
    @Value("${hereader.cors.allowed-origins:http://localhost:*,https://204-168-240-12.sslip.io}")
    private String allowedOrigins;

    @Bean
    List<RateLimitFilter.PathBudget> rateLimitBudgets(
            @Value("${hereader.auth-rate-limit.requests-per-minute:10}")
            int authRequestsPerMinute,
            @Value("${hereader.catalogue-search-rate-limit.requests-per-minute:60}")
            int catalogueSearchRequestsPerMinute,
            // The browse screen's filter list, not a page of results — one
            // request per screen open rather than one per search keystroke,
            // and the result set changes only on a weekly ingestion refresh.
            // Sits above search's budget for that reason, but below cover's,
            // since it is one call per browse rather than one per book.
            @Value("${hereader.catalogue-categories-rate-limit.requests-per-minute:120}")
            int catalogueCategoriesRequestsPerMinute,
            // Same reasoning as categories' budget above — one request per
            // browse-screen open, refreshed only on the weekly ingestion run.
            @Value("${hereader.catalogue-languages-rate-limit.requests-per-minute:120}")
            int catalogueLanguagesRequestsPerMinute,
            // One flick of a browse grid is dozens of cover requests at
            // once, so this budget sits well above search's (ADR 0029's
            // amendment to ADR 0026).
            @Value("${hereader.catalogue-cover-rate-limit.requests-per-minute:300}")
            int catalogueCoverRequestsPerMinute,
            // Ten downloads a minute is already generous for one reader
            // (ADR 0029) — this is the tightest of the four budgets, since
            // every hit is a full Gutenberg fetch rather than a local query.
            @Value("${hereader.catalogue-download-rate-limit.requests-per-minute:10}")
            int catalogueDownloadRequestsPerMinute) {
        return List.of(
                new RateLimitFilter.PathBudget("/auth", authRequestsPerMinute),
                // Its own budget, scoped to /catalogue/search rather than
                // /catalogue, so covers and downloads (#179) can each carry
                // a different one later without colliding with this one
                // (ADR 0029's amendment to ADR 0026).
                new RateLimitFilter.PathBudget(
                        "/catalogue/search", catalogueSearchRequestsPerMinute),
                new RateLimitFilter.PathBudget(
                        "/catalogue/categories", catalogueCategoriesRequestsPerMinute),
                new RateLimitFilter.PathBudget(
                        "/catalogue/languages", catalogueLanguagesRequestsPerMinute),
                new RateLimitFilter.PathBudget(
                        "/catalogue/cover", catalogueCoverRequestsPerMinute),
                new RateLimitFilter.PathBudget(
                        "/catalogue/download", catalogueDownloadRequestsPerMinute));
    }

    @Bean
    SecurityFilterChain filterChain(
            HttpSecurity http,
            RateLimitFilter rateLimit,
            JwtAuthFilter jwt,
            SyncRequestSizeFilter sizeLimit)
            throws Exception {
        return http
                .csrf(csrf -> csrf.disable())
                .cors(cors -> cors.configurationSource(corsConfigurationSource()))
                .sessionManagement(s ->
                        s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(
                                new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/health", "/auth/**", "/catalogue/**").permitAll()
                        .anyRequest().authenticated())
                .addFilterBefore(jwt, AuthorizationFilter.class)
                .addFilterBefore(rateLimit, JwtAuthFilter.class)
                // Anchored to rateLimit rather than jwt directly for the
                // same reason PR4 anchors rateLimit to jwt: a custom filter
                // class only works as an anchor once it is already in the
                // chain, and rateLimit was added last above.
                .addFilterBefore(sizeLimit, RateLimitFilter.class)
                .build();
    }

    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOriginPatterns(List.of(allowedOrigins.split(",")));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("Authorization", "Content-Type"));

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }

    // The test profile supplies its own, spy-wrapped instance (see
    // lt.hereader.server.config.TestPasswordEncoderConfig) so
    // AuthControllerIntegrationTest can verify encoder calls without a
    // @MockitoSpyBean override forking the test context's cache key (#231).
    @Bean
    @Profile("!test")
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}