# Evidence notes: RSVP and reading

Working notes on the research behind this project's design, including the
findings that argue against it. The README carries the summary; this file
holds the detail and connects each finding to a specific feature.

Every citation below was checked against its journal record. Where a
figure could not be traced to a primary source, it has been left out
rather than reported at second hand.

---

## What this project claims, and does not

**Claims:** presenting text one word at a time in a fixed screen position
removes the need to locate each successive word, and for readers who
cannot use central vision efficiently, that removal is worth something
measurable but modest.

**Does not claim:** that RSVP makes normally sighted people read faster
with comprehension intact.

**Also does not claim:** that RSVP is uniquely suited to central field
loss. The best available comparison found the opposite ordering, and it
is discussed below rather than omitted.

---

## 1. Normally sighted readers

The speed-reading case for RSVP rests on the idea that eye movements are
the bottleneck. They are not; language processing is. Two further
problems are specific to RSVP:

- **Regressions are impossible.** Skilled readers move backward through
  text regularly, and those movements do real comprehension work on
  difficult sentences. A single-word stream cannot support them.
- **Parafoveal preview is removed.** Normal reading partially processes
  the next word before fixating it. RSVP eliminates that.

The review concludes there is a trade-off between speed and accuracy, and
that the durable route to reading faster is becoming a more skilled
language user rather than changing how text is displayed.

> Rayner K, Schotter ER, Masson MEJ, Potter MC, Treiman R (2016). So Much
> to Read, So Little Time: How Do We Read, and Can Speed Reading Help?
> *Psychological Science in the Public Interest* 17(1):4–34.
> PMID 26769745. doi:10.1177/1529100615623267

**Feature:** rewind-on-pause partly compensates for the loss of
regressions. When playback stops, the reader backs up several words,
because the last words displayed were probably never processed. The count
is a user setting.

---

## 2. RSVP compared with page reading in low vision

This is the study the project's premise actually rests on.

Fourteen participants with dense central scotomas (CFL) and nine
low-vision participants without scotomas (noCFL) read under both RSVP and
conventional page presentation.

- RSVP was faster than page reading for both groups.
- **CFL participants improved by a factor of about 1.5 (SD 0.41); noCFL
  participants improved by about 2.1 (SD 0.38).** The group with central
  scotomas benefited *less*.
- Scanning laser ophthalmoscope recordings in four CFL participants
  confirmed RSVP reduced saccades by an average of about 1.3 per word.
- Even with fewer saccades, CFL participants still required longer word
  durations than noCFL participants.
- The authors conclude that inefficient eye movements account for only
  **part** of the reading speed reduction caused by central field loss.

> Rubin GS, Turano K (1994). Low vision reading with sequential word
> presentation. *Vision Research* 34(13):1723–1733. PMID 7941378.
> doi:10.1016/0042-6989(94)90129-5

**Honest reading of it:** removing the search for the next word helps,
the mechanism is confirmed rather than assumed, and it is not a
transformation. Central field loss slows reading for reasons beyond eye
movements, and no presentation format addresses those.

---

## 3. Reader-controlled advance beats fixed-rate RSVP

"Elicited sequential presentation" (ESP) is a variant in which words
appear at a constant screen location, as in RSVP, but the reader triggers
each new word with a button press instead of receiving it on a timer.

Fifteen slow low-vision readers who habitually used CCTV magnifiers were
tested with ESP, RSVP, and their CCTV.

- **ESP produced reading speeds averaging 47% faster than RSVP**, roughly
  matching their CCTV speed.
- Slower readers benefited more. The regression predicted no benefit for
  readers already reading at 133 wpm or above under RSVP.
- Word length and the duration readers chose were significantly
  correlated, suggesting part of the benefit comes from readers
  allocating time per word themselves.

> Arditi A (1999). Elicited sequential presentation for low vision
> reading. *Vision Research* 39(26):4412–4418. PMID 10789434.
> doi:10.1016/S0042-6989(99)00154-6

