# 0001. Monorepo with separate pure Dart packages

Status: accepted
Date: 2026-07-27

## Context

The project has three components: a Flutter app, a reading engine, and an
EPUB parser. The engine and parser hold the logic worth testing and worth
reading.

## Options

1. Single Flutter project with everything under `app/lib/`.
2. Separate repositories per component.
3. Monorepo containing plain Dart packages that the Flutter app depends
   on by path.

## Decision

Option 3.

## Consequences

Positive:

- Engine tests run with `dart test` in under a second, with no widget
  harness and no Flutter SDK required in CI.
- The core logic cannot accidentally acquire a UI dependency, because the
  packages do not import Flutter at all.
- `rsvp_engine` could be published to pub.dev independently.
- One repository means one issue tracker, one CI configuration, and one
  place for a reviewer to look.

Negative and accepted:

- Dependencies are wired with path references, which need converting to
  version references if a package is ever published.
- A release process would have to keep package versions aligned with the
  app.
