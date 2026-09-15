# Architecture decision records

Every substantial decision gets an ADR, written the day it's made — see
`CONTRIBUTING.md`'s *Architecture Decision Records* section for what
qualifies and what each one must contain. [`docs/architecture.md`](../architecture.md)
walks through the ones that shape the most code.

| # | Decision |
|---|---|
| [0001](0001-monorepo.md) | Monorepo with separate pure Dart packages, so the reading core carries no Flutter import |
| [0002](0002-locator-format.md) | Locators are `{blockId, charOffset, parserVersion}`, never word indices |
| [0003](0003-pacing-decision-model.md) | Pacing returns a sealed `PacingDecision`, not a `Duration` |
| [0004](0004-store-book-files.md) | Store EPUB source bytes, not parsed text |
| [0005](0005-sync-event-log.md) | Sync is an event log with per-entity conflict rules |
| [0006](0006-deployment-infrastructure.md) | A single Hetzner VPS with Docker Compose and Caddy, over managed platforms |
| [0007](0007-pending-positions.md) | A position for a book this device lacks is held, not dropped |
| [0008](0008-profile-merge-granularity.md) | Profiles merge whole, at per-profile granularity |
| [0009](0009-web-platform-coverage.md) | Web coverage is a build for the app and a browser run for the packages |
| [0010](0010-chapter-navigation.md) | Chapter navigation reads the book's own table of contents, or none |
| [0011](0011-position-save-cadence.md) | Positions are written while reading, not only on close |
| [0012](0012-app-chrome-appearance.md) | App chrome is a neutral ramp plus one accent, chosen per device |
| [0013](0013-progress-token-index.md) | Reading progress is a stored token index, a hint and never a locator |
| [0014](0014-reading-time-estimate.md) | Time left is estimated from the active profile, and withheld under elicited pacing |
| [0015](0015-reader-chrome-is-monochrome-over-the-profile.md) | Reader chrome is monochrome over the profile, with one accent |
| [0016](0016-reader-theme-follows-the-app.md) | The reading surface follows the app unless the profile decides |
| [0017](0017-local-notes.md) | Local notes are book rows parsed through the same normalizer |
| [0018](0018-chapter-hint-on-a-tile.md) | The chapter on a tile is a device-local hint written with the position |
| [0019](0019-icons-are-two-vendored-phosphor-weights.md) | Icons are two vendored Phosphor weights, named by role in one file |
| [0020](0020-reader-driven-navigation.md) | Tap zones step by a device-local amount and stop where the reader chose |
| [0021](0021-back-a-sentence-back-a-paragraph.md) | Back a sentence and back a paragraph are their own jumps, not a reversed step |
| [0022](0022-chapter-jumps-also-suppress-the-resume-rewind.md) | A chapter or front-matter jump suppresses the resume rewind |
| [0023](0023-continuous-deployment.md) | CI builds the images, a version tag deploys them, and the server only pulls |
| [0024](0024-database-backups.md) | Backups are a nightly `pg_dump` from a compose service, kept on the same machine |
| [0025](0025-continuous-scroll.md) | Sliding text is a second reading surface, driven by a ticker and dragged with a finger |
| [0026](0026-rate-limiting-the-authentication-endpoints.md) | The authentication endpoints are rate-limited by an in-process, IP-keyed filter |
| [0027](0027-refresh-token-revocation.md) | Refresh-token revocation is a `token_version` column, checked at refresh |
| [0028](0028-content-security-policy.md) | The web bundle ships a Content-Security-Policy restricting it to its own origin |
| [0029](0029-catalogue-ingested-and-searched-locally.md) | The Free books catalogue is ingested from Gutenberg's bulk exports and searched locally, never proxied live |
| [0030](0030-shared-spring-test-contexts.md) | The server's integration suite shares Spring test contexts instead of rebuilding one per class |
| [0031](0031-chrome-type-roles-on-a-base.md) | Chrome type is four roles expressed as ratios of a base, with every `TextTheme` slot declared |
| [0032](0032-colour-meanings-are-fixed-at-build-time.md) | Colour meanings are fixed at build time: a curated palette, a pinned error group, and the accent as a fill |
| [0033](0033-measure-and-control-proportion.md) | Every scrollable body takes a measure, and a control is sized as a control rather than a poster |
| [0034](0034-a-one-control-destination-is-a-row.md) | A Settings destination whose purpose is one control is a row, and the reader route is opaque |
| [0035](0035-reader-transport-names-itself.md) | On the reading surface hierarchy is size and position, and every transport control names itself in text (§2–3 superseded by 0037) |
| [0036](0036-chrome-prose-is-budgeted-in-blocks.md) | Chrome prose is budgeted in blocks: one sentence per control, one per section, checked by a test |
| [0037](0037-transport-controls-are-named-in-a-legend.md) | Transport controls are named in a legend behind one (i), and the first Play teaches the tap that pauses |
| [0038](0038-changing-a-preset-forks-it.md) | Changing a Preset forks it, and the Settings row opens the active profile's editor |
| [0039](0039-cloudflare-authenticated-origin-pulls.md) | Cloudflare's proxy is verified at the origin with Authenticated Origin Pulls, closing the direct-to-origin bypass and the rate-limit header forgery it enables |