**Feature:** manual advance is a first-class pacing mode, not a fallback.
Hold or tap to move forward, no timer. On this evidence it should be the
default for the low-vision preset, with auto-pacing offered as an option
rather than the reverse.

---

## 4. Variable word duration

Readers with central field loss from age-related maculopathy read RSVP
text at a constant rate and at three rates where duration varied by word
length.

- **CFL readers got through sentences an average of 33% faster** with
  variable duration.
- Older normally sighted readers reading foveally were fastest with
  **constant** duration.
- Slower CFL readers tended to benefit more than faster ones.
- The authors conclude that varying word duration by word length would
  improve reading rates for low-vision patients with CFL.

> Aquilante K, Yager D, Morris RA, Khmelnitsky F (2001). Low-vision
> patients with age-related maculopathy read RSVP faster when word
> duration varies according to word length. *Optometry and Vision
> Science* 78(5):290–296. PMID 11384006.
> doi:10.1097/00006324-200105000-00012

**Feature:** `pacingModel` offers at least `constant`, `lengthScaled`,
and `elicited`, because the same feature has opposite effects in
different populations. Length scaling defaults on for the low-vision
preset and off elsewhere.

---

## 5. What the training studies do and do not show

A figure of 53% improvement in RSVP reading speed for people with central
vision loss circulates widely. **It is a training effect, not a
comparison against page reading, and it must not be cited as evidence
that RSVP is faster than a book.**

Six participants (mean age 73.8) with long-standing macular disease
completed six sessions of perceptual learning, reading roughly 300
sentences aloud under RSVP. Their post-training RSVP speed averaged 53%
higher than their pre-training RSVP speed.

Chung's discussion lists as open questions whether the improvement
transfers to page reading, what training duration is optimal, and whether
comprehension improves alongside speed.

> Chung STL (2011). Improving Reading Speed for People with Central
> Vision Loss through Perceptual Learning. *Investigative Ophthalmology &
> Visual Science* 52(2):1164–1170. PMID 21087972. doi:10.1167/iovs.10-6034

**Relevance here:** limited. It suggests reading speed under RSVP
improves with practice, which implies a new user's first session is not
representative of what they could reach. It says nothing about RSVP
versus conventional reading. Later work attempted to replicate it with
smaller reported effects; those figures are not repeated here because
they were only located in secondary sources.

---

## 6. Findings that argue against features

Kept deliberately, so the design is not justified only by evidence that
agrees with it.

**Vertical text does not help.** Readers with preferred retinal loci to
the left of their scotoma were trained on 90-degree-rotated RSVP.
Training improved their vertical reading but did not produce speeds
appreciably exceeding those following horizontal RSVP training.

> Calabrèse A, Liu T, Legge GE (2017). Does Vertical Reading Help People
> with Macular Degeneration: An Exploratory Study. *PLOS ONE*
> 12(1):e0170743. doi:10.1371/journal.pone.0170743

**Line spacing does not help AMD readers.** Increased line spacing
improves reading speed in normal peripheral vision, but reading speeds
for AMD participants were essentially flat across the range of line
spacings and RSVP vertical word separations tested, except at the
smallest separation where speed was lower.

> Chung STL, Jarvis SH, Woo SY, Hanson K, Jose RT (2008). Reading speed
> does not benefit from increased line spacing in AMD patients.
> *Optometry and Vision Science* 85(9):827–833. PMID 18772718.
> doi:10.1097/OPX.0b013e31818527ea

A later study found only a small effect of interline spacing on maximal
reading speed in low-vision patients with central field loss, regardless
of scotoma size.

> Calabrèse A, Bernard JB, Hoffart L, Faure G, Barouch F, Conrath J,
> Castet E (2010). Small effect of interline spacing on maximal reading
> speed in low-vision patients with central field loss irrespective of
> scotoma size. *Investigative Ophthalmology & Visual Science*
> 51:1247–1254. PMID 19834038. doi:10.1167/iovs.09-3682

Spacing controls still ship, because they have support for dyslexia
(below) and because reader comfort justifies a setting. They are not
presented as a low-vision feature.

