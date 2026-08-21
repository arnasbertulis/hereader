package lt.hereader.server.auth;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.util.UUID;

import static org.hamcrest.Matchers.notNullValue;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/// Runs the real filter chain against the real database.
///
/// Auth is exactly the kind of thing where a unit test can pass while the
/// wiring is wrong: a filter registered in the wrong order, or a permitAll
/// rule that does not match, only shows up through the whole stack.
@SpringBootTest
@ActiveProfiles("test")
class AuthControllerIntegrationTest {

    @Autowired
    private WebApplicationContext context;

    private MockMvc mvc;

    private MockMvc mvc() {
        if (mvc == null) {
            mvc = MockMvcBuilders.webAppContextSetup(context)
                    .apply(springSecurity())
                    .build();
        }
        return mvc;
    }

    /// Unique per test so cases cannot interfere through shared rows.
    private static String freshEmail() {
        return "user-" + UUID.randomUUID() + "@example.com";
    }

    private static String credentials(String email, String password) {
        return """
                {"email": "%s", "password": "%s"}
                """.formatted(email, password);
    }

    @Test
    void registeringReturnsBothTokens() throws Exception {
        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(freshEmail(), "password123")))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.accessToken").value(notNullValue()))
                .andExpect(jsonPath("$.refreshToken").value(notNullValue()));
    }

    @Test
    void registeringTheSameEmailTwiceConflicts() throws Exception {
        var email = freshEmail();
        var body = credentials(email, "password123");

        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isCreated());

        // 409, not 403: the client needs to tell "that email is taken" apart
        // from "you are not allowed here" to show a useful message.
        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isConflict());
    }

    @Test
    void emailIsNormalisedBeforeItIsStored() throws Exception {
        var email = freshEmail();

        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(email, "password123")))
                .andExpect(status().isCreated());

        // Same address, different case: still the same account.
        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(email.toUpperCase(), "password123")))
                .andExpect(status().isConflict());
    }

    @Test
    void loginReturnsTokensForCorrectCredentials() throws Exception {
        var email = freshEmail();

        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(email, "password123")))
                .andExpect(status().isCreated());

        mvc().perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(email, "password123")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").value(notNullValue()));
    }

    @Test
    void aWrongPasswordAndAnUnknownEmailAreIndistinguishable() throws Exception {
        var email = freshEmail();

        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(email, "password123")))
                .andExpect(status().isCreated());

        var wrongPassword = mvc().perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(email, "wrongpassword")))
                .andExpect(status().isUnauthorized())
                .andReturn().getResponse().getContentAsString();

        var unknownEmail = mvc().perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(freshEmail(), "password123")))
                .andExpect(status().isUnauthorized())
                .andReturn().getResponse().getContentAsString();

        // Identical responses, or the endpoint becomes a way to find out
        // which addresses are registered.
        org.assertj.core.api.Assertions.assertThat(wrongPassword)
                .isEqualTo(unknownEmail);
    }

    @Test
    void aRefreshTokenBuysANewPair() throws Exception {
        var email = freshEmail();

        var registered = mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(email, "password123")))
                .andReturn().getResponse().getContentAsString();

        var refreshToken = com.fasterxml.jackson.databind.json.JsonMapper
                .builder().build()
                .readTree(registered)
                .get("refreshToken").asText();

        mvc().perform(post("/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"refreshToken": "%s"}
                                """.formatted(refreshToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accessToken").value(notNullValue()));
    }

    @Test
    void anAccessTokenIsRefusedAtTheRefreshEndpoint() throws Exception {
        var email = freshEmail();

        var registered = mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(email, "password123")))
                .andReturn().getResponse().getContentAsString();

        var accessToken = com.fasterxml.jackson.databind.json.JsonMapper
                .builder().build()
                .readTree(registered)
                .get("accessToken").asText();

        mvc().perform(post("/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"refreshToken": "%s"}
                                """.formatted(accessToken)))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void aShortPasswordIsRejected() throws Exception {
        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials(freshEmail(), "short")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.detail").value(notNullValue()));
    }

    @Test
    void aNonEmailAddressIsRejected() throws Exception {
        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(credentials("not-an-email", "password123")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.detail").value(notNullValue()));
    }

    @Test
    void nullEmailAndPasswordAreBadRequestNotAServerError() throws Exception {
        mvc().perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email": null, "password": null}
                                """))
                .andExpect(status().isBadRequest());
    }

    @Test
    void healthIsReachableWithoutAToken() throws Exception {
        mvc().perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("ok"));
    }

    @Test
    void aMalformedTokenDoesNotBreakTheFilter() throws Exception {
        mvc().perform(get("/health")
                        .header("Authorization", "Bearer not-a-real-token"))
                .andExpect(status().isOk());
    }
}
