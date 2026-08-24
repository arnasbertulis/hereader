package lt.hereader.server.sync;

import lt.hereader.server.auth.TokenService;
import lt.hereader.server.auth.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
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
    @Autowired private SyncRepository repository;
    @Autowired private JdbcClient jdbc;

    private MockMvc mvc;
    private String auth;
    private UUID userId;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.webAppContextSetup(context)
                .apply(springSecurity())
                .build();

        // A fresh user per test, so no test can see another's events.
        userId = UUID.randomUUID();
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

    // -- conflict uniqueness --------------------------------------------

    @Test
    void theIndexRefusesASecondUnresolvedConflictForTheSameBook() {
        var payload = Map.<String, Object>of("tokenIndex", 100);
        repository.recordConflict(userId, "book-1", payload, payload);

        // Goes around recordConflict's `where not exists` on purpose. That
        // guard is the thing a race gets past, so a second call through it
        // proves only that the guard works when nothing is racing. What V5
        // added is the index underneath, and this is the assertion that
        // fails if the migration is reverted: with V2's
        // `unique (user_id, book_id, resolved_at)`, NULLs being distinct,
        // this insert succeeds.
        assertThatThrownBy(() -> insertConflictDirectly(userId, "book-1"))
                .isInstanceOf(DuplicateKeyException.class);
    }

    @Test
    void aResolvedConflictDoesNotBlockTheNextOneForTheSameBook() {
        var payload = Map.<String, Object>of("tokenIndex", 100);
        repository.recordConflict(userId, "book-1", payload, payload);
        repository.resolveConflict(
                userId, repository.unresolvedConflicts(userId).getFirst().id());

        // The index is partial for this reason: a book the reader has
        // already settled once can diverge again. A plain unique constraint
        // on (user_id, book_id) would forbid it.
        repository.recordConflict(userId, "book-1", payload, payload);

        assertThat(repository.unresolvedConflicts(userId)).hasSize(1);
    }

    private void insertConflictDirectly(UUID userId, String bookId) {
        jdbc.sql("""
                insert into position_conflicts (user_id, book_id, ours, theirs)
                values (:userId, :bookId, cast('{}' as jsonb),
                        cast('{}' as jsonb))
                """)
                .param("userId", userId)
                .param("bookId", bookId)
                .update();
    }

    // recordConflict's own `where not exists` is a check-then-insert that
    // races under read committed. Sequential calls, as above, cannot show
    // that: this drives real concurrent transactions at
    // position_conflicts_one_unresolved_per_book (V5). It is deliberately
    // kept alongside the deterministic test above rather than instead of
    // it — eight threads may or may not interleave badly on a given run,
    // so it can pass against a schema the test above proves is wrong.
    @Test
    void concurrentConflictsForTheSameBookLeaveExactlyOneUnresolvedRow()
            throws Exception {

        var payload = Map.<String, Object>of("tokenIndex", 100);
        Callable<Void> attempt = () -> {
            repository.recordConflict(userId, "book-1", payload, payload);
            return null;
        };

        ExecutorService pool = Executors.newFixedThreadPool(8);
        try {
            List<Future<Void>> attempts = pool.invokeAll(
                    List.of(attempt, attempt, attempt, attempt,
                            attempt, attempt, attempt, attempt));
            for (Future<Void> attemptResult : attempts) {
                attemptResult.get(5, TimeUnit.SECONDS);
            }
        } finally {
            pool.shutdown();
        }

        assertThat(repository.unresolvedConflicts(userId)).hasSize(1);
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
    void aNullEntityTypeIsRefused() throws Exception {
        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "deviceId": "laptop",
                                  "events": [{
                                    "idempotencyKey": "k1",
                                    "entityType": null,
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

    // -- request size ----------------------------------------------------

    @Test
    void anOversizedPushIsRejectedBeforeItIsParsed() throws Exception {
        // Not valid JSON: SyncRequestSizeFilter checks Content-Length before
        // the body ever reaches Jackson, so the content need not parse.
        var oversized = new byte[(int) SyncRequestSizeFilter.MAX_PUSH_REQUEST_BYTES + 1];

        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(oversized))
                .andExpect(status().isPayloadTooLarge());
    }

    // -- payload size ----------------------------------------------------

    /// [rawJsonValue] is spliced in unquoted, so a case can send a string or
    /// an array and put `Map.toString()` and the encoded JSON on either side
    /// of the cap.
    private static String payloadPush(String rawJsonValue, String hlc) {
        return """
                {
                  "deviceId": "laptop",
                  "events": [{
                    "idempotencyKey": "k1",
                    "entityType": "PREFERENCE",
                    "entityId": "note",
                    "payload": {"value": %s},
                    "hlc": "%s",
                    "deleted": false
                  }]
                }
                """.formatted(rawJsonValue, hlc);
    }

    private static String jsonString(String value) {
        return '"' + value.replace("\"", "\\\"") + '"';
    }

    @Test
    void aPayloadIsMeasuredAsEncodedJsonRatherThanAsToString() throws Exception {
        // 4,200 quote characters. Map.toString() writes them as themselves,
        // reaching 4,208 characters and passing the 8,192 cap; JSON escapes
        // every one of them to \", reaching 8,412 and failing it. A cap
        // measuring toString() accepts this payload, which is the bug.
        var body = payloadPush(jsonString("\"".repeat(4_200)), stamp(0, "laptop"));

        mvc.perform(post("/sync/events")
                        .header("Authorization", auth)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isPayloadTooLarge());
    }

    @Test
    void aPayloadOverTheCapOnlyByToStringIsAccepted() throws Exception {
        // The same divergence in the other direction, which is the half a
        // one-sided test misses: 3,000 single-digit numbers render as
        // "[1, 1, ...]" under toString() for 9,008 characters, over the cap,
        // and as "[1,1,...]" in JSON for 6,011, under it. A cap measuring
        // toString() rejects a payload the wire format has room for.
        var array = "[" + "1,".repeat(2_999) + "1]";

        pushExpectingOk(payloadPush(array, stamp(0, "laptop")));
    }

    @Test
    void aPayloadUnderTheEncodedCharacterCapIsAccepted() throws Exception {
        pushExpectingOk(payloadPush(jsonString("a".repeat(100)),
                stamp(0, "laptop")));
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
