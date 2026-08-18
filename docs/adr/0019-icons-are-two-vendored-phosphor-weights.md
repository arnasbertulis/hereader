# 0019 — Icons are two vendored Phosphor weights, named by role

Status: Accepted
Date: 2026-08-18

## Context

The app drew 43 distinct glyphs from the legacy Material Icons font, reached
directly as `Icons.tune`, `Icons.cloud_off_outlined` and so on across 14 files.

Two things are wrong with that for this app.

The first is the family. Material Icons is a mix of filled and outlined shapes
with no weight control, and the filled ones carry visual weight the reader did
not ask for — a solid `play_arrow` under a reading profile chosen for low
contrast is a large dark mass on a page tuned to avoid them. ADR 0015 spent the
reader's chrome down to a monochrome ramp and one accent for the same reason,
and the icons were never brought in line.

The second is that the family was a decision made 43 times. Every call site
named a glyph, so the question "what weight does this app draw at" had no place
to be answered, and changing the answer meant an edit per site.

An earlier note in this repository claimed a lighter set was impossible without
custom painters, on the grounds that `close`, `play_arrow` and `pause` are
already single-weight glyphs whose `_outlined` names are the same picture. That
premise is true and the conclusion does not follow: it is a fact about the
legacy font, which is the only one the app had.

## Decision

**Phosphor, at Light, with Fill for selection.**

Phosphor exposes weight as a real axis across a consistent family — six of
them, drawn as one set rather than assembled. Material Symbols was the other
candidate and carries weight, fill, grade and optical size as variable axes,
which is strictly more control. Phosphor was chosen on the drawing.

**Light, not Thin.** Thin was the original ask. At the sizes this app draws
icons — 20 to 24 logical pixels — Thin's strokes land near one physical pixel,
which is the first thing central field loss takes away, and the app has a
high-contrast mode that a hairline actively fights. Light is still a clear step
down from Material's mixed weights and survives both.

**Fill means selected.** Six of the Material names were outlined/filled pairs
standing in for selection — `home_outlined`/`home` and the rest. Phosphor gives
that as a weight on one glyph, so each pair collapses to one picture drawn two
ways, and selection reads as emphasis rather than as a change of subject.

**Two vendored fonts, not the package.** `phosphor_flutter` cannot be compiled
against this Flutter SDK. It declares `PhosphorIconData extends IconData`, and
`IconData` is a `final class`, so the front end rejects the package's own
source the moment anything imports it. There is no fixed release: 2.1.0 is the
latest and the constraint is on the SDK, not the version.

So the fonts are vendored under `app/assets/fonts/`, declared in
`pubspec.yaml`, and addressed by plain const `IconData`. Phosphor is MIT and
the notice sits beside the files. Only Light and Fill are copied; the package
ships all six weights, about 3MB, to draw glyphs from two of them.

**One roster, named by role.** `app/lib/theme/app_icons.dart` holds every
constant the app draws, named for what it means rather than what it is:
`AppIcons.chapters`, not a list glyph; `AppIcons.readingProfile`, not sliders.
Nothing outside that file names a codepoint or a font family. The weight is
therefore decided once, and the next family swap is a rewrite of one file plus
a font declaration.

Role names also record distinctions the glyph does not. `contrastWarns` and
`settingWarns` are the same picture and different facts — one reports a
measurement, the other reports a setting — and could want to diverge without a
search-and-replace deciding for them.

`uses-material-design: true` stays. The framework draws its own glyphs from
that font — `AppBar`'s back button, `SegmentedButton`'s check, the arrow inside
a `PopupMenuButton` — and none of those are the app's to name.

## Consequences

The two fonts are subset at build time and cost almost nothing. Against the
build before this change, the total font payload rises by about 7KB.

Anything that draws an icon imports `app_icons.dart`. A new glyph is added to
the roster first and used second, which is the point: the addition is a
decision with a name, made in a file that shows what is already there.

Tests find chrome by role too. `app_smoke_test.dart` reached Settings and the
signed-out sync state by naming a Material glyph, and now names
`AppIcons.tabSettings` and `AppIcons.syncSignedOut` — the same coupling, to a
name that says what it is asserting.

The failure mode this introduces is a wrong codepoint: a constant that compiles
and draws the wrong picture, or the empty box for a glyph absent from the
subset. `flutter analyze` cannot see it, and neither can a widget test, which
matches an `IconData` by value rather than by shape. It is caught by looking at
the screen, which is how the roster was checked.

The codepoints were extracted from `phosphor_flutter`'s own generated tables
for exactly the glyph names in use, rather than transcribed. A name absent from
those tables failed the extraction rather than reaching a build.

## Alternatives

**Keeping `phosphor_flutter` and pinning an older Flutter.** Rejected outright.
The SDK is not going to un-seal `IconData`, and holding the toolchain back for
an icon package inverts what matters.

**A `dependency_overrides` or a forked package.** A fork is the vendored fonts
plus a generated Dart file with 1512 constants the app does not use, wrapped in
a package boundary that buys nothing here. The vendoring is the fork with the
unused parts left out.

**Material Symbols.** Genuinely more control — variable weight, fill, grade and
optical size, and a real unfilled `play_arrow`, which is the thing an earlier
note in this repo said did not exist. Not rejected on merit; Phosphor was
preferred on how the set draws after both were on the table. If Light turns out
too heavy or too light against a real reader, Symbols' continuous weight axis
is the reason to revisit, and this file is the place it would be revisited
from.

**Lucide, Heroicons, Iconsax.** Cleaner individual glyphs and smaller coverage.
Rejected because every one of the roles here needs a match before a swap, and a
set with gaps filled from elsewhere reads worse than a consistent heavier one.

**Custom painters.** What the earlier note assumed was necessary. Reserved for
a shape no family has, which is none of these.

**Keeping the glyph names at the call sites and only changing the family.** The
smaller diff, and it would have left the family a decision made 43 times.
Rejected on the same argument as the one behind `ResolvedPresentation`: a rule
that lives in a convention rather than in a type holds until someone finds it
easier not to.

## Verification

`flutter analyze` in `app/`, clean — which resolves every constant in the
roster and every call site against it.

`flutter test` in `app/`, 932 passing, unchanged from before the swap apart
from the four finders in `app_smoke_test.dart` that named a Material glyph.

`flutter build web --release`, which is where the tree-shaking claim is
checked rather than assumed:

```
Phosphor-Fill.ttf   449252 -> 1804 bytes  (99.6% reduction)
Phosphor-Light.ttf  536628 -> 9780 bytes  (98.2% reduction)
MaterialIcons.otf  1645184 -> 7736 bytes  (99.5% reduction)
```

The Material subset shrank by 4500 bytes across this change, since the app now
names none of those glyphs itself and only the framework's own remain. Against
that, the two Phosphor subsets add 11584. Net, about 7KB.

The build also emits a pre-existing warning about `cupertino_icons`, confirmed
present on `main` before this change and unrelated to it.

Checked by hand on Windows, and this paragraph replaces one that said "not yet
run" while it had not been. The screens draw as intended: no empty box from a
codepoint outside the subset, and no glyph landing on the wrong role. Those
are the two failures nothing else here can see, since a widget test matches an
`IconData` by value rather than by shape.

Outstanding: Android Chrome, along with everything else since the UI pass. The
icons are static glyphs rather than anything animated or translated, so the
frame throttle recorded under known limitations does not reach them — an
expectation, not a result. What is worth an actual look there is size: Light's
strokes were chosen against a physical pixel at 20-24dp, and the device that
argument is about is a phone.
