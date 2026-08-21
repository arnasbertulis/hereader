# server

The sync service for hereader. Spring Boot 4.1 on Java 25, Postgres, no ORM.

Stores reading positions, profiles and preferences. Never book files: those
stay on the reader's device, which is a privacy decision and a licensing one.
See [ADR 0004](../docs/adr/0004-store-book-files.md).

Deployed on a single Hetzner VPS via Docker Compose, behind Caddy, which also
serves the compiled Flutter web build from the same hostname. See
[ADR 0006](../docs/adr/0006-deployment-infrastructure.md). Releases go out
from a `v*` tag: CI builds this service and the web bundle into container
images and the server pulls them, per
[ADR 0023](../docs/adr/0023-continuous-deployment.md).

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

On Windows, set `JWT_SECRET` in the IntelliJ run configuration, or in
PowerShell before running Maven:

```powershell
$env:JWT_SECRET = [Convert]::ToBase64String((1..48 | ForEach-Object { Get-Random -Maximum 256 }))
./mvnw spring-boot:run
```

Flyway applies the schema on first start. `GET /api/health` reports whether the
service can reach its database rather than merely whether the process is
alive, because a health check that always answers ok makes a broken deploy
look healthy. It runs `select 1` and answers with nothing about the data
itself — earlier it ran `select count(*) from users`, disclosing the account
count to an unauthenticated caller for no reason the check needed.

Everything sits under a `/api` context path, set by
`server.servlet.context-path`, so that Caddy can serve the web build from the
same hostname and browser requests are same-origin in production. Controller
mappings below are written without it; the URL a client calls carries it.

**Via Docker Compose**, which is what production runs:

```bash
cp .env.example .env   # then edit JWT_SECRET and DATABASE_PASSWORD
docker compose up --build -d db app
```

Compose defines four services: Postgres, this service, Caddy, and the backup
job described below. Only Caddy
publishes ports to the world; the service binds to `127.0.0.1:8080` and the
database publishes nothing at all, which is why a development container must
not reuse the name `hereader-db` — it would be replaced by one nothing on the
host machine can reach.

Caddy is named out of the command above rather than brought up. It runs
`ghcr.io/arnasbertulis/hereader-web`, an image CI builds by copying the
compiled Flutter bundle into `caddy:2`, and its certificate is issued against
an sslip.io hostname that resolves to the server's IP — so a local one has
nothing to serve and would fail its ACME challenge anyway. `app`'s image tag
comes from `HEREADER_TAG` in `.env`, defaulting to `local`, which is what
`--build` produces here and what `server/deploy.sh` overwrites with a commit
sha on the server. See [ADR 0023](../docs/adr/0023-continuous-deployment.md).

`db-backup` is named out of it too, for a duller reason: it works locally and
writes dumps of a development database that nobody wants.

## Backups

The `db-backup` service runs `backup/backup.sh` once when it starts and then
every night at 03:00 UTC, writing a `pg_dump` archive into the `db-backups`
volume and keeping fourteen days of them. It is the same `postgres:17` image
as the database, so `pg_dump` never drifts out of step with the server it is
dumping. See [ADR 0024](../docs/adr/0024-database-backups.md) for why this is
a compose service rather than a cron entry, and for what it deliberately does
not cover.

Each run writes to a `.partial` name, checks the archive is readable with
`pg_restore --list`, renames it into place, and only then deletes anything
older than the retention window. The service reports unhealthy if no dump is
newer than 25 hours, because a backup job that silently stopped looks exactly
like one that is working.

```bash
docker exec hereader-db-backup ls -lt /backups     # what is there
docker exec hereader-db-backup /opt/backup/backup.sh   # take one now
docker inspect --format '{{.State.Health.Status}}' hereader-db-backup
```

The volume is also mounted read-only into `db`, so restoring does not begin
with copying a file between containers. Checking a dump without touching
anything live:

```bash
docker exec hereader-db sh -c 'createdb -U "$POSTGRES_USER" hereader_restore_check'
docker exec hereader-db sh -c 'pg_restore -U "$POSTGRES_USER" \
  -d hereader_restore_check "$(ls -t /backups/hereader-*.dump | head -1)"'
docker exec hereader-db sh -c 'psql -U "$POSTGRES_USER" -d hereader_restore_check \
  -c "select count(*) from users"'
docker exec hereader-db sh -c 'dropdb -U "$POSTGRES_USER" hereader_restore_check'
```

Restoring for real is the same `pg_restore` against `hereader`, with the
service stopped so nothing writes underneath it. The dump carries
`flyway_schema_history`, so the service starts against it without re-running
migrations.

```bash
docker compose stop app
docker exec hereader-db sh -c 'dropdb -U "$POSTGRES_USER" hereader'
docker exec hereader-db sh -c 'createdb -U "$POSTGRES_USER" hereader'
docker exec hereader-db sh -c 'pg_restore -U "$POSTGRES_USER" \
  -d hereader "$(ls -t /backups/hereader-*.dump | head -1)"'
docker compose start app
```

