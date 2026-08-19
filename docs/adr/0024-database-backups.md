# 0024. Nightly `pg_dump` from a compose service, kept on the same machine

Date: 2026-08-19

## Status

Accepted.

## Context

ADR 0023 made a release something that can be undone: the running tag is
written into `server/.env`, and putting the previous one back is one line
and a `docker compose up -d`. Nothing equivalent exists for the data. A
release can be rolled back; a dropped table cannot.

What Postgres holds here is accounts — an email address and a password
hash each — the sync event log, the resolved state per entity, and the
reading positions waiting for a reader to settle them. It does not hold
books. ADR 0004 keeps EPUB bytes on the device and the service never
receives one, so the worst case is that every device re-registers and
every reader loses their place, not that anything unrecoverable is gone.

That is a genuinely low cost, and it has been the standing reason for not
having backups. It is also not a reason that survives being written down:
the cost of the loss is low, the cost of preventing it is a scheduled
`pg_dump`, and the README has carried "no automated backups" as a known
limitation for as long as there has been a server.

The realistic ways the data goes away, in the order they are likely:

**A migration that applies cleanly and is wrong.** Flyway runs at startup
on every deploy. ADR 0023's health check catches a migration that *fails*
— the service cannot reach the database, so `/health` never answers — and
says nothing about one that succeeds and drops the wrong column.

**A command typed against the wrong machine.** `docker compose down -v`
is four words from `docker compose down`, and the developer's machine and
the server run the same compose file.

**The data directory corrupting**, or being deleted while the database is
stopped.

**The VPS ceasing to exist.** One machine, one disk, no replica (ADR
0006). This is the one a local dump does not answer, and the decision
below says so rather than implying otherwise.

## Decision

### The dump is taken by a compose service, not by a host cron

A `db-backup` service on the same `postgres:17` image as the database,
which means `pg_dump` and the server it dumps stay in step without a
second thing to remember.

A crontab is the obvious alternative and is worse here for a specific
reason: ADR 0023 spent its length moving the server towards holding
nothing but Docker, git and a checkout, with everything that defines the
deployment in the repository. A cron entry is state on the box that no
clone contains, that no deploy updates, and that a rebuilt server would
silently not have. The service is in `compose.yaml`, so it arrives with
the next deploy and leaves with a `git revert`.

### Nightly at 03:00 UTC, plus one at container start

The startup dump exists so that a backup exists immediately after this is
first deployed and after every deploy since, rather than at 03:00 the
following morning. It also makes the health check below answerable from
the moment the container comes up.

Sleeping to the next 03:00 rather than for 24 hours keeps the schedule
anchored: a deploy at an odd hour does not move backups to that hour
permanently.

### Custom format, checked before it is published, pruned after

`pg_dump --format=custom` over plain SQL. It is compressed without a
second tool, `pg_restore` can pull a single table out of it, and it
carries a table of contents that can be read back without a database —
which is what makes the check possible at all.

`pg_restore --list` runs against the new file before anything else. It
fails on a truncated or corrupt archive and costs milliseconds at this
size. It is not a restore and is not described as one anywhere: it proves
the container is intact, not that the rows inside it are the expected
rows. The restore test in Verification is the claim about the rows.

The dump is written to a `.partial` name and renamed into place after the
check passes, so an interrupted run leaves something that cannot be
mistaken for a backup. Retention deletes dumps older than fourteen days,
and it runs *after* a new one has landed and been checked, never before —
the other order is a broken dump path that quietly deletes the last good
backups on its way to writing nothing.

### The schedule is in `compose.yaml`; the work is in a mounted script

`server/backup/backup.sh` is bind-mounted into the container read-only
and invoked once per night by a four-line loop in the service's
`command:`.

The split is not aesthetic. A bind mount is resolved when the container
starts, and a deploy that rewrites the script does not restart this
container — so a long-running process that had read the script once would
keep executing the old text indefinitely, with nothing to indicate it.
Invoking the file fresh each night means the body of a backup is always
whatever the last deploy put on disk, and the only thing that can go
stale is the loop, which does not change. Changing the loop means
changing `compose.yaml`, which does force a recreate.

