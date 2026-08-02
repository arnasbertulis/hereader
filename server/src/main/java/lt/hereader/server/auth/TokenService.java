package lt.hereader.server.auth;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

/// Issues and validates the service's own tokens.
///
/// Deliberately not delegating to Firebase or Google as the token issuer:
/// keeping issuance here means a social login can be added later purely as
/// an identity source, without reworking how the API authenticates.
@Service
public class TokenService {

    private static final String TYPE_CLAIM = "typ";
    private static final String ACCESS = "access";
    private static final String REFRESH = "refresh";

    private final SecretKey key;
    private final Duration accessLifetime;
    private final Duration refreshLifetime;

    TokenService(
            @Value("${hereader.jwt.secret}") String secret,
            @Value("${hereader.jwt.access-token-minutes}") long accessMinutes,
            @Value("${hereader.jwt.refresh-token-days}") long refreshDays) {

        var bytes = secret.getBytes(StandardCharsets.UTF_8);
        if (bytes.length < 32) {
            throw new IllegalStateException(
                    "JWT_SECRET must be at least 32 bytes for HS256");
        }

        this.key = Keys.hmacShaKeyFor(bytes);
        this.accessLifetime = Duration.ofMinutes(accessMinutes);
        this.refreshLifetime = Duration.ofDays(refreshDays);
    }

    public String issueAccessToken(UUID userId) {
        return issue(userId, ACCESS, accessLifetime);
    }

    /// Long-lived on purpose. A reading app that logs you out weekly is
    /// worse than one that trusts a device for two months.
    public String issueRefreshToken(UUID userId) {
        return issue(userId, REFRESH, refreshLifetime);
    }

    private String issue(UUID userId, String type, Duration lifetime) {
        var now = Instant.now();

        return Jwts.builder()
                .subject(userId.toString())
                .claim(TYPE_CLAIM, type)
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(lifetime)))
                .signWith(key)
                .compact();
    }

    /// The user id in a valid access token, or null if the token is
    /// unusable for any reason: bad signature, expired, or a refresh token
    /// presented where an access token belongs.
    ///
    /// Returns null rather than throwing because every failure means the
    /// same thing to the caller, and distinguishing them in a response
    /// tells an attacker which part of their forgery was wrong.
    public UUID userIdFromAccessToken(String token) {
        return userId(token, ACCESS);
    }

    public UUID userIdFromRefreshToken(String token) {
        return userId(token, REFRESH);
    }

    private UUID userId(String token, String expectedType) {
        try {
            Claims claims = Jwts.parser()
                    .verifyWith(key)
                    .build()
                    .parseSignedClaims(token)
                    .getPayload();

            if (!expectedType.equals(claims.get(TYPE_CLAIM, String.class))) {
                return null;
            }
            return UUID.fromString(claims.getSubject());

        } catch (JwtException | IllegalArgumentException e) {
            return null;
        }
    }
}