The `dropdb` in that sequence discards the current database. There is no
undo, and the dump being restored is the only copy of what replaces it —
which is the reason the check above exists as a separate, harmless procedure.

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
| `CORS_ALLOWED_ORIGINS` | `http://localhost:*`, plus the deployed hostname | Comma-separated. Load-bearing for a Flutter dev server on a random port |
| `AUTH_RATE_LIMIT_PER_MINUTE` | 10 | Per client IP, against `/auth/**` |

`.env` holds the secret and the database password on a developer's machine and
on the server, populated separately in each place and never committed.
`compose.yaml` passes `CORS_ALLOWED_ORIGINS` through to the `app` container
with the deployed origin as its default — the deployed `.env` should still set
it explicitly to the deployed origin only, since the default exists for a
fresh checkout and not as a substitute for a deliberate value.

The backup job reads none of these. Its connection comes from the standard
`PG*` variables that `compose.yaml` sets for it, and its one setting,
`BACKUP_KEEP_DAYS`, is written there rather than in `.env` because it is a
property of the deployment and not a secret.

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

`POST /sync/events` rejects a push over 16MB by `Content-Length`, before the
body is parsed — `SyncRequestSizeFilter`. Bean validation on `PushRequest`
alone doesn't bound memory, since Jackson has already built the object graph
by the time it runs. `server/Caddyfile`'s `request_body` directive enforces
the same limit against actual bytes as they stream in, ahead of the JVM,
which also covers a request that omits `Content-Length` altogether.

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

CORS is configured explicitly. Spring Security sends no CORS headers by
default, so a browser client on a different origin gets a request that the
service handled correctly and the browser then discarded.

`/auth/**` is rate-limited to 10 requests per minute per client IP (ADR 0026):
`/auth/register` writes two rows and `/auth/login` runs a bcrypt comparison at
real cost, so both are amplifiers for a caller with no limit. Exceeding it
answers 429 with a `ProblemDetail` body and a `Retry-After` header. The limit
is per-process, in memory — correct for the single instance this runs as
today (ADR 0006), not for a future one with more than one `app` container.

## Sync

Clients append events to a local outbox and drain it when there is a
connection. The service assigns each accepted event a sequence number that is
monotonic per user, and devices pull everything after the number they last
saw.

**The log records; the state resolves.** `sync_events` is append-only and
keeps every write including ones that lost. `entity_state` holds the current
resolved value per entity, so a device that has been away for a month does not
replay a thousand events to learn one reading position.

**A deletion is a fact about the event, not only about the state.** Both
tables carry a `deleted` flag. `entity_state` has since V2; `sync_events` only
since V3, and the gap between them was the worst bug this project has had.
Clients pull the log, not the resolved state, and the pull query filled the
field with a literal `false`. A profile deleted on one device would have
arrived elsewhere as an ordinary write carrying that profile's last payload
and the deletion's stamp — the highest stamp in play — so every other device
would write it back as live while the deleting device kept its tombstone. Two
devices permanently disagreeing, nothing logged. Found by reading the wire
contract end to end before attempting a cross-device test; neither suite could
have caught it, since the Dart tests run against a fake service and the Java
tests had never exercised a deletion because no client had ever sent one.

**Ordering uses hybrid logical clocks.** Format is
`{millis:013d}-{counter:05d}-{deviceId}`, fixed-width so lexicographic
comparison gives the same answer as comparing the parts, which means the
database can order by the string without parsing it. The Dart client
implements the same format byte for byte.

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

The threshold is measured against a token index the client supplies, which the
service cannot verify. It is used here and only here: a wrong value costs a
prompt that was not needed or misses one that was, and the client deliberately
never shows the figure to a reader, since both candidates resolve against that
device's own copy of the book.

The service has no way to know whether a device has actually imported the
book a position refers to — book files never reach it, by design. A client
that receives a position for a book it does not have holds it locally until
the book is imported, rather than discarding it or failing. See
[ADR 0007](../docs/adr/0007-pending-positions.md); nothing about that changes
this service's schema or behaviour, since the position event it delivered was
already correct.

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

```
V1  initial schema
V2  entity_state, the resolved value per entity
V3  the deleted flag on sync_events — see the deletion note above
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

If nothing is listening on `localhost:5432` when `verify` runs, every
integration test fails with the same `UnsatisfiedDependencyException` chain
down to `Connection refused` — Flyway cannot open a connection, so the
Spring context never starts, and every test in that context fails identically
after the first. Check `docker ps` for a Postgres container with its port
actually published to the host before assuming anything else is wrong; the
deployed compose stack's `db` service does **not** count, since ADR 0006
deliberately keeps that port internal to the Docker network only.

Unit tests for tokens and clock stamps run without a Spring context. Everything
else runs the real filter chain against a real Postgres, because the failures
that matter in sync are ordering, retried pushes and cross-device races, none
of which appear without the database enforcing its constraints. An in-memory
substitute would not do: the schema uses jsonb, uuid and Flyway, and none of
them behave the same on H2.

CI runs the same suite against a Postgres service container.

## Not built yet

Compaction of the event log. Bookmarks, which have a conflict rule defined but
no endpoint using it.

An off-site copy of the nightly dumps. Every backup is currently on the same
disk as the database it came from, which answers a bad migration and a wrong
`DROP` and does not answer losing the machine. Deferred with its reasons in
[ADR 0024](../docs/adr/0024-database-backups.md) rather than left unsaid.
