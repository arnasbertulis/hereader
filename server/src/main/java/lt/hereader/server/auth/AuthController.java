package lt.hereader.server.auth;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.Locale;
import java.util.UUID;

@RestController
@RequestMapping("/auth")
class AuthController {

    record Credentials(
            @Email @NotBlank String email,
            @NotBlank @Size(min = 8, max = 200) String password) {}

    record RefreshRequest(@NotBlank String refreshToken) {}

    record Tokens(String accessToken, String refreshToken) {}

    private final UserRepository users;
    private final PasswordEncoder passwords;
    private final TokenService tokens;

    /// A bcrypt hash of a fixed string, encoded once at startup with the same
    /// encoder as real passwords, so the unknown-email path in `login` can pay
    /// the same cost as a real comparison instead of returning early.
    private final String dummyHash;

    AuthController(UserRepository users, PasswordEncoder passwords,
                   TokenService tokens) {
        this.users = users;
        this.passwords = passwords;
        this.tokens = tokens;
        this.dummyHash = passwords.encode("timing-side-channel-dummy");
    }

    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    Tokens register(@Valid @RequestBody Credentials body) {
        var email = normalise(body.email());

        if (users.findByEmail(email).isPresent()) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "That email is already registered.");
        }

        var user = users.create(
                UUID.randomUUID(), email, passwords.encode(body.password()));

        return issueFor(user.id(), user.tokenVersion());
    }

    @PostMapping("/login")
    Tokens login(@Valid @RequestBody Credentials body) {
        var user = users.findByEmail(normalise(body.email()));

        if (user.isEmpty()) {
            // Pay the same bcrypt cost as a real comparison would, so an
            // unknown email cannot be told apart from a wrong password by
            // response time.
            passwords.matches(body.password(), dummyHash);
            throw badCredentials();
        }

        if (!passwords.matches(body.password(), user.get().passwordHash())) {
            throw badCredentials();
        }
        return issueFor(user.get().id(), user.get().tokenVersion());
    }

    /// Trades a refresh token for a new pair, so a device that has not been
    /// opened in weeks does not force the reader to log in again. Rejects a
    /// token whose version claim no longer matches the user's current
    /// value — the effect of a logout (ADR 0027).
    @PostMapping("/refresh")
    Tokens refresh(@Valid @RequestBody RefreshRequest body) {
        var info = tokens.refreshTokenInfo(body.refreshToken());
        if (info == null) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "That token is not usable.");
        }

        var user = users.findById(info.userId());
        if (user.isEmpty() || user.get().tokenVersion() != info.tokenVersion()) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "That token is not usable.");
        }
        return issueFor(user.get().id(), user.get().tokenVersion());
    }

    /// Invalidates every refresh token issued for the caller, on every
    /// device, from this moment on (ADR 0027). An access token already in
    /// hand keeps working until it expires on its own.
    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    void logout(@AuthenticationPrincipal UUID userId) {
        if (userId == null) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "That token is not usable.");
        }
        users.bumpTokenVersion(userId);
    }

    private Tokens issueFor(UUID userId, long tokenVersion) {
        return new Tokens(
                tokens.issueAccessToken(userId),
                tokens.issueRefreshToken(userId, tokenVersion));
    }

    /// One message for both "no such user" and "wrong password". Telling
    /// them apart would let someone enumerate which emails are registered.
    private static ResponseStatusException badCredentials() {
        return new ResponseStatusException(
                HttpStatus.UNAUTHORIZED, "Email or password is incorrect.");
    }

    private static String normalise(String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }
}