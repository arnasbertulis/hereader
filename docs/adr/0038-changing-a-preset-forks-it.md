# 0038. Changing a Preset forks it, and the Settings row opens the active profile

Date: 2026-09-10

## Status

Accepted.

## Context

A Preset is a built-in profile: it lives in code, is never stored, and cannot
be edited or deleted. A Fork is a stored copy of a profile, made because the
thing it came from could not be changed. The app already makes one kind of
fork on the reader's behalf — the sliding switch's — but for every other change
it made the reader ask for the fork first.

**Changing the speed of a Preset took five steps.** Settings → Reading profiles
→ the row's overflow menu (`profile_row.dart:39`) → "View settings", the label
a Preset's menu shows instead of "Edit" (`profile_row.dart:53`) → "Make a copy"
inside the editor (`profile_edit_screen.dart:95-114`) → the change itself. #353
counted three levels and #433 inherited that count; the fork step is the part
neither counted. `ProfileRow` is shared with the reader's own profile switcher,
so the same path starts from the reader's Profile button.

**The Settings index already shows the active profile, then opens something
else.** #423 put the active profile's pace and type size on the Settings index
row. Tapping that row opens the list of every profile, where a tap *chooses* a
profile (`profile_row.dart:38`) and editing is behind the menu.

#442 restored the activation of a copy with an announcement and an Undo, so the
announcement this ADR relies on already exists.

## Decision

### 1. A Preset's editor is editable, and the first change forks it

The first change the reader makes in a Preset's editor makes a Fork, named the
way "Make a copy" names one ("Standard (copy)"), and makes it the active
profile. The change is announced with the same Undo snackbar #442 uses; Undo
deletes the fork and makes the Preset active again. Further changes in that
editor edit the fork. The Preset itself is never modified.

### 2. Every change to a Preset forks anew

Returning to a Preset later and changing it again makes a second fork. An
earlier fork of the same Preset is never reused: which Preset a fork came from
and whether it is still "the" fork of it are two facts, not one — the trap the
sliding fork already names.

### 3. "Edit" is the menu item for every profile

"View settings" goes. "Make a copy" stays, for a copy the reader wants for its
own sake.

### 4. The Settings index row opens the active profile's editor

The row that shows the active profile's pace and size opens that profile's
editor. The full list — choose another, copy, delete — is reached from an "All
profiles" action in the editor's app bar. The list's own tap-to-choose is
unchanged.

## Consequences

- Changing the active profile's speed is two taps from Settings: the row, then
  the control. For a Preset, the first change also forks it.
- After the first fork the active profile *is* that fork, so §4 opens the fork
  and §2's extra forks appear only when a reader goes back to a Preset on
  purpose.
- An accidental fork is undone by the snackbar and removable by Delete: this
  warns, it does not block.
- A fork is an ordinary stored profile, so it syncs under ADR 0008 like any
  other; nothing here adds sync semantics.
- A sliding fork is already stored and editable, so editing it forks nothing.
  Renaming it or giving it caret settings still makes it the reader's, as
  before.
- Closes #433.

## Alternatives considered

- **Keep "Make a copy" as the only way to change a Preset.** The reader has to
  know that a Preset is immutable before they can change a speed — an
  implementation fact they should never meet.
- **A "change speed and size" shortcut on the Settings index row.** A second
  path that forks and writes a profile, beside the editor's: two paths writing
  one fact.
- **Ask before forking.** A dialog in front of every first change blocks where
  an Undo warns.
- **Reuse an earlier fork of the same Preset.** Needs a rule for when a fork is
  still "the" fork — renamed? edited since? — and every answer merges two
  facts.
- **Let Presets be edited in place.** Presets live in code and are never
  stored; making them mutable dissolves the Preset/Fork distinction and gives
  sync a built-in profile to merge.

## Verification

Widget tests: the first change in a Preset's editor stores exactly one fork,
makes it active and shows the Undo snackbar; Undo removes the fork and
restores the Preset; a second change in the same editor stores no second fork;
returning to the Preset and changing it again stores a second fork; a Preset's
menu reads "Edit"; the Settings index row opens the active profile's editor,
and "All profiles" opens the list.
