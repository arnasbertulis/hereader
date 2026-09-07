# 0033. Every scrollable body takes a measure, and a control is not a poster

Date: 2026-09-07

## Status

Accepted.

## Context

A **measure** is the width a column of content is capped to. Commit 9f31a43
introduced one: `ContentWidth` (`app/lib/theme/content_width.dart:18-37`), a
`Center` around a `ConstrainedBox`, with `AppContent.maxWidth` at 720 for lists
and forms and `AppContent.proseMaxWidth` at 640 for prose
(`app_tokens.dart:33-41`). Ten screens adopt it.

What that commit did not add is a rule, and the gaps show where a rule would
have helped. `custom_accent_screen.dart:37` is a bare `ListView` reached from
Appearance, so the Settings subtree falls out of its own cap one level down.
`library_screen.dart`, `free_books_screen.dart`, `note_editor_screen.dart`,
`paste_reader_screen.dart` and `catalogue_browse.dart` have no width constraint
of any kind. On a maximised desktop window those run a line of body text to
roughly 200 characters, against the 45-75 that is readable.

Two related shapes have the same cause — a dimension nobody decided.

**Height.** `home_screen.dart:25-33` caps the continue tile's width at 252 and
states the reasoning: "A tile that tracked a desktop window would be a hero
image, and the continue tile is a control, not art." There is no height cap.
The tile's height is `width * kCoverAspect` = 378, which is 59% of a phone
viewport, 44% of it blank placeholder cover — and for a **Note**, which has no
cover and no author, it is blank twice over, with an empty line where the
author would be (`home_screen.dart:502-509`).

**Pairing.** `MainAxisAlignment.spaceBetween` appears exactly once in
`app/lib` — `setting_slider.dart:60-71`, a label and its value pushed to
opposite edges. It reaches the screen through three call paths: Reading
settings' step control, and both `rgb_sliders.dart` consumers. A magnified
reader never sees both halves of one fact at once. Meanwhile
`settings_screen.dart:261-275` already does the opposite and writes down why:
"at the text sizes this app is built for the two collide before either wraps."
The right convention exists in the codebase; it just is not a rule.

## Decision

### 1. Every scrollable body takes a measure

A screen's scrollable body is wrapped in `ContentWidth`. `AppContent.maxWidth`
for lists and forms, `AppContent.proseMaxWidth` for prose. The reading surface
is exempt and full-bleed by design; nothing else is.

This is stated as a rule rather than left as ten call sites because the two
places that missed it — a sub-screen one level down, and every screen written
before the widget existed — are exactly what a rule catches and a refactor does
not.

### 2. A label and its value are never separated by flexible space

The value sits under its label, left-aligned. No `spaceBetween` between a label
and the thing it labels, and no trailing-edge value on a row whose title can
wrap. `settings_screen.dart:264-266`'s reasoning generalises: at this app's
text sizes, the two collide before either wraps, so the horizontal arrangement
buys nothing and costs the reader the pairing.

### 3. A control is sized as a control

Cover art inside a control is incidental, not the subject. The continue tile
becomes a row — a small cover at the same 72 the Library's single-column
`_BookRow` uses, then title and place — rather than a poster with a caption.

This follows `home_screen.dart`'s own stated principle to its conclusion.
Capping the tile's height as a fraction of the viewport would keep a hero image
and argue about its size; the tile is a control, and a control does not need
378 logical pixels of placeholder.

## Consequences

- Closes #359, #351, #350 and #327, and Home's half of #335 — a Note in a row
  has no blank author line and no blank cover to fill.
- `library_screen.dart`, `free_books_screen.dart`, `note_editor_screen.dart`,
  `paste_reader_screen.dart` and `catalogue_browse.dart` adopt `ContentWidth`.
  The Library and Free books grids need a decision per screen about whether the
  grid or the viewport takes the cap, since both compute columns from
  `constraints.maxWidth`.
- `custom_accent_screen.dart`'s gap closes by deletion under ADR 0032 rather
  than by adoption.
- `setting_slider.dart` is one widget to change and three call paths to
  re-verify.
- `AppShelf.tileWidth` (172) is declared but not enforced — the grid divides
  available width instead (`library_screen.dart:684`). Section 1 does not fix
  that; it is #340's.
- Home and the Library's single-column layout converge on one row shape instead
  of diverging, which is a smaller vocabulary to maintain and to learn.

## Alternatives considered

- **Leave it as issues.** #359 is mostly closed and `setting_slider.dart` is a
  one-line fix, so there is a real case that no ADR is warranted. Rejected
  because the reason those screens slipped the cap is that there was nothing to
  check a new screen against — the same failure ADR 0031 and ADR 0032 each
  diagnose in their own dimension.
- **Per-screen width constants.** What the app had before 9f31a43: correct
  reasoning, local to one file, invisible to every other screen.
- **Cap the continue tile's height as a fraction of the viewport.** Keeps a
  hero image and makes its size a tuning parameter on every device class.
- **Keep the label/value row and rely on larger text.** Larger text makes the
  separation worse, not better: the two halves move further apart as the
  measure grows.

## Verification

A test that walks each screen's `Scaffold` body and asserts a `ContentWidth`
ancestor, with the reading surface as the single declared exemption. A golden
of the continue tile at a 320-wide viewport for a Book and for a Note. A widget
test that `SettingSlider` renders its value below its label at text scale 2.0.
