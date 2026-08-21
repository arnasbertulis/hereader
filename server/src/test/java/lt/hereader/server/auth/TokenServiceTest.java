package lt.hereader.server.auth;

import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/// Plain unit tests: no Spring context, so the whole class runs in
/// milliseconds. Anything that needs a database lives in the integration
/// tests instead.
class TokenServiceTest {

    private static final String SECRET =
            "a-test-secret-that-is-comfortably-longer-than-32-bytes";

    private final TokenService tokens = new TokenService(SECRET, 60, 60);

    @Test
    void accessTokenCarriesTheUserId() {
        var userId = UUID.randomUUID();

        var token = tokens.issueAccessToken(userId);

        assertThat(tokens.userIdFromAccessToken(token)).isEqualTo(userId);
    }

    @Test
    void refreshTokenCarriesTheUserIdAndVersion() {
        var userId = UUID.randomUUID();

        var token = tokens.issueRefreshToken(userId, 3L);

        var info = tokens.refreshTokenInfo(token);
        assertThat(info.userId()).isEqualTo(userId);
        assertThat(info.tokenVersion()).isEqualTo(3L);
    }

    @Test
    void aRefreshTokenIsNotAcceptedWhereAnAccessTokenBelongs() {
        // Without the type claim this would pass, and every session would
        // quietly last as long as the refresh window.
        var token = tokens.issueRefreshToken(UUID.randomUUID(), 0L);

        assertThat(tokens.userIdFromAccessToken(token)).isNull();
    }

    @Test
    void anAccessTokenIsNotAcceptedWhereARefreshTokenBelongs() {
        var token = tokens.issueAccessToken(UUID.randomUUID());

        assertThat(tokens.refreshTokenInfo(token)).isNull();
    }

    @Test
    void aTokenSignedWithAnotherSecretIsRejected() {
        var other = new TokenService(
                "a-different-secret-that-is-also-long-enough-to-work", 60, 60);

        var forged = other.issueAccessToken(UUID.randomUUID());

        assertThat(tokens.userIdFromAccessToken(forged)).isNull();
    }

    @Test
    void anExpiredTokenIsRejected() {
        // Zero lifetime: the token is already past its expiry when issued.
        var expiring = new TokenService(SECRET, 0, 0);

        var token = expiring.issueAccessToken(UUID.randomUUID());

        assertThat(expiring.userIdFromAccessToken(token)).isNull();
    }

    @Test
    void aTamperedTokenIsRejected() {
        var token = tokens.issueAccessToken(UUID.randomUUID());

        // Flip a character in the payload. The signature no longer matches.
        var parts = token.split("\\.");
        var tampered = parts[0] + "." + parts[1].substring(1) + "x." + parts[2];

        assertThat(tokens.userIdFromAccessToken(tampered)).isNull();
    }

    @Test
    void garbageIsRejectedRatherThanThrowing() {
        // The filter runs this on every request, including ones carrying
        // whatever a scanner decided to send.
        assertThat(tokens.userIdFromAccessToken("garbage")).isNull();
        assertThat(tokens.userIdFromAccessToken("")).isNull();
        assertThat(tokens.userIdFromAccessToken("a.b.c")).isNull();
    }

    @Test
    void aShortSecretIsRefusedAtStartup() {
        // Failing to start is the right response: a service signing tokens
        // with a weak key is worse than one that is down.
        assertThatThrownBy(() -> new TokenService("too-short", 60, 60))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("32 bytes");
    }

    @Test
    void twoTokensForTheSameUserAreBothValid() {
        // Issuance is stateless, so logging in on a second device does not
        // invalidate the first.
        var userId = UUID.randomUUID();

        var first = tokens.issueAccessToken(userId);
        var second = tokens.issueAccessToken(userId);

        assertThat(tokens.userIdFromAccessToken(first)).isEqualTo(userId);
        assertThat(tokens.userIdFromAccessToken(second)).isEqualTo(userId);
    }
}
