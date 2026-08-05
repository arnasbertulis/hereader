# 0006. Deploy on a single Hetzner VPS via Docker Compose, fronted by Caddy

Date: 2026-08-05

## Status

Accepted.

## Context

Nothing was containerized or hosted before this. The app and Postgres ran
locally via IntelliJ and a manually-started container. Budget for hosting
is self-imposed: up to roughly 10 EUR/month, ideally less, with one hard
requirement — the link must be reachable at all times. A free tier that
sleeps on inactivity (Render's free web services, for instance) fails that
requirement by design, regardless of cost.

No domain is owned, and buying one wasn't judged worth it for a portfolio
project with a fixed application deadline.

Comfort level with the underlying tools (SSH, Docker, systemd) was
explicitly low going in. That was treated as a reason to choose the option
with the most transferable learning, not a reason to avoid infrastructure
work in favor of a more automated platform.

## Options considered for hosting

**Oracle Cloud "Always Free" ARM VM.** Genuinely free, and generous on
paper (up to 4 OCPU / 24GB). Rejected: current reports describe
inconsistent provisioning ("out of capacity" errors in some regions) and
allocation changes applied without notice. Unpredictability is a bad trade
against a fixed application deadline, even to save a few euros a month.

**Fly.io / Railway (managed PaaS).** Rejected on cost: Fly.io's free tier
was discontinued in 2024; a small always-on app plus a Postgres volume
runs roughly 13-20 EUR/month once machine and volume costs are totaled,
above budget for what this project needs. Also rejected on learning value:
deploying here means learning a platform-specific CLI and config format,
not the transferable skills (SSH, Docker, reverse proxies) that were an
explicit goal.

**Render free tier.** Rejected outright: sleeps on inactivity, which
directly violates the always-available requirement.

**Hetzner CX22 VPS.** Chosen. Roughly 4-6 EUR/month depending on region
and VAT, comfortably within budget. No automatic scaling, no managed
database, no platform abstraction — full manual control, which was the
point.

## Decision

### One VPS running the whole stack via Docker Compose

The Spring Boot app, Postgres, and the reverse proxy all run as containers
on a single Hetzner CX22 (2 vCPU / 4GB RAM / 40GB NVMe). No managed
database service, no separate static-hosting platform for the Flutter web
build.

At this project's actual scale — one developer, occasional recruiter
traffic — splitting these across multiple platforms would mean
coordinating several dashboards and sets of credentials for no operational
benefit. Consolidate until there's a concrete reason not to.

### SSH key-only authentication, no root login

An ed25519 key pair was generated locally and attached to the server at
creation time, so no root password was ever set. A non-root `deploy` user
was created immediately after first boot, given `sudo` and `docker` group
membership, and root SSH login was then disabled entirely.

Password authentication over SSH is one of the most commonly automated
attack vectors against any server with a public IP. Removing it, and
removing root as a login target at all, closes that off from the first
real session onward rather than as a later hardening pass.

### Hetzner Cloud Firewall restricts inbound traffic to 22, 80, 443, and ICMP

Hetzner does not firewall a server by default; every port is reachable
the moment it boots. A firewall was attached explicitly, allowing only
SSH, HTTP, HTTPS, and ping. Nothing else — including Postgres's 5432 and
the app's own 8080 — is reachable from outside the server at all.

### Caddy as reverse proxy, sslip.io for the hostname

Caddy sits in front of the app container and is the only thing with ports
published to the host (80 and 443). It proxies to `app:8080` over
Docker's internal network. `db`'s port is not published to the host at
all; `app` reaches it as `db:5432` over the same internal network.

No domain is owned, and TLS certificates need a real hostname to attach
to — a bare IP address cannot get a Let's Encrypt certificate. `sslip.io`
solves this without registering anything: it's a DNS service that parses
the target IP directly out of the hostname itself (`204-168-240-12.sslip.io`
always resolves to `204.168.240.12`). Caddy requests a certificate against
that hostname, Let's Encrypt's HTTP-01 challenge succeeds because port 80
is reachable, and the whole certificate lifecycle — issuance and renewal
— happens automatically from then on.

Caddy's certificate cache lives in a named Docker volume
(`caddy-data`), not left to be recreated on every container restart.
Let's Encrypt rate-limits how often a given hostname can request a new
certificate; without persistence, a few redeploys in quick succession
could exhaust that limit and leave the app without valid HTTPS until it
resets.

### Local testing intentionally stops short of the Caddy layer

The app-and-Postgres pairing was verified fully locally first — fresh
volume, Flyway migrations applying cleanly, `/health` responding —
before any of this was provisioned. Caddy's config was not, and cannot
be, verified locally the same way: the `sslip.io` hostname resolves to
the real server's IP, not to a developer's machine, so a local Caddy
container would simply fail its ACME challenge. This was accepted as a
real gap in local coverage rather than worked around, since faking it
would test something other than what actually runs in production.

## Consequences

The server has no automatic backups and no failover. Postgres data here
is reading positions and preferences, not the book files themselves (see
ADR 0004 — those never leave the reader's device), so the actual cost of
losing this data is low: recreatable by re-registering test devices,
not an irreplaceable loss. Revisit if this project ever has real users
depending on synced state persisting.

There is no CD pipeline yet. Deploying a change today means SSH-ing in,
`git pull`, and `docker compose up --build -d` by hand. Acceptable for a
single-developer project at this stage; worth automating if deploys
become frequent enough for the manual step to be the bottleneck rather
than a rare, deliberate action.

The `sslip.io` hostname is tied to this server's specific IP. Moving to a
new server, or Hetzner ever changing the assigned address, means the
public URL changes too. A real domain, if one is bought later, removes
this coupling — noted as the natural next step if this ever needs to be
a stable, memorable link rather than a working one.

Everything currently runs as root inside its containers at the OS level
of the host is avoided (non-root `deploy` user, non-root user inside the
Spring Boot image per the Dockerfile), but the containers themselves have
no resource limits set — a runaway process in any one of them could
still exhaust the VPS's 4GB RAM. Not yet a problem at this traffic level;
worth adding `mem_limit` per service if it becomes one.

## Alternatives considered

**Buying a domain now.** Rejected for cost and lack of urgency — sslip.io
gives a working HTTPS endpoint today at zero cost; a domain is a small,
reversible upgrade to make later if the project needs a more permanent or
presentable URL.

**A managed Postgres service (Neon, Supabase) alongside a separate app
host.** Rejected: adds a second platform, a second set of credentials,
and a network hop between app and database for no benefit at this scale
— the whole point of consolidating onto one VPS was to avoid exactly this
kind of unnecessary coordination.

**Deploying without a firewall or without disabling root login, planning
to harden "later."** Rejected deliberately. Both are essentially free to
do correctly from the start and meaningfully more annoying to retrofit
onto a server that's already been live and reachable on the open internet.