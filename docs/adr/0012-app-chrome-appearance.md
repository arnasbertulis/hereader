# 0012. App chrome is a neutral ramp plus one accent, chosen per device

Date: 2026-08-15

## Status

Accepted.

## Context

The app around the books was Material's baseline. `ColorScheme.fromSeed` with
the default `tonalSpot` variant and a purple seed, one theme, following the
platform brightness and nothing else.

The seed hue was the smaller half of the problem. `tonalSpot` tints every
surface with the seed, so a deep purple does not give a grey app with purple
buttons; it gives a pale lilac wash on every card, sheet and bar. Swapping the
seed under the same variant moves that wash to another hue rather than
removing it.

The larger half is who this app is for. A reader with central field loss is
also the reader most likely to have a strong preference about brightness, and
to have set one at the operating system level already. The app offered them
nothing: no way to force dark on a device that reports light, no way to ask
for stronger separation between surfaces, and no accent choice at all.

Three constraints shaped the answer.

The reading surface is already configurable per profile, down to an arbitrary
background tint, and those colours are the reader's own. Anything decided here
that reached that surface would collide with a choice already made there.

Appearance has to be known before the first frame. `_start()` already awaits
the database, the stored session and the clock, because every write needs a
stamp. A preference read after first paint means a white flash on a
dark-theme device on every cold start.

The preference table is synced infrastructure. `setPreference` takes a
`sync` flag that defaults to false, and ADR 0005 records the outbound
preference path as unused capability.

## Decision

### Surfaces come from a fixed neutral ramp; only the accent is generated

`buildScheme` calls `ColorScheme.fromSeed` with `DynamicSchemeVariant.fidelity`
to generate the accent group, then overrides every surface, outline and
inverse role from a fixed ramp. Fidelity keeps the generated palette near the
colour the reader picked instead of pulling it toward a pastel, which matters
when they picked it deliberately. The override is what makes the greys
identical under all six accents.

Neither end of the ramp is pure black or pure white, matching the argument
`profile_presentation.dart` already makes for the reading surface: maximum
contrast is uncomfortable over a long session, and the ratio difference is
negligible. The values sit close to that file's own constants so a reader who
tinted nothing sees one continuous surface on leaving a book.

Six accents, named, no purple. The name is not decoration: a swatch that
signalled selection by colour alone would fail the reader this app exists for.

### High contrast replaces the ramp rather than deepening it

A separate set of values for both brightnesses, plus `contrastLevel: 1.0` into
`fromSeed` so the accent pair moves with it. Hairlines go from 1dp to 2dp and
the hairline colour moves with the ramp, because a 1dp `outlineVariant` line
is the first thing to disappear for a low-vision reader.

It is reachable two ways. The reader's own switch forces it on, and
`MaterialApp`'s `highContrastTheme` slot gives it to anyone whose platform
already asks for high contrast without their having to find the setting here.
Either one is enough.

### The three settings are device-local

`ui.theme_mode`, `ui.accent` and `ui.high_contrast`, in the namespace
`ui.active_profile` established, each written with `sync: false` stated at the
call site rather than left to the default.

A phone read outdoors and a desktop in a dim room want different brightnesses,
which is the argument that already keeps the active profile pointer local.
Syncing them would also mean opening the outbound preference path for the
first time, and a theme switch is the wrong thing to prove it with: the failure
mode is a device silently changing its own appearance because another one did.

They are stored as the words they mean — `dark`, `#2F4858`, `true` — rather
than as enum indices. An index breaks silently the day the enum gains a case
in a different position. The accent is stored as its colour rather than its
name, so a custom accent needs no second format and no migration.

Every read degrades rather than throws. This runs inside the `try` whose
`catch` renders the startup failure screen, so an unrecognised value would
replace the app over a preference. The same reasoning ADR 0005 applies to
profiles arriving from a build with different constraints.

### The reader's accent never reaches the reading surface

`readerChromeTheme` seeds from `readerChromeSeed`, a constant of its own. A
reader who tinted their background moss and set the accent to rust would
otherwise find the two adjacent on the one screen where the whole point is
that the colours are theirs.

## Consequences

Every screen outside the reader now rebuilds when appearance changes, from a
`ListenableBuilder` above `MaterialApp`. That forced `HereaderApp` to become
stateful: it held its navigator `GlobalKey` as a field of a `StatelessWidget`,
which was safe only while nothing rebuilt it. A fresh key per rebuild would
hand the `Navigator` a new identity and discard every route under it.

`app/web/index.html` paints its background from `prefers-color-scheme`, so the
loader is no longer white on a dark device. It follows the browser rather than
the reader's stored choice, which lives in OPFS behind the engine the page is
still loading. A reader who chose Light on a dark-preference device sees a
dark background for the moment before the first frame. Recorded as a
limitation rather than solved.

Two hex values are now written down in both `app_colors.dart` and
`index.html`. `app/test/web_shell_colors_test.dart` fails if they drift.

The light `outline` value moved from `#8B9297` to `#787E82`. It draws the
border of an outlined button, which WCAG 1.4.11 treats as information needed to
identify a control and asks for 3:1 against its background; the old value
reached 3.05 against `surface` and 2.52 against `surfaceContainerHighest`, so a
button on a card missed it. Nothing here uses elevation, so that border is the
only thing separating the control from what is behind it.

The appearance controls sit behind a row on the reading profiles screen, which
is the wrong home for them. It is the only settings surface the app has until
the navigation shell lands.

## Alternatives considered

**Keep `tonalSpot` and change the seed.** Rejected. The wash across every
surface is the tell, more than the hue is, and this moves it rather than
removing it.

**Android dynamic colour.** Rejected. It hands surface tinting back to the
system, which is the thing the fixed ramp exists to prevent, and it would make
the app's appearance depend on a wallpaper on one platform and not the others.

**Sync appearance through the outbound preference path.** Rejected, for the
reason above: the settings are ones two devices should reasonably disagree
about, and the path they would open has no other customer waiting.

**Store the accent by name.** Rejected. It reads well in the database and it
cannot represent a colour that is not on the list, so the custom accent would
need a second key or a sentinel value, and a migration for anything already
stored.

**Write the theme choice to `localStorage` so `index.html` can read it.**
Rejected. It would make the loader exact, at the cost of a second copy of a
setting that already has an owner, on the one platform where the two could
disagree without anything noticing.

**Clamp `textScaler` so the ramp's type scale holds its layout.** Rejected
without argument. Text scaling is the accessibility setting this reader is
most likely to be using.

## Verification

`flutter test` in `app/`, and `dart test` and `dart test -p chrome` in
`packages/rsvp_engine/`, all green.

`app/test/app_theme_test.dart` measures every generated scheme: six accents by
two brightnesses by two contrast levels. `onSurface` and `onSurfaceVariant`
clear 4.5:1 against every surface role in all of them, `outline` clears 3:1,
and the surface roles are byte-identical across accents, which is the claim
`buildScheme` is built on.

`packages/rsvp_engine/test/contrast_test.dart` runs the WCAG maths under
`dart2js` as well as the VM, which is what moving it out of the app was for.

Checked by hand on Windows: switching theme, accent and contrast retheme the
app on the tap, survive a restart, and leave the reading surface unchanged
under every combination.
