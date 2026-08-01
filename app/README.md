# app

The Flutter client for hereader. Android, Windows and web.

Everything interesting lives in the two Dart packages this depends on:
[`rsvp_engine`](../packages/rsvp_engine) decides what word to show and for how
long, [`epub_reader`](../packages/epub_reader) turns a book file into readable
blocks. This package holds screens, persistence and platform glue.

## Running it

```bash
flutter pub get
flutter run -d windows   # or -d chrome, or a connected Android device
```

## Layout

```
lib/
├─ data/
│  ├─ database.dart            Drift schema: books, positions, profiles, outbox
│  └─ library_repository.dart  The only file that knows drift exists
└─ reading/
   ├─ library_screen.dart      Import, list, open, remove
   ├─ library_book.dart        Import pipeline and the in-memory book model
   ├─ reader_screen.dart       Full-screen reading surface
   ├─ rsvp_view.dart           Draws one token at the profile's anchor
   └─ paste_reader_screen.dart Read arbitrary pasted text
```

After changing `data/database.dart`, regenerate:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## How a book gets read

The picker returns bytes, never a path, because the web has no file behind the
dialog and the bytes are what gets stored anyway.

Parsing and tokenizing run through `compute()` on a background isolate. Both
are CPU-bound and take long enough to drop frames on the UI isolate.

The EPUB bytes are stored; the parsed text is not. Parsed output is derived
data that a `kParserVersion` bump would invalidate, so the parser stays the
single source of truth and books are re-parsed each time they open. See
[ADR 0004](../docs/adr/0004-store-book-files.md).

`ReaderScreen` pops with a `Locator`, which the library writes to the database
in the same transaction as an outbox entry. A position on disk without a
queued event would never sync; an event without a position would sync a change
this device does not have.

## The paste screen

Not scaffolding. It is the quickest way to try the engine against arbitrary
text, including languages the tokenizer has not been tuned for, and it needs
no file on disk. It builds a throwaway one-block book and reuses the same
reader.

## Testing

```bash
flutter test
```

Widget tests open an in-memory database rather than mocking the repository, so
they exercise the real queries.

One quirk worth knowing: drift schedules a zero-duration timer when a query
stream is cancelled. If the widget tree is left to teardown, that timer is
never pumped and the framework reports a leaked timer. Tests that build the
library screen dispose the tree explicitly and pump with a duration.

## Not built yet

Settings screen, chapter navigation, and the sync client that drains the
outbox.
