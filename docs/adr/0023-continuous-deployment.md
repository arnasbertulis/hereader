# 0023. Deploy container images built by CI, triggered by a version tag

Date: 2026-08-19

## Status

Accepted. Supersedes the "There is no CD pipeline yet" paragraph in ADR
0006's Consequences.

## Context

Deploying a change meant four manual steps: SSH to the VPS, `git pull`,
`docker compose up --build -d`, and then a separate copy of the compiled
Flutter web bundle from the developer's machine into `server/web-dist/`,
which Caddy served through a read-only bind mount.

Three properties of that arrangement are worth stating plainly, because
each of them is what this ADR is actually replacing.

**The web bundle could not come from `git pull`.** `server/web-dist/` was
in `.gitignore`. The copy was not an oversight in the routine; it was
load-bearing, and it was the one step no CI run could have caught being
skipped.

**The VPS compiled the application.** `build: .` on the `app` service meant
a full Maven build on a CX22 — 2 vCPU and 4GB of RAM, already running a JVM
and Postgres. It worked, but the machine sized for serving was doing the
work of a build machine, on the release path.

**Nothing named the running release.** With the server source at whatever
`git pull` had fetched and the bundle at whatever was last copied, the
answer to "what is deployed" was a date and a memory. There was nothing to
roll back *to*.

There was also a quieter problem in CI. `ci-flutter.yml` ran
`flutter build web` with no `--dart-define`, so `HEREADER_API` took its
`http://localhost:8080/api` default (`app/lib/main.dart:23`). The check
proved that the app compiles to JS, which is what ADR 0009 asks of it, but
the artifact it produced was not one that could ever be deployed. Building
in CI for real makes that difference matter.

## Decision

### CI builds two images and pushes them to GHCR; the server only pulls

`ghcr.io/arnasbertulis/hereader-server` is the existing `server/Dockerfile`.
`ghcr.io/arnasbertulis/hereader-web` is `caddy:2` with the compiled bundle
copied in, from `app/web.Dockerfile`. Both are tagged with the commit sha
and with `latest`.

Baking the bundle into the Caddy image rather than mounting a directory is
what makes a web release atomic. Replacing files under a live bind mount
has a window — short, but real — where one request can be served part of
one release and part of the next; `index.html` from the new bundle asking
for a `main.dart.js` that has not landed yet is a white page, and it
resolves itself, which is the worst kind of fault to be told about.

It also settles a smaller trap. The obvious way to make the copy atomic is
to write a new directory and rename it into place, and that does not work
here: a bind mount resolves to a path when the container starts, so
renaming the directory out from under Caddy leaves it serving the old
files from an inode with no name.

The Caddyfile stays a bind mount. Serving config changes on a different
schedule from the bundle, and mounting it keeps
`docker compose restart caddy` as the way to apply one.

### The tag to run is written into `.env`, not exported for one command

`compose.yaml` refers to `${HEREADER_TAG:-local}` and `server/deploy.sh`
writes the sha into `server/.env`, which compose already reads for the
database password.

The alternative — exporting the variable for the single `docker compose up`
— leaves the box in a state where anyone running `docker compose up -d` by
hand afterwards silently moves the deployment to `:local`, or to whatever
`:latest` has become. Writing it down means the file on the server records
what is running, and a rollback is that line changed to an earlier sha
followed by `docker compose up -d`. No pipeline run required to undo a
pipeline run.

### Deploys are triggered by a `v*` tag, not by a merge to `main`

The three CI workflows are separate files, and a workflow cannot depend on
a job in another one. A `push: branches: [main]` trigger would therefore
start deploying in parallel with the tests rather than after them.
`workflow_run` can chain onto one workflow finishing but not onto three
finishing together, and reconstructing "did the other two pass" from the
API inside the deploy job is a gate written twice.

A tag avoids the question rather than answering it. The branch ruleset on
`main` already requires `app`, `server`, `test (rsvp_engine)` and
`test (epub_reader)` to pass before anything merges, so a commit that has a
tag on it has been through them. Tagging is also an accurate description of
what a deploy is on this project — a deliberate act, not a consequence of a
merge, which is the framing ADR 0006 chose and which nothing since has
changed.

### The deploy key can only deploy

The key GitHub Actions holds is restricted in the server's
`authorized_keys` by `command="…/server/deploy.sh"` plus `no-pty` and the
forwarding restrictions. The commit to deploy arrives as
`SSH_ORIGINAL_COMMAND` and is matched against `^[0-9a-f]{40}$` before it is
passed to `git`.

A CI secret is a credential held by a third party and readable by anyone
who can push a workflow file. Scoped this way, the worst case is a
redeploy of a commit that is already in the repository, rather than a shell
on the machine.

### The workflow fails on the health check, not on the SSH command

`docker compose up -d` returns once containers are created, which is before
Flyway has applied anything. The deploy job polls `/api/health` — which
reports database reachability rather than process liveness, for exactly
this reason — for up to 150 seconds and fails the run if it never answers.
Without it, a deploy that started a container which then died on a bad
migration reports success.

## Consequences

The VPS no longer needs a JDK, Maven, or the Flutter SDK, and no longer
compiles anything. It needs Docker, git for `compose.yaml` and the
Caddyfile, and network access to GHCR.

Deploying the web bundle now restarts Caddy, where copying files did not.
That is a sub-second interruption, and the Let's Encrypt certificate is
unaffected because it lives in the `caddy-data` volume rather than in the
image (ADR 0006).

