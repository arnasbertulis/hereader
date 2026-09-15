# Hereader

![dart](https://github.com/arnasbertulis/hereader/actions/workflows/ci-dart.yml/badge.svg?branch=main) ![flutter](https://github.com/arnasbertulis/hereader/actions/workflows/ci-flutter.yml/badge.svg?branch=main) ![java](https://github.com/arnasbertulis/hereader/actions/workflows/ci-java.yml/badge.svg?branch=main)

A configurable reading surface for low-vision readers. Text is presented one
word at a time in a fixed position, instead of as a page you scan with your
eyes — the technique is Rapid Serial Visual Presentation (RSVP).

**Status: in active development.** Books can be imported and read, notes can
be written and read alongside them, reading settings can be adjusted and
saved, and both a reading position and the settings themselves follow the
reader between devices. Live at
**[https://204-168-240-12.sslip.io](https://204-168-240-12.sslip.io)** — open
it directly in a browser, or see [`docs/status.md`](docs/status.md) for what
works today.

https://github.com/user-attachments/assets/9c2b9218-ec69-4ccc-b512-7cb934ae6a5b

## Why this exists

**Central field loss**, a blind spot in the middle of the visual field, makes
conventional page reading a search for the next word using an off-centre part
of the retina. Presenting one word at a time in a fixed position removes that
search: Rubin and Turano (1994) measured about 1.3 fewer saccades per word
under RSVP than page reading, with retinal imaging. It is not the only case
this app targets — presentation is a set of independent controls (print size,
position, pacing, chunk size, spacing, contrast, typeface, reader- or
timer-driven advance), with presets as starting points.

RSVP is not a speed-reading technique for normally sighted readers, and this
project makes no such claim; it does not diagnose, treat or manage any
condition. The full evidence review, including studies that argue against
parts of this design, is in
[`docs/research/rsvp-evidence.md`](docs/research/rsvp-evidence.md).

## What works today

Full checklist in [`docs/status.md`](docs/status.md). Highlights: EPUB import
and parsing, three pacing models, two reading surfaces (fixed word and
sliding text), local notes, a library with sort and filter, cross-device sync
of reading positions and profiles with conflict resolution, a Free books
catalogue of ~78,000 Project Gutenberg titles, and a deployed CI/CD pipeline
with nightly database backups.

## How it's built

The reader's device is authoritative for reading; everything works offline,
and an account is offered, never required. Sync is an append-only event log
with hybrid-logical-clock ordering and per-entity conflict resolution —
reading positions prompt the reader on real divergence, preferences and
profiles take last-write-wins. Books never leave the device: the service
stores positions, preferences and metadata only.

[`docs/architecture.md`](docs/architecture.md) covers sync and the dozen or
so decisions that shape the most code — locators as character offsets rather
than word indices, pacing as a sealed decision rather than a `Duration`,
presets as code that fork on edit, and so on. Every substantial decision has
its own ADR in [`docs/adr/`](docs/adr/README.md), with rejected alternatives
and why.

## Repository layout

```
packages/rsvp_engine/     Pure Dart. Tokenizer, pacing models, reading
                          profiles, playback state machine, locators,
                          hybrid logical clocks, WCAG contrast maths.
packages/epub_reader/     Pure Dart. Zip container and OPF parsing, HTML
                          normalisation, front matter detection, table of
                          contents parsing, cover extraction.
app/                      Flutter client. Android, Windows, web.
server/                   Spring Boot service. Auth, sync event log,
                          conflict resolution. Postgres via Flyway.
                          Dockerfile, compose.yaml and Caddyfile for
                          deployment.
docs/adr/                 Architecture decision records.
docs/research/            Evidence notes behind the design.
```

Each directory carries its own README with the detail this one leaves out:
[`app`](app/README.md), [`server`](server/README.md),
[`rsvp_engine`](packages/rsvp_engine/README.md),
[`epub_reader`](packages/epub_reader/README.md).
[`CONTRIBUTING.md`](CONTRIBUTING.md) covers the process this repo follows.

## Running it

```bash
git clone https://github.com/arnasbertulis/hereader.git
cd hereader

cd packages/rsvp_engine && dart test && dart analyze
cd ../epub_reader && dart test && dart analyze

cd ../../app
flutter pub get
flutter run -d windows   # or -d chrome, or a connected Android device
```

The app works fully offline and expects the sync service on
`http://localhost:8080/api` — override with
`--dart-define=HEREADER_API=<url>`. The service is optional; see
[`app/README.md`](app/README.md) for platform-specific notes (web needs a
secure context, and two vendored drift assets) and
[`server/README.md`](server/README.md) for running the sync service via
Docker Compose or Maven.

## Testing

Each package's own README has its test commands. In short: `dart test` in
each pure-Dart package, `flutter test` in `app/`, `./mvnw verify` in
`server/`. CI runs all of it on every push — see
[`.github/workflows/`](.github/workflows/).

## Roadmap

1. Bookmarks and highlights over the same sync event log
2. Exporting and importing a profile as a file, for sharing without an account
3. Book transfer between devices, over the local network or a share sheet — never relayed through the service, to avoid transmitting copyrighted content
4. A second Catalogue source alongside Project Gutenberg (Standard Ebooks is the candidate, gated by its feed requiring an account)
5. Google sign-in as an additional identity source
6. PDF support: column detection, header/footer stripping, reading-order reconstruction
7. A frame measurement of sliding text on a physical Android phone, and a screen-reader pass over its step actions
8. Right-to-left text on the sliding surface
9. An off-site copy of the nightly database dumps

## Known limitations

Trade-offs taken deliberately rather than bugs — full list in
[`docs/known-limitations.md`](docs/known-limitations.md). A few that matter
most for anyone evaluating the project: books and notes don't transfer
between devices (by design — see the roadmap); a different edition of the
same book won't resolve a saved position against it; the deployed web build
runs `dart2js` output, not `--wasm`; and iOS is untested since building it
needs macOS hardware.

## License

MIT. See [LICENSE](LICENSE).
