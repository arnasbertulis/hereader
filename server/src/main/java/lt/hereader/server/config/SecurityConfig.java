package lt.hereader.server.config;

import lt.hereader.server.auth.JwtAuthFilter;
import lt.hereader.server.sync.SyncRequestSizeFilter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
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
            int catalogueSearchRequestsPerMinute) {
        return List.of(
                new RateLimitFilter.PathBudget("/auth", authRequestsPerMinute),
                // Its own budget, scoped to /catalogue/search rather than
                // /catalogue, so covers and downloads (#179) can each carry
                // a different one later without colliding with this one
                // (ADR 0029's amendment to ADR 0026).
                new RateLimitFilter.PathBudget(
                        "/catalogue/search", catalogueSearchRequestsPerMinute));
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

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}