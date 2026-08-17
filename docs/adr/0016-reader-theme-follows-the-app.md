# 0016 — Reader theme follows the app where the profile states no polarity

Status: Accepted
Date: 2026-08-17

## Context

Opening a book from a dark Home dropped the reader onto a white page. The
reading profile decided the surface on its own, and nothing about the app's
own theme mode reached it, so a reader who set the app dark met full-brightness
white every time they opened a book.

`PresentationConfig.polarity` was a two-value enum defaulting to
`darkOnLight`. That default was doing two different jobs. On
`centralFieldLoss`, `centralFieldLossTimed` and `lowFatigue` the polarity is
written out and cited: Aquilante et al. 2001 and Arditi 1999 for the first two,
and a preference stated as a preference for the third. On `Presets.standard`
and `Presets.spacedType` nobody chose it. Neither Aquilante's constant-rate
finding nor Zorzi's letter-spacing result says anything about which way round
the surface runs, so those two profiles carried a light page because the class
default was light.

Two existing decisions constrain the answer. Theme mode is device-local under
ADR 0012, on the argument that already keeps the active-profile pointer local.
Profiles merge whole under ADR 0008, so anything added to a profile crosses the
wire inside one payload and loses or wins as part of it.

One more constraint comes from ADR 0001. `rsvp_engine` carries no Flutter
import and could be published on its own, so it holds no notion of a platform
theme and cannot look one up.

## Decision

`PresentationConfig.polarity` becomes `Polarity?`. Null says the profile states
no preference and whoever draws it supplies one. `Polarity` itself stays a
two-value enum with no app awareness.

`PresentationConfig.resolvedWith(Polarity fallback)` returns a config with the
fallback substituted where the profile left the field open, and returns the
config unchanged where it did not.

The app supplies the fallback from the brightness it is running in.
`polarityFor(Brightness)` in `profile_presentation.dart` maps a light app to
`darkOnLight` and a dark app to `lightOnDark`. `resolvePresentation` pairs it
with `resolvedWith`.

`ResolvedPresentation` is an extension type over a `PresentationConfig` whose
polarity is decided, and `resolvePresentation` is its only constructor.
`surfaceArgbFor`, `chromeBrightnessFor`, `readerInkArgbFor`, `readerTrackFor`,
`readerProgressFillFor`, `readerChromeTheme` and `RsvpView` all take it.

Each screen resolves once, near the top of `build`, from a context above any
`Theme` that screen installs, and passes the result down. `ReaderScreen` and
`ProfileEditScreen` are the two.

`Presets.standard` and `Presets.spacedType` state no polarity. The three
presets whose reasoning picks a surface keep `lightOnDark`, and the app's theme
does not reach them.

Both nullable fields on `PresentationConfig` leave `copyWith`. `withPolarity`
and `withTint` each set one field, null included.

A polarity name `fromJson` cannot read now means unset rather than
`darkOnLight`.

Following the app takes its brightness, not its colours. The reading surface
keeps `lightSurfaceArgb` and `darkSurfaceArgb`, which are not the app ramp's
own surface roles.

Settings gains a switch above the existing polarity control and disables that
control while the switch is on. Turning it off pins the polarity the app was
supplying.

## Alternatives considered

**A third `Polarity` value, `followApp`.** Rejected on three counts. It puts an
app concept inside a package that has no way to act on it, so every switch in
`rsvp_engine` over `Polarity` gains a case it cannot paint and has to throw or
pick a side the reader never chose. It moves every profile already on disk onto
an enum value none of them were written with. And it makes the pure package's
public API describe a platform it cannot see.

**A boolean beside a concrete polarity**, so `toJson` could write a real value
for older clients to read. Rejected: two fields describing one fact, where the
concrete one goes stale the moment the reader changes the app's theme. Two
paths writing one fact is how they come apart, which is why `ReaderScreen`
stopped popping a `ReadingResult` under ADR 0011. The wire benefit is also
smaller than it looks, since an older client discards the boolean on its own
next write regardless.

**Keeping `polarity` non-null and resolving inside `RsvpView`.** Rejected. The
settings preview draws through `RsvpView` and the WCAG contrast readout sits
directly beneath it measuring the same pair. Resolution below them would have
the readout reporting the unresolved colours while the reader looked at the
resolved ones. That is the exact disagreement `profile_presentation.dart`
already records: `RsvpView` carried its own ink and surface constants that had
drifted, and the readout judged `0xFF080808` against a surface painted
`0xFF101010`.

**A comment saying resolution happens above `RsvpView`, with no type to
enforce it.** Rejected on this project's own evidence. `readerChromeSeed`'s doc
comment stated the correct intent while the constant beside it held Material's
baseline purple, and nothing caught it until a screenshot did.

