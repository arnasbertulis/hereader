# 0034. A destination whose purpose is one control is a row, and the reader is opaque

Date: 2026-09-07

## Status

Accepted. ADR 0031 depends on this landing first.

## Context

Settings is tab index 2 (`app_shell.dart:65`), an index of six rows each
pushed as a plain `MaterialPageRoute` (`settings_screen.dart:95-101`). Three of
the six branches go a third level deep: Account to `SignInScreen`, Appearance
to `CustomAccentScreen`, Reading profiles to `ProfileEditScreen`.

Two of the six destinations are a screen wrapped around a single button.

`account_screen.dart:24-147` is a `StatelessWidget` that owns no state at all;
its session comes from a `StreamBuilder`. It has **one** interactive control —
Sign out, or Sign in — plus a status tile, a "This device" tile and a 40-word
paragraph about the device identifier.

`sync_screen.dart:22-164` owns exactly one field, `DateTime? _lastSynced`, and
has **one** interactive control, Sync now, disabled unless signed in. Its
signed-out subtitle is literally `'Sign in under Account to turn sync on.'` — a
full screen whose only message is the name of another full screen.

Between them they carry roughly 127 words of prose to offer two buttons.

**Transitions are a separate mechanism, and #374 diagnoses the wrong one.**
`QuietPageTransitionsBuilder` (`page_transitions.dart:21-60`) is installed for
every platform at `app_theme.dart:227` and drives only the **primary**
animation — a fade plus a 0.98-to-1 scale. `secondaryAnimation` is accepted and
never used, so on a push or a pop the outgoing route is not faded at all: one
route fades over a stationary one. The only genuine cross-fade in the app is
tab switching (`_FadingIndexedStack`, `app_shell.dart:380-469`), where both
layers sit at roughly 0.5 mid-way — and that is not what #374 describes. Both
run at `AppMotion.state`, 120ms, and collapse to zero under
`MediaQuery.disableAnimationsOf`.

What #374 actually photographed is the **reader** — pushed by
`book_opener.dart:100-114` as an unmodified `MaterialPageRoute` above the whole
shell, so it takes the same themed fade as About or Appearance, and an RSVP
word is briefly legible over a settings list.

## Decision

### 1. A destination whose entire purpose is one control is a row

Judged by **purpose, not by counting controls**. About has zero interactive
controls and remains a screen, because its purpose is the prose. Sync's purpose
is one button, so it is a row.

Counting is the wrong test twice over: it catches About, which should stay, and
it turns on an implementation detail that flips the moment someone adds a
field — `account_screen.dart` owns no state and `sync_screen.dart` owns one,
and that difference means nothing to a reader. Purpose is what a reviewer can
judge and what a rule can be checked against.

### 2. Account and Sync are deleted

The account moves to the top of the Settings index with its sync control
inline. Two of the three third-level branches in the Settings tree disappear
with them, since `SignInScreen` is reached from Account and
`CustomAccentScreen` is deleted by ADR 0032.

### 3. The reader route is opaque and does not fade

The reader is not a peer of a settings list and should not arrive like one.
Making the route opaque removes the overlap #374 describes at its source,
rather than by tuning a duration.

Driving `secondaryAnimation` so the outgoing route genuinely leaves would fix
the overlap everywhere, and is rejected: it makes every screen change busier,
which is the wrong trade for this audience. `QuietPageTransitionsBuilder` is
named for the right instinct and keeps it.

## Consequences

- Closes #356, #353 and #374.
- **Unblocks ADR 0031.** Removing roughly 127 words from the Settings subtree
  is what makes Secondary text at the base size affordable. ADR 0031 must not
  ship first.
- The Settings index gains an account row with inline sync state, which is more
  than the other five rows carry — the index's own row vocabulary needs a pass,
  not just an insertion.
- `sync.cursor.read()`'s "last synced" value and the sync `state` stream move
  from a screen's `State` to the index row. Watch that this does not become a
  second path writing the same fact alongside `sync.state`.
- Signed-out copy stops referring the reader to a screen that no longer exists.
- `AppMotion.route` (180ms, `app_tokens.dart:61`) is not used by the
  transitions builder, which returns `AppMotion.state`. Left alone here, but it
  is a token that means nothing.

## Alternatives considered

- **Do #356 as written, without a rule.** Deletes the two screens that exist
  today and leaves nothing to stop the next one-control screen being written.
  The rule is the part that generalises.
- **Count interactive controls, exempt About by name.** A named exemption is
  how a rule stops being checkable.
- **Test on owned state rather than purpose.** Would keep `sync_screen.dart`
  and delete `account_screen.dart`, which is precisely backwards from the
  reader's point of view.
- **Keep the screens and give them more to do.** Inventing content to justify a
  navigation level is the wrong direction for an app whose prose volume is
  already the constraint on ADR 0031.
- **Drive `secondaryAnimation`.** Rejected in section 3.
- **Shorten the transition instead.** 120ms is already short; the overlap is
  structural, not a duration problem.

## Verification

A widget test asserting the Settings index has no destination whose body
contains exactly one interactive control. A test that the reader route is
opaque and that pushing it does not render the previous route's subtree. A test
that the account row shows sync state without a `SyncScreen` in the tree.
Screenshots of Settings signed out and signed in.
