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
├─ main.dart                    Startup: opens the database, restores the
│                                session and the clock, reads appearance
│                                before the first frame, starts sync. Also
│                                where HEREADER_API is read
├─ startup_failure.dart         Shown when any of that throws. Depends on
│                                nothing that can have failed — plain widgets
│                                and a pure colour function — because there
│                                is no widget tree left to report through
├─ app_shell.dart               The three tabs, the bar and the rail, and
│                                the cross-fade between them
├─ data/
│  ├─ database.dart             Drift schema, version 10: books (an EPUB or a
│  │                             note, told apart by sourceFormat), positions
│  │                             (with the chapter hint ADR 0018 adds), pending
│  │                             positions, covers, profiles, preferences,
│  │                             outbox, conflicts
│  ├─ database.g.dart           Generated. See build_runner below
│  └─ library_repository.dart   The only file that knows drift exists
├─ net/
│  └─ http_transport.dart       The shared HTTP transport: error mapping,
│                                timeout, and JSON body decoding, called by
│                                both api_client.dart and catalogue_client.dart
├─ sync/
│  ├─ sync_engine.dart          Drains the outbox, applies remote events
│  ├─ api_client.dart           Calls the sync service, refreshes tokens,
│                                layering auth and 401-retry over net/http_transport.dart
│  ├─ auth_store.dart           Session storage: keystore on native, local
│  │                             storage on web
│  ├─ last_synced.dart          How long ago a sync finished, in words rather
│  │                             than a timestamp, and coarse on purpose
│  ├─ position_conflict_sheet.dart  Two positions, each resolved against this
│  │                             device's own copy of the book rather than
│  │                             shown from the payload's unverified hint
│  └─ sign_in_screen.dart       Sign in or register, always skippable
├─ theme/
│  ├─ app_colors.dart           Neutral ramps, the six accents, buildScheme
│  ├─ app_icons.dart            Every glyph the app draws, named by role.
│  │                             Two vendored Phosphor weights, Light and
│  │                             Fill, addressed by const IconData
│  ├─ app_tokens.dart           Spacing, radii, durations, hairline widths,
│  │                             and the app's two shadows
│  ├─ app_typography.dart       The type scale
│  ├─ app_theme.dart            ThemeData and every component theme.
│  │                             AppChromeSource, a ThemeExtension, carries
│  │                             the reader's accent and contrast choice
│  │                             down to the reader screen, since buildScheme
│  │                             folds both into a ColorScheme and cannot
│  │                             report either back out
│  ├─ page_transitions.dart     Routes fade and scale two percent rather than
│  │                             sliding a full screen width, because judder
│  │                             is a position error integrated over time and
│  │                             a long slow translation is the worst case a
│  │                             web build can draw
│  └─ appearance.dart           Theme mode, accent and high contrast: stored,
│                                read before the first frame, notified from.
│                                Device-local, each write passing sync: false
└─ reading/
   ├─ home_screen.dart          The book you were last in, and four you read
   │                             before it. Empty state opens the same
   │                             AddMenu the library does
   ├─ library_screen.dart       Import, list, open, remove, edit a note,
   │                             sort, and filter by format
   ├─ library_book.dart         Import pipeline, the in-memory book model,
   │                             and BookSourceFormat — an EPUB parses
   │                             through EpubParser, a note through
   │                             HtmlNormalizer directly
   ├─ add_menu.dart             The four-way add dialog (Free books/EPUB/
   │                             note/paste), shared by the library's add
   │                             button, the library's empty state and Home's
   ├─ free_books_screen.dart    Full-screen Gutenberg Catalogue search and
   │                             browse, opened from AddMenu. Debounced live
   │                             search, most-downloaded default, import
   │                             straight into the Library
   ├─ note_editor_screen.dart   Write a note, or edit one already stored
   ├─ book_cover.dart           Covers, and the generated face for a book
   │                             that declares none
   ├─ book_progress.dart        What the reader is told about their place:
   │                             the bar, the percentage, the time left, and
   │                             a note's own Added/Edited date
   ├─ book_opener.dart          The one path from a book id to the reader.
   │                             Not a navigation call: it syncs, settles a
   │                             waiting divergence, reads the bytes,
   │                             re-parses by source format and re-reads the
   │                             position before anything is pushed
   ├─ paste_reader_screen.dart  Read arbitrary pasted text, without storing it
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
   ├─ reading_display.dart      Whether a tile's time counts down to the end
   │                             of the chapter or the end of the book. One
   │                             preference, in the AppearanceController
   │                             shape, because Home and Library both listen
   ├─ reading_settings_screen.dart  What the app does while a book is open —
   │                             one setting, and the rest stated rather than
   │                             configured. What is ruled out here is a
   │                             setting whose wrong value costs the reader
   │                             their place, not a preference as such
   ├─ profile_actions.dart      Duplicate and delete a profile, including
   │                             the delete confirmation copy, in
   │                             BookOpener's stateless shape — called by
   │                             both ReaderScreen and ProfilesScreen instead
   │                             of each carrying its own copy
   ├─ profiles_screen.dart      Profile list, presets separated from forks
   ├─ profile_edit_screen.dart  One profile, with a live preview
   ├─ appearance_screen.dart    Theme, accent and contrast for app chrome.
   │                             Its own preview, since every control here
   │                             rethemes the app on the frame it is tapped
   ├─ custom_accent_screen.dart An accent outside the six named ones. Needed
   │                             no migration: the stored form has always
   │                             been six hex digits rather than a name
   ├─ rgb_sliders.dart          A colour as three sliders — long tracks rather
   │                             than a two-dimensional field, for readers who
   │                             cannot reliably hit a small target. The one
   │                             RGB picker, used by custom_accent_screen.dart
   │                             and the profile editor's background field
   ├─ sync_screen.dart          What sync has done and a way to run it now.
   │                             Reports rather than configures, and shows no
   │                             count of what is waiting — see Sync below
   ├─ account_screen.dart       The session, the device, and the way in and
   │                             out of an account. Signing out keeps books
   │                             and places, and the dialog says so
   └─ about_screen.dart         What this is, what it is built on, and what
                                 it does not claim. No version number: the
                                 app carries no real one
