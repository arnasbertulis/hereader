// Throwaway comment: measuring server-only CI wall clock for ADR 0009 (#224).
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
    private static final String VERSION_CLAIM = "ver";
    private static final String ACCESS = "access";
    private static final String REFRESH = "refresh";

    /// The user id and the token_version a refresh token was issued under,
    /// read back from its `ver` claim. `/auth/refresh` compares this against
    /// the user's current value so a logout (ADR 0027) can invalidate it.
    public record RefreshTokenInfo(UUID userId, long tokenVersion) {}

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
        return issue(userId, ACCESS, accessLifetime, null);
    }

    /// Long-lived on purpose. A reading app that logs you out weekly is
    /// worse than one that trusts a device for two months. Carries the
    /// version it was issued under so a later logout can invalidate it
    /// without a revocation table (ADR 0027).
    public String issueRefreshToken(UUID userId, long tokenVersion) {
        return issue(userId, REFRESH, refreshLifetime, tokenVersion);
    }

    private String issue(UUID userId, String type, Duration lifetime, Long tokenVersion) {
        var now = Instant.now();

        var builder = Jwts.builder()
                .subject(userId.toString())
                .claim(TYPE_CLAIM, type)
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(lifetime)));

        if (tokenVersion != null) {
            builder.claim(VERSION_CLAIM, tokenVersion);
        }

        return builder.signWith(key).compact();
    }

    /// The user id in a valid access token, or null if the token is
    /// unusable for any reason: bad signature, expired, or a refresh token
    /// presented where an access token belongs.
    ///
    /// Returns null rather than throwing because every failure means the
    /// same thing to the caller, and distinguishing them in a response
    /// tells an attacker which part of their forgery was wrong.
    public UUID userIdFromAccessToken(String token) {
        var claims = claims(token, ACCESS);
        return claims == null ? null : UUID.fromString(claims.getSubject());
    }

    /// The user id and token_version a refresh token was issued under, or
    /// null if the token is unusable for any reason: bad signature, expired,
    /// wrong type, or (a token issued before this claim existed) missing the
    /// version claim entirely.
    public RefreshTokenInfo refreshTokenInfo(String token) {
        var claims = claims(token, REFRESH);
        if (claims == null) {
            return null;
        }

        Long version = claims.get(VERSION_CLAIM, Long.class);
        if (version == null) {
            return null;
        }

        return new RefreshTokenInfo(UUID.fromString(claims.getSubject()), version);
    }

    private Claims claims(String token, String expectedType) {
        try {
            Claims claims = Jwts.parser()
                    .verifyWith(key)
                    .build()
                    .parseSignedClaims(token)
                    .getPayload();

            if (!expectedType.equals(claims.get(TYPE_CLAIM, String.class))) {
                return null;
            }
            return claims;

        } catch (JwtException | IllegalArgumentException e) {
            return null;
        }
    }
}