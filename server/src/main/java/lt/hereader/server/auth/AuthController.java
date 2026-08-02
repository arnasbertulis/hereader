package lt.hereader.server.auth;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
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

    AuthController(UserRepository users, PasswordEncoder passwords,
                   TokenService tokens) {
        this.users = users;
        this.passwords = passwords;
        this.tokens = tokens;
    }

    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    Tokens register(@RequestBody Credentials body) {
        var email = normalise(body.email());

        if (users.findByEmail(email).isPresent()) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "That email is already registered.");
        }

        var user = users.create(
                UUID.randomUUID(), email, passwords.encode(body.password()));

        return issueFor(user.id());
    }

    @PostMapping("/login")
    Tokens login(@RequestBody Credentials body) {
        var user = users.findByEmail(normalise(body.email()))
                .orElseThrow(AuthController::badCredentials);

        if (!passwords.matches(body.password(), user.passwordHash())) {
            throw badCredentials();
        }
        return issueFor(user.id());
    }

    /// Trades a refresh token for a new pair, so a device that has not been
    /// opened in weeks does not force the reader to log in again.
    @PostMapping("/refresh")
    Tokens refresh(@RequestBody RefreshRequest body) {
        var userId = tokens.userIdFromRefreshToken(body.refreshToken());

        if (userId == null || !users.exists(userId)) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "That token is not usable.");
        }
        return issueFor(userId);
    }

    private Tokens issueFor(UUID userId) {
        return new Tokens(
                tokens.issueAccessToken(userId),
                tokens.issueRefreshToken(userId));
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