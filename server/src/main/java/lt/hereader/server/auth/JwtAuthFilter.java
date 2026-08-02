package lt.hereader.server.auth;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/// Reads the bearer token on every request and, if it is valid, tells Spring
/// Security who the caller is.
///
/// Does not reject anything itself. An unauthenticated request simply passes
/// through with no authentication set, and the security config decides
/// whether that endpoint allows it.
@Component
public class JwtAuthFilter extends OncePerRequestFilter {

    private final TokenService tokens;

    JwtAuthFilter(TokenService tokens) {
        this.tokens = tokens;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {

        var header = request.getHeader("Authorization");

        if (header != null && header.startsWith("Bearer ")) {
            var userId = tokens.userIdFromAccessToken(header.substring(7));

            if (userId != null) {
                var auth = new UsernamePasswordAuthenticationToken(
                        userId, null, List.of());
                SecurityContextHolder.getContext().setAuthentication(auth);
            }
        }

        chain.doFilter(request, response);
    }
}