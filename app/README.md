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
├─ main.dart                    Startup: opens the database, reads appearance
│                                before the first frame, starts sync
├─ startup_failure.dart         What the app shows when that fails, rather
│                                than a blank window
├─ app_shell.dart               The three tabs, the bar and the rail, and
│                                the cross-fade between them
├─ data/
│  ├─ database.dart             Drift schema: books, positions, pending
│  │                             positions, covers, profiles, preferences,
│  │                             outbox, conflicts
│  ├─ database.g.dart           Generated. See build_runner below
│  └─ library_repository.dart   The only file that knows drift exists
├─ sync/
│  ├─ sync_engine.dart          Drains the outbox, applies remote events
│  ├─ api_client.dart           Calls the sync service, refreshes tokens
│  ├─ auth_store.dart           Session storage: keystore on native, local
│  │                             storage on web
│  ├─ sync_button.dart          Status and a manual run, as one control
│  ├─ last_synced.dart          How long ago the last finished run was
│  ├─ position_conflict_sheet.dart  Two positions, for the reader to choose
│  │                             between when devices diverge
│  └─ sign_in_screen.dart       Sign in or register, always skippable
├─ theme/
│  ├─ app_colors.dart           Neutral ramps, the accent list, buildScheme
│  ├─ app_tokens.dart           Spacing, radii, durations, hairline widths,
│  │                             and the app's one shadow
│  ├─ app_typography.dart       The type scale
│  ├─ app_theme.dart            ThemeData and every component theme.
│  │                             AppChromeSource, a ThemeExtension, carries
│  │                             the reader's accent and contrast choice
│  │                             down to the reader screen, since buildScheme
│  │                             folds both into a ColorScheme and cannot
│  │                             report either back out
│  ├─ page_transitions.dart     Routes fade and scale rather than sliding
│  ├─ rgb_sliders.dart          Three channel sliders, shared by the screens
│  │                             that pick a colour
│  └─ appearance.dart           Theme mode, accent and high contrast: stored,
│                                read before the first frame, notified from
└─ reading/
   ├─ home_screen.dart          The book you were last in, and four you read
   │                             before it
   ├─ library_screen.dart       Import, list, open, remove
   ├─ library_book.dart         Import pipeline and the in-memory book model
   ├─ book_cover.dart           Covers, and the generated face for a book
   │                             that declares none
   ├─ book_progress.dart        What the reader is told about their place:
   │                             the bar, the percentage, and the time left
   ├─ book_opener.dart          The one path from a book id to the reader
   ├─ paste_reader_screen.dart  Read arbitrary pasted text
   ├─ reader_screen.dart        Full-screen reading surface
   ├─ rsvp_view.dart            Draws one token at the profile's anchor. The
   │                             only definition of what reading looks like;
   │                             the settings preview draws through it. Takes
   │                             a ResolvedPresentation, so a profile that
   │                             follows the app arrives with a polarity
   │                             already chosen
   ├─ profile_presentation.dart Polarity colours, reader chrome theme,
   │                             readerInkArgbFor for controls drawn straight
   │                             on the surface, and readerProgressFillFor /
   │                             readerTrackFor for the one accented control
   │                             on the screen. ResolvedPresentation and
   │                             resolvePresentation live here too: a profile
   │                             may state no polarity, and this is where one
   │                             gets decided. The ARGB helpers and WCAG
   │                             maths it used to hold live in rsvp_engine,
   │                             so they run in a browser
   ├─ settings_screen.dart      An index of sections, each its own subpage
   ├─ reading_settings_screen.dart  The reading section of that index
   ├─ profiles_screen.dart      Profile list, presets separated from forks
   ├─ profile_edit_screen.dart  One profile, with a live preview
   ├─ appearance_screen.dart    Theme, accent and contrast for app chrome
   ├─ custom_accent_screen.dart An accent outside the six built in
   ├─ sync_screen.dart          Sync state and a manual run, in settings
   ├─ account_screen.dart       Session and sign out
   └─ about_screen.dart         What this is, and what it does not claim
