# app

The Flutter client for hereader. Android, Windows and web.

Everything interesting lives in the two Dart packages this depends on:
[`rsvp_engine`](../packages/rsvp_engine) decides what word to show and for how
long, [`epub_reader`](../packages/epub_reader) turns a book file into readable
blocks. This package holds screens, persistence, sync, and platform glue.

## Running it

```bash
flutter pub get
flutter run -d windows   # or -d chrome, or a connected Android device
```

The app expects the sync service on `http://localhost:8080/api`. Point it
elsewhere at build time:

```bash
flutter run --dart-define=HEREADER_API=https://api.example.com/api
```

Signing in is optional. The app reads and writes fully offline; an account
only adds syncing a position and preferences between devices.

## Layout

```
lib/
├─ data/
│  ├─ database.dart            Drift schema: books, positions, pending
│  │                            positions, profiles, preferences, outbox,
│  │                            conflicts
│  └─ library_repository.dart  The only file that knows drift exists
├─ sync/
│  ├─ sync_engine.dart         Drains the outbox, applies remote events
│  ├─ api_client.dart          Calls the sync service, refreshes tokens
│  └─ auth_store.dart          Session storage: keystore on native, local
│                               storage on web
└─ reading/
   ├─ library_screen.dart      Import, list, open, remove
   ├─ library_book.dart        Import pipeline and the in-memory book model
   ├─ reader_screen.dart       Full-screen reading surface
   ├─ rsvp_view.dart           Draws one token at the profile's anchor. The
   │                            only definition of what reading looks like;
   │                            the settings preview draws through it
   ├─ settings_screen.dart     Profile list, presets separated from forks
   ├─ profile_edit_screen.dart One profile, with a live preview
   ├─ profile_presentation.dart ARGB helpers, polarity colours, WCAG ratio
   ├─ sign_in_screen.dart      Sign in or register, always skippable
   └─ paste_reader_screen.dart Read arbitrary pasted text
```

After changing `data/database.dart`, regenerate:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## How a book gets read

The picker returns bytes, never a path, because the web has no file behind the
dialog and the bytes are what gets stored anyway.

Parsing and tokenizing run through `compute()`, which puts them on a
background isolate on Android and Windows and *does not* on web: there,
`compute()` calls the function directly and wraps the result in a Future.
Both passes are CPU-bound and take a few hundred milliseconds on a novel, so
on the web build importing or opening a book freezes the page for that long.
Left as it is for now — a real web worker needs its own compiled entry point,
and chunking the parser with yields would reshape it for one target.

The EPUB bytes are stored; the parsed text is not. Parsed output is derived
data that a `kParserVersion` bump would invalidate, so the parser stays the
single source of truth and books are re-parsed each time they open. See
[ADR 0004](../docs/adr/0004-store-book-files.md).

`ReaderScreen` decides when the reader's place is worth recording — every stop,
every fifteen seconds of movement between them, and when the app is hidden —
and hands it to a callback. The library writes it to the database in the same
transaction as an outbox entry: a position on disk without a queued event would
never sync; an event without a position would sync a change this device does
not have. That transaction also drops any queued position event for the same
book that has never been sent, so the cadence above costs nothing on the wire.
See [ADR 0011](../docs/adr/0011-position-save-cadence.md).

## Sync

`SyncEngine` pushes the outbox, then pulls and applies whatever other devices
wrote, on a five-minute timer and whenever `syncNow()` is called directly. It
never blocks a reader: a failed push leaves the outbox intact, and a failed
pull leaves local state exactly as it was.

A position can arrive for a book this device has not imported — every web
client's first sign-in, since books never transfer between devices by design.
That position waits in `pending_positions`, a table with no foreign key to
`books`, and is moved into `reading_positions` the moment the matching book is
imported, in the same transaction as the import. See
[ADR 0007](../docs/adr/0007-pending-positions.md).

Each event in a pulled batch applies inside its own try/catch. One event that
fails to apply is counted and skipped rather than stalling every event behind
it, and `syncNow()` always resolves to a terminal `SyncStatus` — including on
an error neither `NetworkException` nor `ApiException` describes. An earlier
version of this code let such an error escape uncaught, which left the sync
indicator spinning indefinitely with no work actually running.

## Testing

```bash
flutter test
```

Widget tests open an in-memory database rather than mocking the repository, so
they exercise the real queries. `LibraryRepository` tests do the same for
pending positions specifically: holding one, draining it on import, and
stamp ordering in both directions.

One quirk worth knowing: drift schedules a zero-duration timer when a query
stream is cancelled. If the widget tree is left to teardown, that timer is
never pumped and the framework reports a leaked timer. Tests that build the
library screen dispose the tree explicitly and pump with a duration.