**A plain wrapper class rather than an extension type.** Same compile-time
guarantee, but `RsvpView` rebuilds once per word under ADR 0011's playback, and
a wrapper allocation on that path buys nothing. The extension type compiles to
the config itself. Its cost is real and accepted: extension types forward no
members, so `RsvpView` reads `presentation.config.fontSizePt`. That verbosity
is also what stops an unresolved config reaching a paint call by looking close
enough.

**An assert inside `surfaceArgbFor`.** Rejected: it fires in a debug run of a
screen somebody thought to open, while the type fires in `flutter analyze` on
every screen at once, in CI, on every push.

**Storing the follow choice as a device-local preference** rather than on the
profile. Rejected: polarity already lives on the profile, and splitting one
setting across two tables means anything reading it watches both, for no gain
the reader can see.

**Overriding the built-in low-vision presets with the app default.** Rejected.
`centralFieldLoss` reverses the surface on cited evidence, and a light app
theme is not evidence.

**Falling back to `darkOnLight` on a polarity name `fromJson` cannot read.**
This was the shipped behaviour and `profile_test.dart` asserted it. Reversed
here: an unreadable name comes from a build carrying a value this one does not
have, and it says nothing about which of these two the reader would have
picked. The app's own theme is a better answer than a constant. Mode keeps its
fallback, because the engine has to lay something out and has no caller to ask.

**Encoding the follow intent so an older client preserves it.** Rejected as
impossible rather than as unwanted. An older `PresentationConfig.fromJson`
drops any key it has no field for, whatever that key is called, so no wire
format survives a round trip through it. See the consequence below.

**Tying `lightSurfaceArgb` and `darkSurfaceArgb` to the app ramp's surface
roles**, so a book opens on exactly the colour Home was drawn in. Rejected: it
puts the app ramp inside the pair the contrast readout measures, and that ramp
moves for chrome reasons and again under high contrast, which a reader sets for
the app rather than for the page.

## Consequences

A profile that states no polarity renders light on a device set light and dark
on a device set dark, both signed into the same account. That follows from
theme mode being device-local under ADR 0012 rather than working around it, and
it is stated here so nobody has to discover it from the code.

A client older than this field reads the absent key as its own default and pins
the profile to `darkOnLight`. Because profiles merge whole under ADR 0008, that
client writes the pin back over the follow intent on its next edit of the same
profile, and both devices then agree on a polarity the reader never chose.
Nothing logs it. Recorded in `app/README.md` under known limitations.

No migration. Presentation is stored as JSON in `stored_profiles`, and every
profile on disk carries an explicit `polarity` key because the previous
`toJson` wrote one unconditionally. Stored profiles stay on the surface their
reader already reads on. A reader who forked `Standard` before this change
keeps their white page and can opt in from the switch; a reader who never
forked is on `builtin.standard`, which is code, and gets the new behaviour.

`readerProgressFillFor`'s contrast guard has more backgrounds to survive. One
profile now reaches both polarity defaults on one device depending on the
theme, so the fill can fall back to the ink on a book that did not trigger it
yesterday. `reader_chrome_test.dart` measures every preset under both app
themes for that reason. The silent nature of that fallback is unchanged and
remains a known limitation from ADR 0015.

The step between the app ramp and the reading surface is now visible. A dark
app moves from `#131416` to `#101010` on opening a book, and a light app from
`#FBFBFC` to `#FAFAFA`, where before a dark app went to `#FAFAFA` and the jump
read as the reader screen having a look of its own. The two ramps stay
separate for the reason under the last rejected alternative.

`copyWith` no longer sets `tintArgb`, which is a change beyond what this
decision needed. Taken because both nullable fields on the class now follow one
rule and the compiler names every call site, and because it deletes the
eleven-field `PresentationConfig` that `_BackgroundField`'s reset was
rebuilding by hand for exactly this reason.

## Verification

`flutter analyze` and `dart analyze` clean. `flutter test` and `dart test`
green.

Two failures surfaced during that run and were fixed inside this change rather
than after it. `scrollUntilVisible` in `reading_surface_test.dart` resolved its
default `scrollable` argument to the single `Scrollable` in the tree and found
two, since the name field builds an `EditableText` with a `Scrollable` of its
own; the finder is now named explicitly. `profile_test.dart` asserted the old
`darkOnLight` fallback on an unreadable polarity name, and its polarity
assertion is dropped in favour of the coverage in
`presentation_polarity_test.dart`.

Checked by hand on Windows: a book opened from a dark app onto a dark page and
from a light app onto a light one; `Central field loss` opened inside a light
app and kept its reversed surface; the settings switch turned off against an
open book, which left the page on the colour it was already showing and enabled
the polarity control beneath it.

The colour step between the app ramp and the reading surface, recorded under
consequences, was observed during that pass rather than predicted from the
constants.
