# 0035. On the reading surface, hierarchy is size and position, and every control names itself

Date: 2026-09-07

## Status

Accepted. Extends ADR 0015 to the transport's own vocabulary. Keeps ADR 0021's
four jumps and two-row layout unchanged.

## Context

ADR 0032 gives the rest of the app a colour vocabulary — a fill Material
derives a foreground against, never ink. That vocabulary is unavailable on the
reading surface. ADR 0015 makes reader chrome monochrome over the profile, and
the buttons drawn straight on the surface take no theme at all, only an ink
colour picked from the surface's measured luminance.

The code already reached the right conclusion and wrote it down.
`reader_screen.dart:1628-1640` records that hierarchy on this screen is carried
by **size**, precisely because fill and colour are ruled out: Play is
`_primaryIconSize` 44, everything else `_secondaryIconSize` 28. What has never
been written down is that this is a rule rather than one screen's local
choice — so the next control added here has nothing to check itself against.

**Names exist but do not reach a touch reader.** All seven transport controls
carry a `tooltip:`, as does the conditional Chapters button — 'Back a
paragraph', 'Back a sentence', 'Forward a sentence', 'Forward a paragraph',
'Back to library', 'Reading profile', and Play's four-state label. A tooltip is
a pointer affordance. On the touch devices this app is primarily used on, none
of those names is ever drawn, so the reader is left discriminating four seek
glyphs that differ by one stroke.

Two of #354's claims do not survive reading the file. Close and Play are **not**
"identical weight" — 28 against 44, and the size hierarchy is deliberate and
documented. And its "~136px apart on a 502px viewport" measurement predates
#329, which capped the row at `_controlsMaxWidth` 360 (`:1647`), so spacing no
longer tracks the window.

**The RSVP word still wraps.** `rsvp_view.dart:56-118` draws the token as a
plain `Text` with `textAlign: TextAlign.center` and **no `maxLines`, no
`overflow`, no `softWrap: false`, no `FittedBox`**. A word wider than the
viewport breaks across three lines, which moves the fixation point RSVP exists
to hold still. Commit d11e9da added `scaledFontSizePt`
(`profile_presentation.dart:445-460`) but it only ever *grows* type —
`if (availableWidth <= referenceWidth) return basePt` — so it closed the
scale-to-fill half and left this one untouched. Commit cd27723 stopped the
wrapped word painting over the progress bar by reserving the controls' height,
which removes the overlap but not the movement.

**Chrome visibility is not a toggle.** `reader_screen.dart:1086` is
`showControls = state != PlaybackState.playing`, and everything gated on it is
removed from the tree rather than faded. While playing, the tree is the reading
surface plus three invisible tap zones. So a tap does not hide the chrome; it
starts playback, and playback hides it.

## Decision

### 1. Hierarchy is size and position, never fill and never colour

The reading-surface counterpart to ADR 0032, under ADR 0015's constraint. A new
control on this surface earns prominence by being larger or by sitting in the
row that carries book-level actions — never by being filled or tinted.

### 2. Every transport control names itself in visible text

A tooltip is not a label. If a control's name matters enough to write into a
`tooltip:`, it matters enough to draw.

### 3. Labels name the axis, not the button

One "Sentence" under the inner pair and one "Paragraph" under the outer pair,
with direction carried by the glyph. Left and right is a discrimination this
reader already has; sentence against paragraph is the one they do not.

Two labels fit the 360 cap at ADR 0031's base size where four do not, which is
what makes this compatible with keeping four jumps. **ADR 0021 stands**: its §2
arithmetic for two rows is unchanged, its §3 glyphs stay in use, and its §4
modifier keys are untouched.

### 4. The word never wraps

The fixation point is the thing this surface exists to hold still, so a token
too wide for the measure is scaled down to fit rather than broken across lines.
This is the scale-to-fit counterpart to d11e9da's scale-to-fill, in the same
`LayoutBuilder`.

### 5. Playback starts only from a deliberate act on the reading surface

Dismissing a sheet is not such an act. This ADR states the rule and not the
repair, because the mechanism is unverified: `_pickProfile` pauses on open
(`:700`) and returns early on a null intent (`:825`), so nothing in that method
resumes playback, and no explicit barrier pass-through exists in the file. The
behaviour must be reproduced before it is fixed. Owned by #366.

## Consequences

- Closes #354 and #365, and the first half of #366.
- The seek row gains a label line and grows vertically. cd27723 already
  reserves the controls' height rather than overlaying the word, so this
  changes a reserved height rather than reintroducing an overlap — but it eats
  vertical space on a 320-high viewport, which is the constraint to check
  first.
- **Section 4 needs a floor, and this ADR does not set one.** Scaling a token
  down conflicts with the size the reader chose in their profile, and a long
  German compound at a 48pt profile cannot both fit and stay at 48pt. The floor,
  and what happens below it, is #365's to decide and to justify against ADR
  0025's two reading surfaces. Recorded here so it is decided rather than
  discovered.
- #366's point 4 is already stale and should not be implemented: under
  `awaitingAdvance` the button shows the pause glyph and reads 'Stop advancing'
  (`:1724-1735`).
- Coarse movement does not depend on the transport at all —
  `reader_screen.dart:1026-1043` scrubs on a horizontal drag anywhere on the
  surface, chaptered book or not. Worth stating because it is the reason
  section 3 could keep four jumps without that being the only coarse seek.
- Section 2 applies to the Chapters button, which is conditional on the book
  declaring chapters, so its label appears and disappears with it.

## Alternatives considered

- **Drop the paragraph pair and label the remaining three controls.**
  Contradicts ADR 0021 §2, which chose four jumps and gave the arithmetic for
  two rows; it would strand the two glyphs §3 verified against the vendored
  font's `cmap`, and it un-rejects the single row §2 un-rejected. Rejected: the
  discrimination problem #354 raises is solved by naming the axis, so removing
  a capability to solve it is paying more than the fix costs.
- **Label all four seek buttons individually.** Does not fit `_controlsMaxWidth`
  at ADR 0031's base size, and shrinking the labels to fit is exactly what ADR
  0031 §2 forbids.
- **Keep tooltips and rely on the size hierarchy.** This is today's design. It
  counts a pointer affordance as an accessibility feature for an audience
  mostly on touch.
- **Wrap the word to two lines instead of three.** Still moves the anchor,
  which is the defect.
- **Let an over-wide word overflow the viewport.** Holds the anchor and loses
  the ends of the word, which is worse than making it smaller.

## Verification

A widget test that every transport control's name is rendered text, at text
scale 1.0 and 2.0, with the row inside `_controlsMaxWidth` and the whole
transport inside a 320-high viewport. A test that no transport control resolves
a fill or a non-ink colour. A `rsvp_view` test that a token wider than the
viewport renders on one line at a reduced size, plus a golden at 320 wide.
#366 is reproduced by hand before anything is changed for it.
