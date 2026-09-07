# 0031. Chrome type is four roles on a base, and every `TextTheme` slot is declared

Date: 2026-09-07

## Status

Accepted. Depends on ADR 0034 landing first; see Consequences.

## Context

`appTextTheme` (`app/lib/theme/app_typography.dart:37-46`) declares eight
`TextTheme` roles and its doc comment claims it "sets every size, weight and
line height from the brief's table."

It does not. `ThemeData(textTheme:)` (`app_theme.dart:106`) **merges** a partial
`TextTheme` onto `Typography`'s Material 3 defaults rather than replacing them,
so three roles the app reaches at real call sites are absent and silently
inherit Material's 2021 values:

| Role | Falls back to | vs. every declared role |
|---|---|---|
| `bodySmall` | 12px, w400, letterSpacing 0.4 | app roles use letterSpacing 0 |
| `titleSmall` | 14px, w500, letterSpacing 0.1 | every other app title is w600 |
| `titleLarge` | 22px, w400 | the app's one heading role is w600 |

`bodySmall` carries nearly every explanatory paragraph in Settings. In an app
built for low-vision readers, the longest prose in the app is drawn at 12px in
a configuration nobody chose.

**`titleLarge` reaches the screen through a component theme, not a call site.**
`appBarTheme` (`app_theme.dart:117-126`) sets no `titleTextStyle`, so all 12
`AppBar`s fall back to Material's `titleLarge` — 22px at w400, the one heading
in the app drawn at regular weight. There is exactly one explicit call site
(`position_conflict_sheet.dart:218`). A fix that only chases call sites misses
all 12 app bars, which is the whole reason this is an ADR and not three
tickets.

Evidence the scale drifted rather than being applied: `displaySmall` (32/w600)
has zero references in `app/lib`; `bodyMedium` (14/w400) has 26, nine of them
in `about_screen.dart` alone.

Two roles that differ by 16/w600 against 14/w500 do not read as a hierarchy.
They read as a mistake.

## Decision

### 1. Four roles, expressed as ratios of a base

| Role | Slot | Ratio · weight · colour | Used for |
|---|---|---|---|
| Screen title | `headlineSmall` | 1.5 · w600 · `onSurface` | App bar titles, About's app name |
| Section header | `titleLarge` | 1.25 · w600 · `onSurfaceVariant` | Every group label |
| Row label | `titleMedium` | 1.0 · w600 · `onSurface` | List row titles, control labels |
| Secondary | `bodyLarge` | 1.0 · w400 · `onSurfaceVariant` | Subtitles, values, all explanatory prose |

The base is 16 logical pixels at a text scale of 1.0. **Roles are ratios, never
absolute sizes.** The app already honours `MediaQuery.textScaler`
(`app_shell.dart:241`, `library_screen.dart:684`, `free_books_screen.dart:671`),
and stating the scale as ratios is what keeps this table true at 2.0 as well as
1.0 — a table of pixel constants is only a decision about one device setting.

Section header gets its own size rather than sharing `titleMedium` with Row
label and separating by colour alone. Telling `#2A2E31` from `#000000` at
identical size and weight is a harder discrimination for this reader than
telling 20px from 16px, and ADR 0032 needs colour for other work.

### 2. Nothing in chrome sits below the base

There is no 14 tier and no 12 tier. `bodyMedium`, `bodySmall`, `labelLarge`,
`labelMedium` and `labelSmall` all resolve to a base role.

An earlier draft exempted the 12px sites as "button and chip text." That is not
what they carry: `app_shell.dart:238,347` are nav labels, but
`book_progress.dart:225,287` are numeric progress readouts and
`library_screen.dart:823,832,917,926`, `free_books_screen.dart:805,813` and
`home_screen.dart:689` are book metadata. A 12px percentage readout is content,
and an allow-list of sanctioned exceptions is a rule the fourth consumer will
not know about — the same failure ADR 0032 diagnoses for per-consumer contrast
checks.

### 3. Every `TextTheme` slot is declared

All thirteen, with the nine this table does not name aliased onto the nearest
role. The root cause is the merge; declaring every slot means there is nothing
left to merge onto.

The alternative — declare four and assert the other nine are never resolved —
is a claim about every current *and future* Flutter component default. The app
bar is proof the app cannot see those coming. Declaration is enforceable;
abstinence is not.

### 4. The app bar takes the Screen title role, and wraps rather than truncates

`appBarTheme.titleTextStyle` is set explicitly. This is a visible change to all
12 app bars (22/w400 to 1.5 base at w600), not a silent cleanup. A title that
does not fit wraps to a second line and the app bar grows; it is never
ellipsised. Truncating a screen name for a reader at 2.0 text scale withholds
it from exactly the reader least able to guess the rest.

### 5. `displaySmall` is deleted

Zero references. About's app name moves to Screen title.

### 6. Enforcement, not convention

A test asserts that every `TextTheme` role the app can resolve is one this ADR
declares, **including roles reached through component themes**
(`appBarTheme`, `listTileTheme`), which is where this defect actually lived.
The next undeclared-role gap fails CI rather than shipping silently.

## Consequences

- **Depends on ADR 0034.** Secondary at the base is only affordable once the
  prose volume drops, and ADR 0034 deletes `account_screen.dart` and
  `sync_screen.dart` — roughly 127 words out of the Settings subtree, more than
  any prose-trimming ticket was going to remove. An earlier draft made this ADR
  depend on #352 and #357 instead: #357 has since landed (`info_dot.dart`), and
  #352's figure for `settings_screen.dart` was never true — that file has no
  explanatory `Text` widgets at all, only row titles and current values.
- `about_screen.dart` is the remaining risk: nine `bodyMedium` sites moving to
  the base. It is already capped at `AppContent.proseMaxWidth`, so it grows
  taller, not wider.
- `listTileTheme.subtitleTextStyle` (`app_theme.dart:190`) moves from
  `bodyMedium` to `bodyLarge` with `onSurfaceVariant`.
- `SectionHeader` (`section_header.dart:13-47`) moves from `titleMedium` to
  `titleLarge`. It is already one shared widget — #346 closed that; an earlier
  draft of this ADR claimed four independent implementations still existed.
- The 26 `bodyMedium` call sites migrate to `bodyLarge` or `titleMedium`, one
  decision per site.
- `app_typography.dart:18-21`'s doc comment names `bodyMedium`/`labelSmall` for
  tabular figures and needs rewriting against section 2.
- #338 (an in-app chrome text-size control) becomes plumbing rather than a
  redesign: it exposes the base, and every role follows.
- Closes #358, #341, #342, and the 12px half of #361.

## Alternatives considered

- **Fix #341/#342 individually.** Leaves the merge behaviour that caused them
  in place for the next screen to trip over, and would not have found the app
  bar, which has no call site to inspect.
- **Declare four slots and assert the rest are never resolved.** Rejected in
  section 3: unenforceable against future Flutter defaults.
- **Absolute pixel sizes.** Simpler to write and simpler to test, and wrong the
  moment the reader raises text scale — which this audience does.
- **Adopt Material 3's default scale unchanged.** Removes the divergence in one
  commit, but a 12px `bodySmall` and 0.4 letterSpacing are the two things this
  audience least needs.
- **Keep eight treatments and document them.** Documenting an accident does not
  make it a system.

## Verification

A widget test that builds each screen's theme and asserts no resolved text
style lands on an undeclared role, covering component-theme defaults rather
than only explicit call sites. A ratio test that the four roles hold their
proportions at text scale 1.0 and 2.0. Screenshot comparison of Settings,
Appearance and one app bar before and after, including a long title at 2.0.
