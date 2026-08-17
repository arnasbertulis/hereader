# 15. Reader chrome is monochrome over the profile, with one accent

Date: 2026-08-17

## Status

Accepted. Supersedes the accent argument in `profile_presentation.dart`'s
chrome section. Pushes local notes from ADR 0015 to ADR 0016.

## Context

Every control on the reading surface was purple under every profile: the
chapter button, the three playback buttons, the progress bar, the chapter
panel and the profile sheet.

Two faults stacked. `readerChromeSeed` held `0xFF6750A4`, which is
`ColorScheme.fromSeed`'s own baseline, so nobody had replaced the placeholder
the file was written with. Its doc comment stated the right intent and the
value never followed, which is the failure this file already records against
its own ink constants. Under it, `readerChromeTheme` called `fromSeed`
directly, and the default `tonalSpot` variant tints surface and container
roles with whatever seed it is given. `buildScheme` exists in
`app_colors.dart` because of that variant. The reader screen never adopted
it.

Replacing the constant alone would have moved the wash rather than removed
it, so this changes the arrangement.

The redesign that came with it: no filled disc behind any glyph, no rewind
button, `Icons.menu` for chapters, and three buttons rather than four.

## Decision

**Glyphs take their colour from the surface's luminance.** `readerInkArgbFor`
returns `darkInkArgb` or `lightInkArgb` by the same 0.179 threshold
`chromeBrightnessFor` already used. The filled tonal disc gave each glyph a
known background to contrast against; without it a glyph sits on whatever the
background field accepted, which is arbitrary RGB.

**The bar is WCAG 1.4.11's 3:1, not 4.5:1.** Nothing on the reading surface
is text any more. The play button's label came off with the disc, because a
label would have to hold 4.5:1 against an arbitrary tint and the threshold
case cannot promise it. State moved into the tooltip and into
`_surfaceLabel`.

**Hierarchy is size.** Play at 44, exit and profile at 28, both inside
`IconButton`'s 48dp minimum. Colour cannot carry hierarchy on a screen with
one ink.

**Panels take the app's neutral ramp through `buildScheme`,** at a brightness
from the profile rather than from the platform. The drawer, the sheet and the
front matter offer have backgrounds of their own, so they read like the rest
of the app. `_FrontMatterOffer` moved off `secondaryContainer`, an accent
role, onto `surfaceContainerHigh` with a hairline, since it is the one place
on this screen carrying a paragraph.

**The accent reaches one thing: `scheme.primary` on the progress fill,** plus
the selected chapter row inside a panel. `scheme.primary` rather than the raw
hex, because `fidelity` at the surface's own brightness lightens the accent
against a dark tint and darkens it against a light one.

**The accent arrives through `AppChromeSource`, a `ThemeExtension` on
`appTheme`.** It carries the accent as the reader picked it and whether
contrast was raised. `buildScheme` folds both into every role and can report
neither back.

**Rewind moved to `arrowLeft` and steps by `ReadingProfile.rewindWords`.** The
button passed a hardcoded 5 while that field decided how far a resume steps
back. Tap zones on the left and right of the surface replace the button, and
are not in this change.

**The progress fill falls back to the ink where the accent cannot read.**
`readerProgressFillFor` measures `scheme.primary` against `readerTrackFor`'s
composite and returns the ink instead when that pair misses 3:1. Falling
back to the ink rather than to a lightened accent, because a washed accent
is still an accent and would report a colour the reader did not choose;
monochrome is what the rest of the screen already is on the backgrounds that
force it.

**The track is 0.16 ink over the surface, not 0.24.** Set by the fallback's
own requirement rather than by appearance: at 0.24, the ink itself reaches
only 2.93 against the track on the tints the guard exists for, which would
have the fallback fail the bar it falls back to. At 0.16 the worst case
across the backgrounds this ADR tests is 3.31, and the track still separates
from the surface by 1.26 to 1.55, which reads as a groove rather than a
second bar.

## Alternatives rejected

**Give `readerChromeSeed` a grey and keep `fromSeed`.** What
`next-session-context.md` proposed. `tonalSpot` tints from any seed, so this
produces a grey-washed panel rather than the ramp, and leaves the reader
screen with a second definition of what a surface looks like.

**Pass a neutral into `buildScheme` as the accent.** `fidelity` holds the
seed's chroma, so a near-grey accent yields a near-grey `primary`. The
progress fill and the panel's selected row lose their accent and the screen
has no measurement colour at all.

**Keep the accent off the reading surface entirely.** The position this file
held until now, on the grounds that a moss background under a rust accent
puts two chosen colours side by side. That argument was made against four
tonal fills and a full-width bar. Against one measurement it costs more than
it buys: the fill is the only thing on the screen reporting a quantity, and
Home already establishes that the accent goes on the progress fill.

