# 0032. Colour meanings are fixed at build time, not derived per reader

Date: 2026-09-07

## Status

Accepted. Narrows ADR 0012's accent scope from a promise in a comment to a
rule with an assertion behind it.

## Context

`app_colors.dart:206-207`'s own comment states the promise: the accent is
visible only on "the active nav indicator, progress fill, primary buttons,
selected states and focus rings." ADR 0012 keeps the accent off the reading
surface; ADR 0015 allows reader chrome exactly one accent.

Two ideas do the work here, and they are now in the app glossary. A **fill** is
a colour applied as a background, which Material derives a contrasting
foreground against — safe by construction. **Ink** is a colour applied to text
or a glyph on a surface — safe only if it clears contrast against a neutral the
reader cannot see the effect of choosing.

**Three consumers draw the accent as ink.** `free_books_screen.dart:814` (a
status `Text` in `primary` at 12px), and `profile_presentation.dart:268` and
`:398`, both reader-surface code under ADR 0015. The middle one already carries
an inline contrast check — the clamp exists, once, locally, which is the "two
paths write one fact" shape `CLAUDE.md` warns against.

**`error` is used as ink in eight places, none as fills:**
`profile_row.dart:61`, `profile_actions.dart:75`,
`library_screen.dart:351,983`, `setting_slider.dart:120,126`,
`sign_in_screen.dart:149`, `position_conflict_sheet.dart:248`. Destructive
actions are not unstyled; they are styled inconsistently.

### What measurement changed

Earlier drafts of this ADR asserted that `error` is seed-derived and that the
accent needs a runtime contrast clamp. Both were measured and both are false.
`buildScheme` (`app_colors.dart:213-218`) calls `fromSeed` with
`DynamicSchemeVariant.fidelity` and `contrastLevel: highContrast ? 1.0 : 0.0`,
then overrides only surface, outline and inverse roles.

- **`error` does not follow the seed.** It is constant across all six accents
  within each brightness and contrast cell: `#BA1A1A` light/normal, `#600004`
  light/high, `#FFB4AB` dark/normal, `#FFECE9` dark/high. Under `fidelity` the
  error palette is fixed Material red.
- **No accent fails contrast.** Across six accents by two brightnesses by two
  contrast levels, the minimum `primary` against `surface` is 6.46 and the
  minimum `onPrimary` against `primary` is 6.68. A 4.5:1 clamp would alter
  nothing.
- **The real defect is `contrastLevel: 1.0`.** Raising contrast pushes
  `primary` and `error` to the *same* end of the tonal ramp, so they converge.
  Worst case per accent, as CIE76 ΔE: Crimson **0.51** (`#FFECEA` against
  `#FFECE9` — one unit of blue), Rust **1.53**, Amber **9.68**, and **Ink —
  the default accent — 14.67**. Every accent's worst case is a high-contrast
  cell.

So "red means destructive" fails, and it fails worst for a reader who turned on
high contrast — and dropping `crimson` from the palette would not fix it,
because amber and the default are also close. The variable that moves is
`error`'s participation in the contrast ramp, not the seed.

Two further facts bear on the scope. `custom_accent_screen.dart` lets a reader
dial an arbitrary 24-bit accent, so the palette is not six colours — it is
every colour, and no enumeration can verify it. And `book_cover.dart:107-110`
records that the generated cover's band takes its hue from the book id, "the
only place in the app where a colour comes from anything but the reader's
accent" — a real exception this ADR would otherwise contradict on its face.

## Decision

### 1. The accent is a choice, not a colour that is painted

Components take roles derived from it. The raw swatch reaches the screen in
exactly one place, the picker.

### 2. The derived accent role is a fill, never ink

It may be a button fill, the progress fill, the nav indicator, a slider track.
It is never applied to text or a glyph sitting on a surface. Selected rows stay
`onSurface` (already true at `app_theme.dart:188`) and selection is carried by
shape — `profile_row.dart:25-45` swaps a glyph rather than a colour. This ADR
is what keeps that true when the next `selected:`-aware widget is themed; the
glyph vocabulary itself is #371's call, constrained by this rule.

`free_books_screen.dart:814` loses the accent. The two
`profile_presentation.dart` sites are ADR 0015's sanctioned single accent on
reader chrome and stay, with their contrast check unchanged — ADR 0015 governs
there, not this ADR.

### 3. The palette is finite and curated

Six hues at three lightnesses, eighteen swatches, every one checked at build
time. `custom_accent_screen.dart` is deleted. A stored arbitrary accent snaps
once to the nearest palette entry by perceptual distance and is **written
back**, so one fact has one value rather than being re-derived at every render.

A finite palette is what turns "the accent is safe" from a runtime clamp that
silently overrides the reader's choice into a property the build proves.

### 4. The error group is pinned out of the contrast ramp

`error`, `onError`, `errorContainer` and `onErrorContainer` are overridden in
`_neutrals()` to fixed values per brightness that **do not move with
`contrastLevel`**: `#AF0018` light, `#FF6B5E` dark.