```

Settings subpages sit in `reading/` beside the reader rather than in a folder
of their own. Most of them configure a reading profile, and the ones that do
not are reached from the same index.

App chrome and the reading surface are themed separately and on purpose.
`theme/` builds the app around the books from a neutral ramp plus one accent
the reader picks. `readerChromeTheme` builds the reading surface from a
brightness the reading profile decides, so a book set to light on dark keeps
dark chrome on a device set to light. See
[ADR 0015](../docs/adr/0015-reader-chrome-is-monochrome-over-the-profile.md).

A profile need not decide, and by default the two most general presets do not.
`PresentationConfig.polarity` is nullable: null says the reader stated no
preference, and the screen drawing it supplies one from the brightness the app
is running in. A dark app opens a book onto a dark page. The presets whose
citations pick a surface, `Central field loss` and its timed variant and
`Low fatigue`, state their polarity and keep it inside a light app. Following
the app means taking its brightness rather than its colours: the reading
surface keeps its own pair, which is what the contrast readout in settings
measures. See
[ADR 0016](../docs/adr/0016-reader-theme-follows-the-app.md).

`ResolvedPresentation` is how that stays honest. It is an extension type over a
config whose polarity is decided, `resolvePresentation` is the only way to make
one, and every function that paints takes it. Each screen resolves once near
the top of `build` and passes the result down, so the reading surface, the
settings preview and the WCAG readout cannot disagree about which colours are
on screen. That disagreement has happened here before, between `RsvpView`'s own
ink constants and the readout measuring a different pair, and a comment saying
where resolution belongs would not have caught it.

The two screens are not otherwise isolated from each other. `readerChromeTheme`
takes the app's own accent and contrast setting, carried down through
`AppChromeSource`, and folds them into the same neutral ramp app chrome uses.
Controls drawn straight onto the reading surface, the playback buttons and the
chapter glyph, take no accent at all; their colour is `readerInkArgbFor`,
picked from the surface's own luminance so a glyph stays legible against
whatever a reader has tinted the background. The progress bar is the one
exception, and even there the accent gives way to the ink wherever it cannot
clear 3:1 against its own track.

Accent is scarce by design. On a given screen it marks the one action or the
one measurement worth marking, the progress fill on the home tile, the dot
under the selected tab, the progress fill on the reading surface, the add
button on the library. Surfaces are separated with hairlines rather than
elevation, and two objects carry a shadow instead because a line cannot seat
them: `AppShadow` under Home's continue tile, which sits alone in open space
with nothing to align to, and `AppFloatShadow` under the library's add button,
which floats over covers it cannot predict. Each token says so itself.

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

Rewind is `arrowLeft`, stepping by the active profile's `rewindWords`. The
reading surface has no rewind button: left and right tap zones are meant to
replace it and are not built yet, so a keyboard, a switch, or a screen reader
is the only way back until then. See
[ADR 0015](../docs/adr/0015-reader-chrome-is-monochrome-over-the-profile.md).

## What the home screen knows

The tile says how far into the book the reader is and roughly how long is
left, and it works both out without parsing anything. A saved position
carries how many tokens into the book it is and the book row carries how many
there are, so progress is one division and the words still ahead are one
subtraction. See [ADR 0013](../docs/adr/0013-progress-token-index.md).

Turning those words into minutes needs a rate, and the rate is whatever the
reader's active profile is set to, so the figure moves when they retune it.
Under reader-elicited advance there is no rate at all and the tile says how
many words are left instead. See
[ADR 0014](../docs/adr/0014-reading-time-estimate.md).

The active profile is a pointer in `preferences` naming a row in
`stored_profiles`, so anything derived from it watches both tables.
`watchActiveProfile` does that with one query whose stream drift invalidates
on a write to either.

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

Sync reports itself in one place, the Sync section of Settings: what the last
run did, when it finished, and a button to run one now. Home carried a copy of
that state and dropped it in the UI pass; the library dropped its own with the
app bar. Keeping four statuses in step across three screens is work nobody
opens the app to see the result of. The library keeps the gesture without the
readout, since a reader who has just put down another device should not wait
five minutes for the timer: pulling the shelf down runs a sync.

## Known limitations

**A profile set to follow the app renders differently on two synced devices.**
Theme mode is device-local under ADR 0012, so one profile draws light on a
phone set light and dark on a desktop set dark. That is the intended
consequence rather than a defect, and it is written down so nobody has to work
it out from the code.

**A client older than the nullable polarity field pins a following profile.**
It reads the absent key as its own default, and because profiles merge whole
under ADR 0008 it writes that pin back on its next edit of the same profile. No
wire format avoids this: an older `PresentationConfig.fromJson` drops any key
it has no field for. See
[ADR 0016](../docs/adr/0016-reader-theme-follows-the-app.md).

**The progress fill on the reading surface can go monochrome without saying
so.** `readerProgressFillFor` falls back to the surface ink wherever the
reader's accent cannot clear 3:1 against its own track, and the accent and the
background are set on two screens that know nothing about each other. Unlike
contrast and fade, this is not warn-don't-block: there is no reading for the
reader to see and override, only a colour that quietly is not the one they
picked. ADR 0016 widens the set of backgrounds this can happen on, since one
profile now reaches both polarity defaults on one device.

**Web imports block the interface.** `compute()` does not offload on Flutter
web; see the note under how a book gets read.

## Testing

```bash
flutter test
```

Widget tests open an in-memory database rather than mocking the repository, so
they exercise the real queries. `LibraryRepository` tests do the same for
pending positions specifically: holding one, draining it on import, and
stamp ordering in both directions.

`reader_chrome_test.dart` measures the reading surface's colours rather than
its widgets: `readerInkArgbFor` against every preset and a spread of tints
around the point where the better overlay flips, and `readerProgressFillFor`
against its own track across all six accents, since that pair is the one
place an arbitrary reader-chosen background meets an accent nothing else on
the screen has to contend with. Every preset is measured under both app
themes, because two of them state no polarity and reach a different surface in
each.

`reading_surface_test.dart` covers what actually gets painted. It pumps
`ReaderScreen` under a dark app theme and reads the colour behind the word,
naming no polarity anywhere: the book opens on `Presets.standard`, so the page
can only have come from the theme.

The smoke test identifies chrome by key rather than by widget type where the
widget is this project's own: `homeContinueTileKey` for the home tile,
`appNavBarKey` for the bottom bar, `readerPlayButtonKey` for the reading
surface's play button, `profileFollowAppKey` for the switch that puts a profile
back to following the app theme, `libraryAddButtonKey` for the button that
opens the library's add menu. Matching a button's label instead was asserting
two things at once, and for the play button the label itself changes with
playback state, which made the match brittle on top of being imprecise.

One quirk worth knowing: drift schedules a zero-duration timer when a query
stream is cancelled. If the widget tree is left to teardown, that timer is
never pumped and the framework reports a leaked timer. Tests that build the
library screen dispose the tree explicitly and pump with a duration.

A second quirk, found the same way: `scrollUntilVisible` resolves its default
`scrollable` argument to the one `Scrollable` in the tree and throws when it
finds several. A screen with a `TextField` on it has two, since `EditableText`
builds its own. Name the scrollable rather than letting it default.