**No guard: let `scheme.primary` paint the fill regardless of what it lands
on.** The position this ADR held on first merge, on the grounds that a
threshold would make the bar change colour as the reader drags the RGB
picker. That objection was wrong about the screen: `_Preview` in
`profile_edit_screen.dart` draws `RsvpView` and the contrast readout while
dragging, not the reading surface's own controls, so the bar in question is
never visible during the drag it was rejected to protect. `reader_chrome_test.dart`
then measured six accents against nine reachable backgrounds and found
`primary` at 1.92 against its track on a tint near the 0.179 flip, which is
below the 3:1 this ADR requires everywhere else on the screen. `readerProgressFillFor`
replaces this: the accent by default, the ink where `primary` cannot clear
the bar.

**Thread `AppearanceController` into `BookOpener`.** `BookOpener` holds a
repository and a sync engine, so this means a constructor argument through
`HomeScreen` and `LibraryScreen` for one colour. It also misses the platform
path: a reader who set high contrast in the operating system reaches
`highContrastTheme`, which the controller does not know about and the theme
extension does.

**Outlined buttons rather than bare glyphs.** A hairline ring is not a filled
disc, and section 7 of the summary describes this as where the reader pass
was heading. Three rings in a row read as three equal controls, which is the
opposite of what removing the fills was for, and the ring competes with the
progress bar directly above it.

## Consequences

`AppChromeSource.fallback` repeats `AppAccents.ink`'s hex, because a static
const cannot read `.color` off a const `AppAccent`. This is the same
constraint that makes `appTheme`'s `accent` nullable rather than defaulted.
`reader_chrome_test.dart` asserts the two match, so the duplicate cannot
drift silently.

A reader who tints their background close to their accent gets a monochrome
progress bar rather than a coloured one: `readerProgressFillFor` falls back
silently, with no warning, because the tint and the accent are set on
different screens and neither knows about the other. Unlike contrast and
fade, this one is not warn-don't-block — there is no reading of "this fill
will be hard to see" for a reader to override, only a colour that quietly
is not the one they picked. Recorded in the README's known limitations as a
gap rather than as an accepted trade-off, since nothing here was chosen for
the reader's benefit the way the fade warning's non-blocking design was.

The reading surface itself is untouched. `RsvpView` reads `inkArgbFor` and
`surfaceArgbFor` directly and takes no theme, so the contrast readout in
settings still measures the pair the app paints.

## Verification

Three rounds of `flutter test` against this change, each finding something
the previous round had not, followed by a clean run of the whole suite.

- **First run.** `reader_chrome_test.dart` failed the progress-fill
  assertion at 1.92 against a required 3, on a background tint near the
  0.179 luminance flip. Led to `readerProgressFillFor`'s guard and
  `readerTrackOpacity` moving from 0.24 to 0.16. `reader_progress_test.dart`
  and `reader_semantics_test.dart` failed five tests reaching the play
  button by `find.text('Read')`, a label the redesign removed. Led to
  `readerPlayButtonKey`.
- **Second run**, after the key fix. `reader_progress_test.dart` failed one
  more test at the same label, on a second tap the first pass missed: the
  removed rewind button, inside the "follows a rewind taken while paused"
  test. Led to driving that test from `arrowLeft` instead.
- **Manual pass on Windows**, light theme, `Presets.standard`. Screenshots
  confirmed the chapter glyph, the three controls and the progress bar
  render correctly. The same pass found the profile sheet's container
  taking the app's theme while its contents took the reader's, visible as a
  grey overlay with barely legible list rows under a dark app theme. Led to
  theming `showModalBottomSheet`'s container arguments at the call site
  rather than only inside the builder — `backgroundColor`, `elevation` and
  `shape`, not `surfaceTintColor`, which the function does not expose.
- **`flutter analyze`** caught the `surfaceTintColor` argument as
  undefined after that fix, since `BottomSheetThemeData` carries the field
  and `showModalBottomSheet` does not. Removed; harmless at `elevation: 0`,
  where `ElevationOverlay` applies no tint regardless.
- **`flutter test`, full suite, green** with every fix above applied
  together.
- **`flutter analyze`, clean** on the tree as merged.
- **Manual pass on Windows**, opening the app directly rather than reading
  assertions, confirming the sheet mismatch fixed under a dark app theme.

Each fix has a test behind it: `reader_chrome_test.dart` asserts the guard
fires only where the accent genuinely cannot read, asserts it does *not*
fire on any preset under any accent, and asserts the sheet's container and
its contents agree under a dark app theme.
