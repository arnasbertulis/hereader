# server

The sync service for hereader. Spring Boot 4.1 on Java 25, Postgres, no ORM.

Stores reading positions, profiles and preferences. Never book files: those
stay on the reader's device, which is a privacy decision and a licensing one.
See [ADR 0004](../docs/adr/0004-store-book-files.md).

## Running it

Needs JDK 25 and a Postgres. The Maven wrapper handles everything else.

```bash
docker run --name hereader-db -e POSTGRES_PASSWORD=dev \
  -e POSTGRES_DB=hereader -p 5432:5432 -d postgres:17
```

The service refuses to start without a signing secret. That is deliberate: a
placeholder secret that ships in a repository is worse than a service that is
down, because anyone reading the repository could mint a token for any user.

```bash
export JWT_SECRET=$(head -c 48 /dev/urandom | base64)
./mvnw spring-boot:run
```

On Windows, set `JWT_SECRET` in the IntelliJ run configuration instead.

Flyway applies the schema on first start. `GET /health` reports whether the
service can reach its database rather than merely whether the process is
alive, because a health check that always answers ok makes a broken deploy
look healthy.

## Configuration

Every value reads from the environment with a development default, except the
signing secret, which has none.

| Variable | Default | |
|---|---|---|
| `DATABASE_URL` | `jdbc:postgresql://localhost:5432/hereader` | |
| `DATABASE_USER` | `postgres` | |
| `DATABASE_PASSWORD` | `dev` | |
| `JWT_SECRET` | none | At least 32 bytes, or startup fails |
| `JWT_ACCESS_MINUTES` | 60 | |
| `JWT_REFRESH_DAYS` | 60 | |

## Endpoints

```
POST /auth/register          email and password, returns a token pair
POST /auth/login             same
POST /auth/refresh           trades a refresh token for a fresh pair

POST /sync/events            push a batch from a device's outbox
GET  /sync/events?since=N    everything after a sequence number
GET  /sync/conflicts         reading positions awaiting the reader's decision
POST /sync/conflicts/{id}/resolve

GET  /health                 open, reports database reachability
```

Everything under `/sync` requires a bearer token. The user id comes from that
token and never from the request body: accepting an owner from the body would
let any account write into any other account's stream.

## Auth

The service issues its own tokens rather than delegating to Firebase or Google
as the issuer. That means a social login can be added later purely as an
identity source, without reworking how the API authenticates.

Access and refresh tokens carry a type claim. Without it a refresh token would
work as an access token, quietly extending every session to the refresh
window.

Login answers identically whether the email is unknown or the password is
wrong, so the endpoint cannot be used to find out which addresses are
registered.

Unauthenticated requests get 401, unauthorised ones get 403. Spring Security
answers 403 for both by default; the client needs them apart to know when to
refresh rather than log the reader out.

## Sync

Clients append events to a local outbox and drain it when there is a
connection. The service assigns each accepted event a sequence number that is
monotonic per user, and devices pull everything after the number they last
saw.

**The log records; the state resolves.** `sync_events` is append-only and
keeps every write including ones that lost. `entity_state` holds the current
resolved value per entity, so a device that has been away for a month does not
replay a thousand events to learn one reading position.

**Ordering uses hybrid logical clocks.** Format is
`{millis:013d}-{counter:05d}-{deviceId}`, fixed-width so lexicographic
comparison gives the same answer as comparing the parts, which means the
database can order by the string without parsing it.

Clients supply their own stamps, so the service does not trust them. A stamp
more than five minutes ahead of server time is rejected rather than clamped:
rewriting a client's stamp would break its own local ordering, and a device
claiming next week would otherwise win every comparison from then on.

**Retries are safe.** Every event carries a client-generated idempotency key,
enforced by a unique constraint on `(user_id, idempotency_key)` rather than a
select followed by an insert, so the guarantee holds under concurrent pushes
instead of depending on a check and an insert staying together.

**Conflict resolution differs by entity type.** This is the substantive
decision in the service.

| Entity | Rule |
|---|---|
| Preference, profile, book metadata | Last write wins |
| Bookmark | Tombstone on delete, so the deletion reaches devices that were offline |
| Reading position | Surfaced when two devices diverge, last write wins otherwise |

Reading positions are the exception because being dropped in the wrong chapter
is the failure a reader actually notices. Two devices within 500 tokens are
the same place for practical purposes and resolve silently. Beyond that, the
divergence is recorded for the reader to settle.

One device moving a long way is not a divergence — that is an afternoon of
reading. It takes two devices disagreeing.

Recorded in [ADR 0005](../docs/adr/0005-sync-event-log.md).

## Schema

Flyway migrations in `src/main/resources/db/migration`, applied in version
order and recorded in `flyway_schema_history`, so the schema is reproducible
from an empty database and reviewable in a diff.

Never edit an applied migration: Flyway stores a checksum and startup fails
if one changes. Schema changes go in a new file.

```
users                 accounts
user_sync_state       the sequence counter, one row per user
sync_events           append-only log
entity_state          current resolved value per entity
position_conflicts    divergences awaiting the reader
```

No JPA. The queries here are simple enough that `JdbcClient` and plain SQL are
clearer than an ORM, and the resolution logic depends on SQL the mapping layer
would obscure — the conditional upsert in `SyncRepository.upsertState` refuses
an older stamp in the database itself, so even a race past the service's own
comparison cannot let an older write win.

## Testing

```bash
./mvnw verify
```

Needs a `hereader_test` database:

```bash
docker exec hereader-db psql -U postgres -c "create database hereader_test"
```

Unit tests for tokens and clock stamps run without a Spring context. Everything
else runs the real filter chain against a real Postgres, because the failures
that matter in sync are ordering, retried pushes and cross-device races, none
of which appear without the database enforcing its constraints. An in-memory
substitute would not do: the schema uses jsonb, uuid and Flyway, and none of
them behave the same on H2.

CI runs the same suite against a Postgres service container.

## Not built yet

Deployment. Compaction of the event log. Bookmarks, which have a conflict rule
defined but no endpoint using it.