The directory is mounted rather than the file, for the same reason
`server/` as a whole is not: `git checkout` replaces a file by writing a
new one and renaming over it, which leaves a file-level bind mount
pointing at the old inode. A directory mount is stable across that.
Mounting `server/` itself would put `.env`, and so the database password
and the JWT secret, inside a container that has no use for either.

### A backup that stopped happening is visible

The service has a health check that passes if any dump in the volume is
newer than 25 hours. The steady-state interval is exactly 24, and the
only irregular gap — between the startup dump and the first 03:00 — is
always shorter than that.

This is the failure this kind of job actually has. A backup that silently
stopped three months ago looks identical to one that is working right up
until the morning it is needed. `docker ps` now says `unhealthy`.

### Restoring is done from the database container

The dumps volume is mounted read-only into the `db` service as well, so a
restore is a `pg_restore` against a path that container can already see.
Without it the dumps would have to be copied out of one container and
into another on the one day that is the worst day to be doing extra
steps.

### The dumps stay on this machine, and that is stated as the limit

They are in a Docker volume on the same disk as the database. That covers
a bad migration, a wrong `DROP`, a corrupt data directory and a deleted
`db-data` volume. It does not cover the disk, the machine, or a
`docker compose down -v`, which takes both volumes.

An off-box copy is the thing that would close that, and it needs a second
credential on the server and a destination that costs money. For a
database whose loss means re-registering test devices, that trade goes
the other way for now. What it does not get to be is unstated: the README
carries it as a known limitation, in place of the line this ADR removes.

## Consequences

Fourteen daily dumps of a database in the low megabytes, compressed. On a
40GB disk this is not a quantity anyone needs to plan for, and if the
database ever grows to where it is, `BACKUP_KEEP_DAYS` is one environment
variable.

The deploy that first carries this recreates the `db` container, because
adding a mount changes its configuration. That is a brief Postgres
restart mid-deploy — the first one the pipeline has caused, since every
release so far replaced only `app` and `caddy`. It also means that deploy
is the closest thing yet to the cold-database start ADR 0023 lists as
unverified, though the data directory still exists and Flyway will find
its migrations already applied.

The backup container holds the database user and password in its
environment, as `app` does. It reaches Postgres over the compose network
on the port ADR 0006 keeps off the host.

`docker compose up --build -d db app` remains the local command. Running
`db-backup` locally works but writes dumps of a development database
nobody wants.

## Alternatives considered

**A cron entry on the host.** Covered above: it is deployment state that
lives outside the repository, and it would also need a Postgres client
installed on the machine, which is one more thing the CD design had just
finished removing.

**A purpose-built backup image such as
`prodrigestivill/postgres-backup-local`.** More features than this needs
— webhooks, multiple schedules, S3 targets — in exchange for trusting a
third-party image with the credentials to the database that holds user
accounts. What it replaces is a `find` and a loop.

**Hetzner's own server backups.** Snapshots the whole machine for 20% of
the server price, with no code at all, and unlike a local dump it
survives the disk. Rejected as the primary mechanism rather than as a bad
idea: it images a server rather than dumping a database, so a restore
takes the whole machine back to that image — including the deployed
release and anything else on it — and the granularity is whatever the
snapshot schedule is. It is complementary to this and remains available
if the off-box gap is worth closing cheaply.

**An off-box copy to a Storage Box or object storage.** The correct
answer to the failure this decision leaves open. Deferred rather than
rejected: it needs a second SSH key or an access key on the server, a
paid destination, and its own retention policy at the far end, and the
data does not yet justify them. Named in the README as a limitation so
that it is a decision rather than an oversight.

**Continuous archiving for point-in-time recovery** — WAL shipping,
pgBackRest or similar. Recovers to any second rather than to last night.
Rejected on weight: it is a standing operational commitment — archive
storage, restore rehearsals, a base backup schedule — for a service whose
recovery objective is honestly "yesterday", and the extra precision buys
back a few reading positions.