**Magnification alone does not solve it.** People with macular
degeneration read slowly even when print size adequately compensates for
their acuity loss, and oculomotor deficits cannot fully explain the size
of the reduction. The authors hypothesise slower temporal processing of
visual patterns in peripheral vision as a contributing factor.

> Cheong AMY, Legge GE, Lawrence MG, Cheung SH, Ruff MA (2007).
> Relationship between slow visual processing and reading speed in people
> with macular degeneration. *Vision Research* 47(23):2943–2955.
> doi:10.1016/j.visres.2007.07.010

---

## 7. Other accessibility claims

**Letter spacing and dyslexia.** Increased inter-letter spacing improved
text reading performance without any training in a large, unselected
sample of Italian and French dyslexic children.

> Zorzi M, Barbiero C, Facoetti A, Lonciari I, Carrozzi M, Montico M,
> Bravar L, George F, Pech-Georgel C, Ziegler JC (2012). Extra-large
> letter spacing improves reading in dyslexia. *PNAS* 109(28):11455–11459.
> PMID 22665803. doi:10.1073/pnas.1205566109

Two caveats carried deliberately. The sample was children reading Italian
and French, not adults reading English or Lithuanian. And the paper drew
a published critique questioning the statistical and practical
significance of the effect:

> Skottun BC, Skoyles JR (2012). Interletter spacing and dyslexia. *PNAS*
> 109(44). doi:10.1073/pnas.1212877109

**Coloured overlays.** Tinted overlays and the "Irlen syndrome"
construct have largely not survived controlled trials. The tint control
ships as a user preference with no efficacy claim attached.

**Typefaces.** OpenDyslexic's specific efficacy is contested. Atkinson
Hyperlegible was designed by the Braille Institute for low vision and
prioritises character disambiguation. Both are options, neither is a
default.

---

## 8. Findings mapped to features

| Finding | Source | Feature |
|---|---|---|
| Reader-controlled advance beat RSVP by 47% in slow low-vision readers | Arditi 1999 | `elicited` pacing mode, default for the low-vision preset |
| Duration scaled to word length: +33% for CFL, worse for normally sighted | Aquilante 2001 | `pacingModel` as a per-profile setting |
| RSVP cuts ~1.3 saccades/word for CFL readers | Rubin & Turano 1994 | Fixed word position is the core presentation |
| CFL readers benefit less than other low-vision readers | Rubin & Turano 1994 | Claims kept modest throughout |
| Regressions are lost under RSVP | Rayner et al. 2016 | Rewind-on-pause, configurable word count |
| No benefit predicted above 133 wpm under RSVP | Arditi 1999 | Low-vision preset defaults slow, not fast |
| Preferred retinal loci are often left of the scotoma | Calabrèse et al. 2017 | `anchorX` / `anchorY` offsets saved per profile |
| Vertical text gives no benefit | Calabrèse et al. 2017 | Not built |
| Line spacing does not help AMD | Chung et al. 2008 | Spacing offered, not framed as low-vision |
| Letter spacing helps dyslexic children, contested | Zorzi 2012, Skottun & Skoyles 2012 | Spacing control, no efficacy claim |
| Reading speed under RSVP improves with practice | Chung 2011 | First-session speed is not treated as a ceiling |

---

## 9. Open questions

- Arditi (1999) is a 15-participant study on CRT displays. Whether the
  ESP advantage survives on a modern touchscreen is untested, and this
  project cannot test it.
- Attempted replications of Chung (2011) reported smaller effects, but
  those papers have not been read directly and no figure is quoted here.
- No evidence gathered on RSVP and ADHD, despite it being a common
  informal justification for apps of this kind. Nothing in the app should
  claim it until that changes.
- No independent evidence found on optimal recognition point
  highlighting. Most of what exists publicly is vendor material.
- Word frequency scaling is planned on the reasoning that rare words need
  longer, but no source has been found testing this under RSVP.
- **Comprehension is not measured in any study cited here.** Every figure
  above is a reading-rate figure. That is a gap in the evidence base, not
  only in this implementation.
