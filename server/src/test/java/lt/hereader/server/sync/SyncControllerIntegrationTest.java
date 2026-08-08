package lt.hereader.server.sync;

import lt.hereader.server.auth.TokenService;
import lt.hereader.server.auth.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.time.Instant;
import java.util.UUID;

import static org.hamcrest.Matchers.hasSize;
import static org.springframework.security.test.web.servlet.setup.SecurityMockMvcConfigurers.springSecurity;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/// End to end through the real filter chain and a real Postgres.
///
/// Sync is the part of this service where a unit test passing means least:
/// the interesting failures are ordering, retries and cross-device races,
/// none of which show up without the database enforcing its constraints.
@SpringBootTest
@ActiveProfiles("test")
class SyncControllerIntegrationTest {

    @Autowired private WebApplicationContext context;
    @Autowired private UserRepository users;
    @Autowired private PasswordEncoder passwords;
    @Autowired private TokenService tokens;

    private MockMvc mvc;
    private String auth;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .apply(springSecurity())
                .build();

        // A fresh user per test, so no test can see another's events.
        var userId = UUID.randomUUID();
        users.create(userId, "sync-" + userId + "@example.com",
                passwords.encode("password123"));

        auth = "Bearer " + tokens.issueAccessToken(userId);
    }

    // -- helpers -------------------------------------------------------

    private static String stamp(long offsetMillis, String device) {
        return "%013d-%05d-%s".formatted(
                Instant.now().toEpochMilli() + offsetMillis, 0, device);
    }

    private static String push(String device, String key, String entityId,
                               int tokenIndex, String hlc) {
        return """
                {
                  "deviceId": "%s",
                  "events": [{
                    "idempotencyKey": "%s",
                    "entityType": "POSITION",
                    "entityId": "%s",
                    "payload": {
                      "blockId": "block-%d",
                      "charOffset": 0,
                      "parserVersion": 1,
                      "tokenIndex": %d
                    },
                    "hlc": "%s",
                    "deleted": false
                  }]
                }
                """.formatted(device, key, entityId, tokenIndex, tokenIndex, hlc);
    }

    private void pushExpectingOk(String body) throws Exception {
        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isOk());
    }

    // -- authentication ------------------------------------------------

    @Test
    void pushingWithoutATokenIsRefused() throws Exception {
        mvc.perform(post("/sync/events")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(push("laptop", "k1", "book-1", 100,
                                stamp(0, "laptop"))))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void pullingWithoutATokenIsRefused() throws Exception {
        mvc.perform(get("/sync/events?since=0"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void oneUserCannotSeeAnotherUsersEvents() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 100, stamp(0, "laptop")));

        var stranger = UUID.randomUUID();
        users.create(stranger, "stranger-" + stranger + "@example.com",
                passwords.encode("password123"));

        mvc.perform(get("/sync/events?since=0")
                        .header("Authorization",
                                "Bearer " + tokens.issueAccessToken(stranger)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.events", hasSize(0)));
    }

    // -- push and pull -------------------------------------------------

    @Test
    void pushedEventsComeBackOnPull() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 100, stamp(0, "laptop")));

        mvc.perform(get("/sync/events?since=0").header("Authorization", auth))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.events", hasSize(1)))
                .andExpect(jsonPath("$.events[0].entityId").value("book-1"))
                .andExpect(jsonPath("$.events[0].seq").value(1))
                .andExpect(jsonPath("$.events[0].payload.tokenIndex").value(100));
    }

    @Test
    void pullingFromASequenceSkipsWhatWasAlreadySeen() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 100, stamp(0, "laptop")));
        pushExpectingOk(push("laptop", "k2", "book-2", 200, stamp(1, "laptop")));

        mvc.perform(get("/sync/events?since=1").header("Authorization", auth))
                .andExpect(jsonPath("$.events", hasSize(1)))
                .andExpect(jsonPath("$.events[0].entityId").value("book-2"));
    }

    @Test
    void aResentBatchIsReportedAsDuplicateRatherThanApplied() throws Exception {
        var body = push("laptop", "k1", "book-1", 100, stamp(0, "laptop"));

        pushExpectingOk(body);

        // Same batch again: a lost response and a correct retry.
        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.accepted").value(0))
                .andExpect(jsonPath("$.duplicates", hasSize(1)))
                .andExpect(jsonPath("$.duplicates[0]").value("k1"));

        mvc.perform(get("/sync/events?since=0").header("Authorization", auth))
                .andExpect(jsonPath("$.events", hasSize(1)));
    }

    // -- ordering ------------------------------------------------------

    @Test
    void aLateArrivingOlderWriteIsLoggedButDoesNotWin() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 500, stamp(0, "laptop")));

        // Written yesterday on a device that was offline until now.
        pushExpectingOk(push("laptop", "k2", "book-1", 10,
                stamp(-86_400_000, "laptop")));

        // Both are history, so both are in the log.
        mvc.perform(get("/sync/events?since=0").header("Authorization", auth))
                .andExpect(jsonPath("$.events", hasSize(2)));

        // The newer write still holds, so no conflict was raised either.
        mvc.perform(get("/sync/conflicts").header("Authorization", auth))
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void aStampFromTheFutureIsRefused() throws Exception {
        // A skewed or hostile device claiming next week would otherwise win
        // every comparison from now on.
        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(push("skewed", "k1", "book-1", 100,
                                stamp(604_800_000L, "skewed"))))
                .andExpect(status().isBadRequest());
    }

    @Test
    void aMalformedStampIsRefused() throws Exception {
        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(push("laptop", "k1", "book-1", 100, "nonsense")))
                .andExpect(status().isBadRequest());
    }

    // -- position divergence -------------------------------------------

    @Test
    void twoDevicesFarApartRaiseAConflict() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 100, stamp(0, "laptop")));

        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(push("phone", "k2", "book-1", 5000,
                                stamp(1000, "phone"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.conflicts", hasSize(1)))
                .andExpect(jsonPath("$.conflicts[0].bookId").value("book-1"))
                .andExpect(jsonPath("$.conflicts[0].ours.tokenIndex").value(100))
                .andExpect(jsonPath("$.conflicts[0].theirs.tokenIndex").value(5000));
    }

    @Test
    void twoDevicesCloseTogetherResolveSilently() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 100, stamp(0, "laptop")));

        // Under the threshold: the same place for practical purposes, and
        // asking the reader about it would be noise.
        pushExpectingOk(push("phone", "k2", "book-1", 300, stamp(1000, "phone")));

        mvc.perform(get("/sync/conflicts").header("Authorization", auth))
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void oneDeviceReadingOnIsNotADivergence() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 100, stamp(0, "laptop")));

        // Same device, far ahead: that is just an afternoon of reading.
        pushExpectingOk(push("laptop", "k2", "book-1", 9000, stamp(1000, "laptop")));

        mvc.perform(get("/sync/conflicts").header("Authorization", auth))
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void aSecondDivergenceOnTheSameBookDoesNotAskTwice() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 100, stamp(0, "laptop")));
        pushExpectingOk(push("phone", "k2", "book-1", 5000, stamp(1000, "phone")));
        pushExpectingOk(push("laptop", "k3", "book-1", 200, stamp(2000, "laptop")));

        // Still one question to answer, not a queue of them.
        mvc.perform(get("/sync/conflicts").header("Authorization", auth))
                .andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void resolvingAConflictClearsIt() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 100, stamp(0, "laptop")));
        pushExpectingOk(push("phone", "k2", "book-1", 5000, stamp(1000, "phone")));

        var conflicts = mvc.perform(get("/sync/conflicts")
                        .header("Authorization", auth))
                .andReturn().getResponse().getContentAsString();

        long id = Long.parseLong(
                conflicts.replaceAll(".*\"id\":\\s*(\\d+).*", "$1"));

        mvc.perform(post("/sync/conflicts/" + id + "/resolve")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "chosen": {"blockId": "block-5000",
                                             "charOffset": 0,
                                             "parserVersion": 1,
                                             "tokenIndex": 5000},
                                  "hlc": "%s",
                                  "deviceId": "laptop"
                                }
                                """.formatted(stamp(2000, "laptop"))))
                .andExpect(status().isNoContent());

        mvc.perform(get("/sync/conflicts").header("Authorization", auth))
                .andExpect(jsonPath("$", hasSize(0)));
    }

    // -- other entities ------------------------------------------------

    @Test
    void preferencesTakeLastWriteWinsWithoutConflicts() throws Exception {
        var body = """
                {
                  "deviceId": "%s",
                  "events": [{
                    "idempotencyKey": "%s",
                    "entityType": "PREFERENCE",
                    "entityId": "theme",
                    "payload": {"value": "%s"},
                    "hlc": "%s",
                    "deleted": false
                  }]
                }
                """;

        pushExpectingOk(body.formatted("laptop", "p1", "dark", stamp(0, "laptop")));
        pushExpectingOk(body.formatted("phone", "p2", "light", stamp(1000, "phone")));

        // A stale font size costs nothing, so nothing is surfaced.
        mvc.perform(get("/sync/conflicts").header("Authorization", auth))
                .andExpect(jsonPath("$", hasSize(0)));
    }

    @Test
    void anUnknownEntityTypeIsRefused() throws Exception {
        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "deviceId": "laptop",
                                  "events": [{
                                    "idempotencyKey": "k1",
                                    "entityType": "NONSENSE",
                                    "entityId": "x",
                                    "payload": {},
                                    "hlc": "%s",
                                    "deleted": false
                                  }]
                                }
                                """.formatted(stamp(0, "laptop"))))
                .andExpect(status().isBadRequest());
    }

    @Test
    void anEmptyBatchIsRefused() throws Exception {
        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"deviceId": "laptop", "events": []}
                                """))
                .andExpect(status().isBadRequest());
    }

    // -- deletions -----------------------------------------------------

    private static String profilePush(String device, String key,
                                      String profileId, String name,
                                      boolean deleted, String hlc) {
        return """
                {
                  "deviceId": "%s",
                  "events": [{
                    "idempotencyKey": "%s",
                    "entityType": "PROFILE",
                    "entityId": "%s",
                    "payload": {
                      "id": "%s",
                      "name": "%s",
                      "pacing": {"kind": "constant", "baseWpm": 250.0},
                      "presentation": {"fontSizePt": 44.0},
                      "rewindWords": 2
                    },
                    "hlc": "%s",
                    "deleted": %b
                  }]
                }
                """.formatted(device, key, profileId, profileId, name, hlc, deleted);
    }

    @Test
    void aDeletionComesBackFromPullAsATombstone() throws Exception {
        pushExpectingOk(profilePush("laptop", "k1", "p.1", "Mine", false,
                stamp(0, "laptop")));
        pushExpectingOk(profilePush("laptop", "k2", "p.1", "Mine", true,
                stamp(1000, "laptop")));

        // The log is what devices pull. A deletion recorded only in
        // entity_state would arrive here as an ordinary write carrying the
        // profile's last payload, and every pulling device would write it
        // back as live.
        mvc.perform(get("/sync/events?since=0").header("Authorization", auth))
                .andExpect(jsonPath("$.events", hasSize(2)))
                .andExpect(jsonPath("$.events[0].deleted").value(false))
                .andExpect(jsonPath("$.events[1].deleted").value(true))
                // The whole profile travels, so a device that never received
                // the create can still write a complete tombstone row.
                .andExpect(jsonPath("$.events[1].payload.name").value("Mine"));
    }

    @Test
    void anOrdinaryWriteComesBackUndeleted() throws Exception {
        pushExpectingOk(push("laptop", "k1", "book-1", 100, stamp(0, "laptop")));

        mvc.perform(get("/sync/events?since=0").header("Authorization", auth))
                .andExpect(jsonPath("$.events[0].deleted").value(false));
    }

    @Test
    void eachEventInABatchCarriesItsOwnFlag() throws Exception {
        pushExpectingOk("""
                {
                  "deviceId": "laptop",
                  "events": [
                    {
                      "idempotencyKey": "k1",
                      "entityType": "PROFILE",
                      "entityId": "p.kept",
                      "payload": {"id": "p.kept", "name": "Kept"},
                      "hlc": "%s",
                      "deleted": false
                    },
                    {
                      "idempotencyKey": "k2",
                      "entityType": "PROFILE",
                      "entityId": "p.gone",
                      "payload": {"id": "p.gone", "name": "Gone"},
                      "hlc": "%s",
                      "deleted": true
                    }
                  ]
                }
                """.formatted(stamp(0, "laptop"), stamp(1, "laptop")));

        mvc.perform(get("/sync/events?since=0").header("Authorization", auth))
                .andExpect(jsonPath("$.events", hasSize(2)))
                .andExpect(jsonPath("$.events[0].entityId").value("p.kept"))
                .andExpect(jsonPath("$.events[0].deleted").value(false))
                .andExpect(jsonPath("$.events[1].entityId").value("p.gone"))
                .andExpect(jsonPath("$.events[1].deleted").value(true));
    }
}