Both GHCR packages have to be public for the server to pull without
credentials. They are, matching the repository. Making either private later
means a read-only token on the server and a `docker login` in `deploy.sh`.

`server/web-dist/` no longer exists as a concept and its `.gitignore` entry
is gone. The directory left on the server from the previous arrangement is
harmless and unreferenced.

Three secrets now exist in the repository: `DEPLOY_SSH_KEY`, `DEPLOY_HOST`
and `DEPLOY_HOST_KEY`, plus `DEPLOY_USER`. GHCR needs none — the built-in
`GITHUB_TOKEN` with `packages: write` is enough, so there is no long-lived
registry credential anywhere.

The deployed hostname is now written in two workflow files as well as in
the Caddyfile and the README. ADR 0006 already records that the sslip.io
name is coupled to the server's IP; this adds two more places that a move
would have to touch. A repository variable was considered and rejected
below.

## Alternatives considered

**Automating the existing steps — SSH, `git pull`, `docker compose up
--build -d`, plus an rsync of the bundle.** Roughly forty lines and an
evening, against most of a day for this. Rejected because it automates the
three properties described in the Context rather than removing them: the
VPS still compiles, the bundle still arrives as loose files with a
partial-copy window, and there is still nothing to roll back to. The one
thing it does fix — a forgotten copy — is the least serious of them.

**A self-hosted runner on the VPS.** Removes the SSH secret entirely, since
the runner pulls work rather than accepting connections. Rejected: it puts
the build back on the CX22, which is the main thing being moved off it, and
a self-hosted runner on a public repository is a documented risk in its own
right — a workflow from a fork can run on it.

**`workflow_run` chaining onto the CI workflows.** Covered above; the
mechanism does not express "after three workflows" and the reconstruction
is a second copy of the gate the ruleset already enforces.

**Deploying on every push to `main`.** Rejected with the trigger decision.
It is also a poor fit for a project where a merge is often documentation.

**A repository variable for `HEREADER_API`.** Would put the hostname in one
place and let a server move happen without a code change, which is a real
argument given ADR 0006's note on IP coupling. Rejected because a variable
that is unset produces `--dart-define=HEREADER_API=` — an empty string,
which `Uri.parse` accepts — so a fresh clone or a misconfigured repository
builds a bundle whose sync requests go nowhere, and does it silently.
Guarding that means writing the literal into the workflow as a fallback
anyway. The value is configuration, it is already public in the Caddyfile
and the README, and two occurrences under `.github/workflows/` are
greppable.

**Keeping `web-dist` as a bind mount and rsyncing into it from CI.** The
partial-copy window and the rename trap are both properties of the mount,
not of how the files get there.

## Verification

`docker compose config` in `server/` resolves, with `HEREADER_TAG` unset and
the database and secret variables supplied on the command line. Both
services report `:local`, which is the developer-machine case, and the
`web-dist` bind mount is gone from the `caddy` service while the Caddyfile
mount remains.

`bash -n server/deploy.sh` parses.

The two workflow files were not machine-linted before their first run.
`actionlint` needs Go or a running Docker daemon and neither was available
in the session that wrote them. GitHub accepted both as written.

**Both triggers have now run end to end against the real VPS.** A
`workflow_dispatch` run on `main` at `f1b3c7f`, and a `v0.1.0` tag at
`281f608` — the second confirming the `push: tags: ['v*']` trigger, which
is the path the design actually rests on. Each ran both image jobs, the
forced command over SSH, the checkout, the `.env` rewrite, `docker compose
pull` against GHCR and the health poll. `GET /api/health` answered
`{"status":"ok"}` and the web root returned 200 afterwards.

Timings from the tagged run, which are the useful ones rather than the
impressive ones: `server-image` 26s, `web-image` 79s, `deploy` 24s. The
server image build was a warm GHA cache hit and says nothing about a cold
one; the point it does make is that the Maven build is no longer on the
CX22's clock at all.

**The health poll finished on its third attempt, about 12 seconds into a
150-second budget.** So the question this section was left open to answer —
whether 150 seconds covers a cold Flyway start — is still unanswered, and
now harder to answer accidentally: both runs found Postgres already up with
its migrations applied, because only the `app` and `caddy` containers were
replaced. The budget has never been near its limit and the first deploy
that brings up a fresh database is the one that will test it.

Three things the runs found rather than confirmed:

- **The first attempt failed on `REMOTE HOST IDENTIFICATION HAS CHANGED`**,
  which is indistinguishable from a man-in-the-middle at a glance. The cause
  was a mangled `DEPLOY_HOST_KEY`, and establishing that meant fetching the
  server's key from two independent sources and comparing fingerprints by
  hand, because ssh names the key the server sent and never the one it was
  compared against. The step now prints the pinned fingerprint, which is
  public by construction and makes the two cases one glance apart. A pinned
  host key is still the right call over a deploy-time `ssh-keyscan`; what
  was wrong was pinning it without any way to see what had been pinned.
- **A host key copied out of a search tool's output is not the key.**
  `Select-String` prefixes its matches with a path and a line number, and
  the value has to be byte-exact. It is now taken from the file directly.
- **The `docker/*` actions run on a deprecated Node 20 runtime**, forced
  onto Node 24 by the runner with a warning on every run. Not a failure and
  not addressed here; it will become one when the forcing stops.

**Still unverified.** The rollback path — editing `HEREADER_TAG` in the
server's `.env` and running `docker compose up -d` — has never been
exercised, which is unfortunate for a path whose whole value is being
available on a bad day. So is a deploy against a cold database, per the
health budget above, and a cold-cache image build.