```

Settings subpages sit in `reading/` beside the reader rather than in a folder
of their own. Most of them configure a reading profile, and the ones that do
not are reached from the same index.

Icons are named by role rather than by picture. `theme/app_icons.dart` is the
only file that knows a codepoint or a font family, so `AppIcons.chapters` is
what a screen asks for and the weight is decided once. The set is Phosphor at
Light, with Fill standing in for selection on the six glyphs that need a
selected state. The fonts are vendored under `assets/fonts/` because
`phosphor_flutter` extends `IconData`, which is now a final class and so
rejects the package on import. See
[ADR 0019](../docs/adr/0019-icons-are-two-vendored-phosphor-weights.md).

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

The save is skipped when the token index has not moved since the last one, so
glancing at an open book and closing it writes nothing — except on the
transition into `finished`, which forces it through. That exception is the
whole rule for a one-token text, where the index never moves away from the
value it was seeded with at open and the guard silently ate every completion
write. The state transition was the fact worth keying on; the index was a
proxy that happened to work for every book long enough to look like the rule.

There are two reading surfaces, and `ReadingSurface` is the one place that
decides which a profile draws — the reader and the settings preview both call
it, so the contrast readout beside the preview cannot end up measuring a pair
the reader never sees. The switch is exhaustive with no `default`, so a fourth
`PresentationMode` is a compile error in exactly one file.

Under sliding text the book is one unbroken line moving right to left at a
steady speed past a fixed eye point, marked by a caret beside the line rather
than over it — above, below or both, solid, outline or chevron, at a distance,
a size and (for outline and chevron) a stroke thickness the reader sets, all
independent of one another, in the accent colour where that can be told apart
from the background and in the surface ink where it cannot. Reaching the end
of the book clears the caret along with the line, rather than leaving it
pointing at text that stopped moving. A `Ticker` supplies the time and
`PlaybackSession` keeps the position; about sixty tokens around the anchor are
measured at a time, never the book. Dragging a finger scrubs 1:1 — the pointer
landing pauses immediately, from a raw `Listener` rather than `onTapDown`,
which is deferred by up to `kPressTimeout` — and lifting it stops where it was
released, with no fling. A tap that was not a drag starts or stops. The three
tap zones are not built in this mode; the four jump buttons, the chapter
drawer and the keyboard bindings are unchanged. See
[ADR 0025](../docs/adr/0025-continuous-scroll.md).

The reader's profile sheet carries a switch for sliding text that has to be
reversible: turning it on for a preset forks it, and turning it back off
returns to the preset rather than leaving the reader on a fork still named
after the mode they just turned off. The pairing is computed by value rather
than stored, in `mode_fork.dart` — a fork identical to its preset in
everything but id, name and mode *is* that preset, so nothing needs
remembering. A fork the reader has only changed the caret settings on is kept
rather than deleted, since those controls exist only under sliding, and is
found and reused the next time the switch goes on rather than duplicated.

Under one word at a time the reading surface is three regions, split
25 / 50 / 25. The left and right quarters step back and forward and stop
there; the centre half keeps play, pause and the elicited advance. `arrowLeft` and `arrowRight` do the same two
things as the edges, so a reader on a keyboard or a switch is not on a
different set of controls from a reader with a thumb.

How far one step moves is `ui.step_words`, set on Settings › Reading, device
local and defaulting to one word. It is not the profile's `rewindWords`, which
answers a different question — how far a *resume* re-enters the sentence after
a pause — and stays with the profile because it belongs to a reading style
rather than to an input.

Every reader-driven move — the tap zones, the four jump buttons, a chapter
choice, and the offer back into front matter — goes through
`PlaybackSession.stopAt`, which stops where it lands and suppresses exactly
one resume rewind. Without that, a step forward followed by pressing play
would leave the reader behind where they started, since the resume out of
`paused` applies `rewindWords` on the way. See
[ADR 0020](../docs/adr/0020-reader-driven-navigation.md) and
[ADR 0022](../docs/adr/0022-chapter-jumps-also-suppress-the-resume-rewind.md).

The controls sit in three rows below the progress bar. A nav row of four
jumps — back a paragraph, back a sentence, forward a sentence, forward a
paragraph — sits above a row of close, play and profile. Each jump disables at
the end it cannot reach rather than offering one that goes nowhere. Back a
sentence and back a paragraph restart the unit the reader is in the first time
they are pressed, and only reach the one before it once already on that unit's
first word — the "previous track" rule a media player applies to skip-back,
picked because re-reading a missed sentence is the more common need. `Ctrl` and
`Shift` with the arrow keys reach the same four jumps from a keyboard. See
[ADR 0015](../docs/adr/0015-reader-chrome-is-monochrome-over-the-profile.md),
[ADR 0020](../docs/adr/0020-reader-driven-navigation.md) and
[ADR 0021](../docs/adr/0021-back-a-sentence-back-a-paragraph.md).

## Notes

A note is a row in `books` like any other, told apart by `sourceFormat`:
its text lives as UTF-8 in the same `bytes` column an EPUB's zip goes in.
On open — writing it for the first time, or reopening a stored one — the
text is split into blank-line-separated paragraphs, escaped, wrapped in
`<p>` tags, and run through the same `HtmlNormalizer` a spine document goes
through, so a note gets real, stable block ids and the same locator
guarantee ADR 0002 gives a book, rather than a bespoke path of its own.
Title and id cannot come from the bytes the way an EPUB's do — there is no
OPF — so both travel in from whoever is asking to reopen it.

Editing rewrites title, bytes and word count through a plain update, never
through `addBook`'s upsert, which would bump `importedAt` on every edit.
`Books.updatedAt` is nullable with no backfill, since null and "edited at
the moment it was imported" are different facts, and it is what the library
reads to show "Added" or "Edited" on a note's tile, in the space an EPUB's
author line leaves empty.

Whether an edit resets the reader's saved position is decided by the editor
screen, not the repository: it holds both the old and new text, so it can
tell a title-only change from one that actually moved the words underneath
a saved place, and only the second asks the reader to confirm — and only
when there was a place to lose. See
[ADR 0017](../docs/adr/0017-local-notes.md).

The library's format filter — All, Books, Notes — is client-side over the
list already streamed for sorting, and persisted the way sort is. It carries
its own empty state rather than reusing the library's: a reader filtered to
Notes with none yet is looking at a different fact than an empty library, so
they get "No notes yet" and a button straight to the editor rather than the
three-way menu asking them to repeat a choice the filter already made, and
the controls row stays on screen so All is always one tap back. Saving into
a filter the result would not appear under resets it to All, but only when
the save was real and only when the addition would otherwise be invisible.

## What the home screen knows

The tile says how far into the book the reader is and roughly how long is
left, and it works both out without parsing anything. A saved position
carries how many tokens into the book it is and the book row carries how
many there are, so progress is `(tokenIndex + 1) / wordCount` — the count of
words already seen, not the index of the one on screen, which is the
correction that stops a finished book or note from reading as 99% forever —
and the words still ahead are one subtraction against the same count. See
[ADR 0013](../docs/adr/0013-progress-token-index.md).

Turning those words into minutes needs a rate, and the rate is whatever the
reader's active profile is set to, so the figure moves when they retune it.
Under reader-elicited advance there is no rate at all and the tile says how
many words are left instead. See
[ADR 0014](../docs/adr/0014-reading-time-estimate.md).

The chapter beside that figure is the one exception to working everything out
from two columns. Chapters are resolved from a parse (ADR 0010) and books are
not parsed until they are opened (ADR 0004), so the reader screen writes the
chapter down with the position and Home reads it back. It is a display hint on
the same terms the token index is: never navigated by, stale after a
`kParserVersion` bump until the next save, and cleared by every write path
that is not the reader — a position arriving from another device carries no
chapter, and keeping the old one would name where the reader used to be. See
[ADR 0018](../docs/adr/0018-chapter-hint-on-a-tile.md).

Which end the figure counts to is `ui.time_left_scope`, and the chapter is
drawn either way, so the words beside the number always say what the number
is about.

The active profile is a pointer in `preferences` naming a row in
`stored_profiles`, so anything derived from it watches both tables.
`watchActiveProfile` does that with one query whose stream drift invalidates
on a write to either. The library screen holds the same subscription, since
its tiles carry the same figure.

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
opens the app to see the result of. `sync/sync_button.dart` is what those bars
built, and it is gone: a widget nothing constructs reads as a screen someone
forgot to wire up rather than as a shape held in reserve, and git remembers it
if a bar ever comes back. The library keeps the gesture without the readout,
since a reader who has just put down another device should not wait five
minutes for the timer: pulling the shelf down runs a sync.

`SyncScreen` shows no count of what is waiting to be sent. `SyncState` carries
none — the field that always read zero was removed rather than fixed — and the
outbox query the repository exposes is limited and skips parked events, so a
number taken from it would answer a narrower question than the label on it
would claim.

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

**The reader chrome, the library controls and the note editor are verified on
Windows only.** Nothing in any of them animates or translates a large area,
which is the shape Chrome's main-thread throttle actually reaches, but that is
an expectation rather than a result.

**Sliding text does translate a large area, every frame, and it has not been
measured on a phone.** It is the first thing in this app that animates
continuously, so the root README's claim that reading is unaffected by
Chrome-on-Android's main-frame throttle no longer covers both surfaces — it is
corrected there. What is done structurally: a `RepaintBoundary`, a painter
driven by `CustomPainter(repaint:)` so no widget rebuilds between token
crossings, and the text measured about once every forty tokens rather than per
frame. What is not done is a number from `HEREADER_FRAME_STATS` on a real
device. See ADR 0025.

**Sliding text runs left to right only.** `measureRun` and `MarqueePainter`
take `TextDirection.ltr` explicitly rather than reading the ambient
`Directionality`, which would mirror shaping within each token while the run
itself still travelled right to left. Consistently wrong beats
half-mirrored — the same discipline `app_icons.dart` applies to
`matchTextDirection`.

**The sliding surface gives a screen reader nothing the fixed anchor did
not.** It is one node with `onTap`, `onIncrease` and `onDecrease`, and the
step actions have the same standing as ADR 0020's keyboard bindings: covered
by a widget test group and by no real assistive technology. Continuous scroll
is a visual presentation; anyone who needs speech rather than sight is better
served by the whole book read aloud.

## Testing

```bash
flutter test
```

runs the suite on the Dart VM. A second command runs the same suite in a real
Chrome instead:

```bash
dart run tool/stage_chrome_test_assets.dart
flutter test --platform chrome --timeout 60s $(grep -L "@TestOn('vm')" test/*_test.dart)
```

The staged copies are gitignored and made fresh each time, because
`flutter_tools` serves `<cwd>/test` at the test server's root rather than
`<cwd>/web` — `test/` is the only directory the in-browser runner can reach.
`flutter-nightly.yml` and `cd.yml`'s `browser-test` job both run the same
script rather than each keeping its own copy step, so staging is written
down once. CI runs this step nightly on `main` and as a gate on the release
tag rather than on every pull request; see ADR 0009. The file list leaves
out the
`@TestOn('vm')` suites rather than relying on the annotation to skip them:
`flutter test --platform chrome` compiles every discovered test file into
one shared bundle before `@TestOn` filtering ever runs, so a suite that
imports `dart:ffi` or `dart:io` — `schema_migration_test.dart` needs a real
file on disk to prove a migration survives a reopen, `web_shell_colors_test.dart`
reads `web/index.html` — breaks the whole compile even though it would never
execute on this platform. Reading the annotation with `grep -L` keeps the
exclusion in one place instead of two. See ADR 0009.

The module is fetched once per suite by `test/flutter_test_config.dart`,
before `main()`, and not on demand: a `testWidgets` body runs inside
`FakeAsync`, which cannot advance a real network fetch, so a lazily-loaded
executor hangs there until the runner's timeout rather than failing. This is
also why `testExecutor()` is synchronous — if the warm-up is ever skipped it
throws and says so.

**The second staged copy is CanvasKit, and only Windows needs it.** Without
it the run compiles, launches Chrome and then hangs at zero CPU with
no output. `flutter_tools`' `_localCanvasKitHandler`
(`flutter_web_platform.dart:518`) builds its path with
`_fileSystem.path.fromUri` and then guards on `startsWith('canvaskit/')` —
on Windows that is a backslash-separated path, so the guard never matches
and the engine's own bootstrap gets a `404` for `canvaskit/chromium/
canvaskit.js`. Nothing downstream of engine initialization then proceeds.
The next handler in the server cascade serves `<cwd>/test` and builds its
path correctly, so a copy of the SDK's `canvaskit` directory there is what
gets served instead. It is gitignored, and CI does not need it —
both `flutter-nightly.yml` and `cd.yml` run on `ubuntu-latest`, where the
path context is posix and the handler's guard matches, so the script skips
this half there.

That asymmetry is why the step is a script rather than a line in this file.
The Windows copy is invisible to CI by construction, so nothing fails when
it is forgotten — the run just hangs, with no error naming a cause. #192 was
filed against exactly that, on a checkout whose README already described the
fix five hundred lines in.

The Chrome run compiles with DDC, not `dart2js` — the compiler the deployed
web build actually uses — so it proves app code runs in a browser at all, not
that it survives `dart2js`'s narrower integer semantics. That half of the
arithmetic risk stays where ADR 0009 puts it: in `rsvp_engine` and
`epub_reader`, proven under `dart test -p chrome`.

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

`app_theme_test.dart` asserts that the neutral ramp is byte-identical under
all six accents, which is the whole claim `buildScheme` exists to make and the
one `ColorScheme.fromSeed` could not.

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

A third: a widget test awaiting `BookImporter`'s real `compute()` isolate
never sees it resolve under ordinary `pump()` calls, however many or however
long — the isolate's message port is not something the test binding wakes on
by itself. `tester.runAsync` is the documented way out, but the tap that
starts the work and the wait for it to finish have to sit inside *one*
`runAsync` call; splitting them across two does not carry the port across.
Confirmed on a minimal probe. Not yet made to work for the note editor's own
save-and-open flow at its full depth (the add-menu dialog, the editor,
`BookOpener`'s sync and conflict checks, then the reader it pushes), which is
why that path has no automated test and the library's filter-reset-on-save
behaviour is checked by reading the code rather than by a test exercising it
end to end. `library_filter_test.dart` does cover the cancel path, which
reaches no isolate.