Measured against all six accents by two brightnesses by two contrast levels,
this pair holds `error` at least 7:1 against `surface` in high contrast and
4.5:1 in normal, keeps `onError` at least 7.4:1 against `error`, and raises the
minimum ΔE between `primary` and `error` from **0.51 to 30.55**. No accent
collides. `crimson` and `rust` both survive, which is why section 3 can offer
eighteen swatches rather than fifteen.

Pinning `errorContainer` also removes a polarity flip nobody chose: today the
warn banner at `profile_edit_screen.dart:1055` inverts from a pale fill with
dark ink to a dark fill with pale ink when high contrast turns on. The cost is
that the banner no longer intensifies under high contrast, which is the right
trade — a colour that means "destructive" should not change appearance based on
a setting about legibility.

### 5. Destructive is signalled by more than hue

A leading icon, an outlined rather than filled treatment, and confirm-button
position. Section 4 makes red mean one thing; this makes the meaning survive a
reader who cannot discriminate the hue at all. Colour alone cannot carry this
in an app that lets the reader pick colours.

### 6. Focus is its own treatment

Distinct from hover, from selection, and from the accent. `scheme.outline` is
not free: `outlinedButtonTheme.side` (`app_theme.dart:169`) and the unselected
switch thumb (`:212`) already use it, so a focus ring in `outline` would be
indistinguishable from an `OutlinedButton`'s own border. It needs its own
colour, or distinction by width and offset rather than hue. Owned by #339,
which #371 depends on.

### 7. Identity colour is the one sanctioned exception

The hue on a coverless book's generated face is derived from the book, not the
accent, so that two coverless books differ. It is not an accent and never
follows one. Naming it here is what stops it being "fixed" into the accent
system by someone applying section 2 literally.

### 8. No runtime clamp

A build-time assertion over the finite palette, not a check each consumer
remembers or a clamp in `buildScheme`. Measurement showed a clamp to be a
no-op against the current swatches, and once section 3 removes the arbitrary
picker there is no unbounded input left for it to guard.

## Consequences

- Closes #360, #348 and #349.
- Unblocks #371 and #372: background tint is free to mean "selected" once it no
  longer also means "accent as ink."
- #335's band is settled as Identity colour and is not changed.
- The twelve new lightness variants in section 3 are **not yet measured** — the
  numbers above cover the six existing swatches. The section 8 assertion is
  what proves the other twelve when they are authored, and it must be written
  before they are.
- The eight `error` sites need a consistency pass under section 5.
- **A gap this ADR does not close.** `_Neutrals.overrideWith`
  (`app_colors.dart:109-131`) overrides `surface`, `onSurface`,
  `onSurfaceVariant`, `outline`, `outlineVariant` and `surfaceContainer` — but
  not `surfaceContainerHigh`. So a dark high-contrast reader gets `surface` at
  `#000000` and a dialog still at `#272A2D`, and `error` on that dialog reaches
  only 5.16:1. The floor this ADR asserts is therefore 4.5:1 against whatever
  backdrop a colour is actually drawn on, and 7:1 against `surface` under high
  contrast. Extending the override across the container ramp changes every
  dialog, sheet and popup menu in the app, so it is #403 rather than this ADR,
  and the comment at `app_colors.dart:101-108` already flags it.
- Every future component theme is checked against one sentence — is this colour
  a fill here, or ink?

## Alternatives considered

- **A runtime clamp in `buildScheme`.** What earlier drafts of this ADR
  decided. Rejected on measurement: a no-op against every current swatch, and
  redundant once the palette is finite. A clamp also silently overrides the
  colour the reader just picked, which is worse than not offering it.
- **Exclude colliding swatches from the palette.** Rejected on measurement: the
  collision is a high-contrast artefact affecting amber and the default accent
  as well as crimson and rust, so exclusion would leave teal and moss. That is
  not a palette.
- **Give `error` a fixed hue but let it keep following `contrastLevel`.** It
  already has a fixed hue; that was the false premise. The contrast ramp is the
  variable.
- **Drop the accent picker and ship one fixed accent.** Genuinely defensible
  for this audience and it dissolves the destructive problem entirely.
  Rejected: personalisation is reasonable and eighteen checked swatches are a
  good version of it.
- **Keep the arbitrary picker and clamp its output.** Rejected under section 3
  and by #349's own reasoning: RGB sliders ask a low-vision reader to solve for
  a colour in three dimensions they cannot see.
- **Auto-derive a second "safe ink" colour from the accent.** Adds a role to
  explain and makes the accent appear to behave inconsistently.

## Verification

A build-time assertion over the palette — eighteen swatches by two brightnesses
by two contrast levels — asserting `primary` against `surface` at 4.5:1,
`onPrimary` against `primary` at 4.5:1, and CIE76 ΔE between `primary` and
`error` above the floor section 4 establishes. WCAG relative luminance is
implemented in `packages/rsvp_engine/lib/src/color/contrast.dart:47` and was
independently cross-checked during this review; ΔE is CIE76 over CIELAB.

Plus a widget test that resolves text and icon colours on Library, Free books
and the profile screens and asserts none equals `colorScheme.primary`. Not a
grep: a grep cannot tell a fill from ink, which is the only distinction this
ADR turns on.