**A scheduled GitHub Actions job that dumps over SSH and stores the dump
as an artifact.** Would put every registered email address and password
hash into a third party's artifact storage, on a schedule, for a database
that fits in a volume. Rejected on that alone; the off-box question is
worth answering with something that is not a CI artifact.

**A streaming replica.** Covers hardware failure well and the most likely
failure here not at all — a replica applies the bad migration faithfully
and a few hundred milliseconds later.

**Plain SQL, gzipped.** Readable with `zless` and greppable, which has
real value when the question is "what was in this". Rejected for the two
things the custom format has: an archive listing that can be checked
without restoring, and selective restore of one table.

## Verification

`docker compose config` in `server/` resolves with the new service. The
`db-backups` volume appears on both `db` (read-only) and `db-backup`, the
script directory is a bind mount, and the `$$` in the schedule and the
health check survives compose's own substitution as a single `$`.

`bash -n server/backup/backup.sh` parses.

**The service has run on the server and a dump has been restored.** The
deploy that carried it wrote a startup dump at 20:08:09 UTC, the health
check reported `healthy` on the first inspection rather than after a day
of waiting — which is what the startup dump is for — and an on-demand run
answered `backup: wrote /backups/hereader-20260819T201210Z.dump (20K)`.

Restoring the newest dump into `hereader_restore_check` produced the same
three counts as the live database: 1 user, 39 sync events, 4 rows of
entity state. The scratch database was dropped afterwards and nothing
live was touched at any point.

That is the claim about the rows that `pg_restore --list` deliberately
does not make. What it still does not cover is a restore onto a different
cluster: this one loaded into the same Postgres, as the same superuser,
with the role the dump refers to already present. A dump restored onto a
fresh machine needs that role created first, which is the sort of thing
found at the worst possible moment.

Every command below reads the user name from the container's own
environment, so no credential is typed on the server's command line.

```bash
# what the startup run wrote, and the health the check reports
docker exec hereader-db-backup ls -lt /backups
docker inspect --format '{{.State.Health.Status}}' hereader-db-backup

# take one now, to see the script's own output
docker exec hereader-db-backup /opt/backup/backup.sh

# counts as they stand, for something to compare against
docker exec hereader-db sh -c 'psql -U "$POSTGRES_USER" -d hereader -c "select
  (select count(*) from users) users,
  (select count(*) from sync_events) events,
  (select count(*) from entity_state) state"'

# load the newest dump into a scratch database and count what arrived
docker exec hereader-db sh -c 'createdb -U "$POSTGRES_USER" hereader_restore_check'
docker exec hereader-db sh -c 'pg_restore -U "$POSTGRES_USER" \
  -d hereader_restore_check "$(ls -t /backups/hereader-*.dump | head -1)"'
docker exec hereader-db sh -c 'psql -U "$POSTGRES_USER" -d hereader_restore_check -c "select
  (select count(*) from users) users,
  (select count(*) from sync_events) events,
  (select count(*) from entity_state) state"'
docker exec hereader-db sh -c 'dropdb -U "$POSTGRES_USER" hereader_restore_check'
```

The scratch database is the point of the exercise. Restoring over
`hereader` would prove the same thing and would be the first time anyone
had tried it, on live data, which is the wrong order.

A dump of that database is 17KB, and 20KB with a second reading session in
it. Fourteen of them is a quarter of a megabyte, so the retention window
is bounded by nothing on a 40GB disk and was chosen for how far back it is
useful to go rather than for what fits.

**The deploy that carried this recreated the `db` container**, as adding a
mount to a service does, and the health check answered on its third
attempt — the same three attempts every deploy so far has taken. So a
Postgres restart with its data directory already populated costs nothing
measurable against the 150-second budget. It is still not the cold start
ADR 0023 lists as unverified: Flyway found its migrations applied and had
nothing to do.

**Still unverified.** The nightly path itself. Everything above ran at
startup or on demand, and the 03:00 UTC loop has not yet come round once —
the first morning it does is what proves the schedule rather than the
script. The health check is what would report its absence, and it now has
a dump recent enough to be reporting `healthy` for the right reason.
