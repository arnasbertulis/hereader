# Contributing

This is a solo portfolio project, but it follows the same discipline a real
team would use, and that discipline is documented here so it stays
consistent rather than living only in the author's head.

## Branches

`<type>/<short-kebab-case-description>`, using the same types as commits
below — for example `fix/pending-positions-for-absent-books` or
`docs/update-readmes`.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/). Types in use:
`feat`, `fix`, `build`, `docs`, `test`, `style`, `refactor`, `chore`.

A commit's body should explain *why* the change exists, not restate the
diff. "Fixed a bug" is not a commit message; "applyRemotePosition wrote
straight into reading_positions, failing the cascade constraint when the
book was not on this device" is.

## Pull requests

Every change goes through a PR, even solo. Description follows four
sections:

```
## What
What changed, in a few sentences or a short list.

## Why
The problem this solves, or the decision behind it. This is the part worth
writing carefully — the diff already shows what changed.

## Testing
How it was verified. "Documentation only" is a valid answer when true.

## Notes
Anything deliberately left out, follow-up work, or context a reviewer
would otherwise have to ask for.
```

Squash-merge is preferred. GitHub's autofill for the squash commit just
repeats the individual commit subjects as a bulleted list, which is not useful
history — the squash commit's extended description is rewritten by hand to say
why the change exists and what was verified.

Plain prose, in paragraphs. No leading `*` or `-`, no headings, no PR-style
sections: `git log` is read in a terminal, and a body that is a list of commit
subjects says what a reader could already see from the diff instead of why any
of it happened.

## Scope of a change

A change is split into a stack of pull requests when it crosses a package
boundary, or when it exceeds roughly 800 lines of hand-written diff, whichever
comes first. Generated files and test fixtures do not count toward that budget.

The stack is built bottom-up, one layer per PR, lowest first: the pure packages,
then the app's plumbing, then the screens that use it, then the documentation
describing the result. **Every PR in the stack passes every required check on
its own**, with the layers above it unwritten. That is what makes `git bisect`
useful and a revert surgical rather than all-or-nothing.

This works because the pure packages are path dependencies (ADR 0001): a change
to `rsvp_engine` merges and `app` picks it up with no publish and no version
bump. It depends on the lower layer's change being **additive**. Where it is not
— a field removed, a JSON shape changed, a signature narrowed — the addition and
the removal are separate PRs, the removal landing only after every caller has
stopped using the old form, so that no single PR both breaks a caller and fixes
it.

A change that genuinely cannot be decomposed this way stays in one PR, and its
Notes section says why. Those are rarer than they look: adding the new form
beside the old one usually works even where it first appears not to, and the
cost of carrying both for two PRs is smaller than the cost of a diff nobody can
read in one sitting.

The ADR opens the stack rather than closing it. An ADR is written the day the
decision is made rather than reconstructed afterward, and for a stacked change
that means the design and its rejected alternatives land first, with the
Verification section stating that the work is not yet built. The last PR in the
stack fills that section in with what was actually run.

Two costs, both accepted deliberately. Intermediate PRs merge code that nothing
calls yet, which is unreachable on `main` until the stack completes — so a stack
is finished rather than abandoned partway. And each PR carries its own
description and its own CI run, which is more ceremony than one large PR. The
trade is worth it once a change stops fitting in a single reading.

For reference, [#94](https://github.com/arnasbertulis/hereader/pull/94) is the
counter-example: one commit, 33 files, +5,458/−285, across two packages and the
docs. Its engine layer was strictly additive — `playback_session.dart` deleted
nothing at all — so the split was available and simply was not taken.

## Architecture Decision Records

A substantial decision gets an ADR in `docs/adr/`, written the same day the
decision is made and verified working — not reconstructed afterward from
memory. "Substantial" means: the reasoning would not be obvious from the
diff alone, there were real alternatives that were rejected, or a future
change is likely to want to know why this one was made the way it was. A
one-line config change is not an ADR; deciding how reading positions
survive a tokenizer change is.

Each ADR states the alternatives considered and why they were rejected, not
just the option chosen. The point of the alternatives section is to stop
the same rejected option from being re-proposed later without the context
of why it didn't work.

An ADR records a *decision*. A constraint imposed from outside — a browser
policy, a platform limit — is not a decision and belongs in the README's
known limitations instead, with whatever evidence establishes it. If that
constraint later changes what this project chooses to build, *that* is the
ADR.

A Verification section describes runs that actually happened. If a claim in
one was written from expected behaviour rather than an observed result, say
so rather than letting it read as a result.

## Tests

Tests are written before or alongside the feature, not after. A bug fix
gets a regression test in the same PR as the fix — not a follow-up, unless
the PR notes explicitly say so and explain why.

Where a change is an optimisation, the test targets what the optimisation
could break rather than the optimisation itself. Asserting that something
got faster usually means adding a hook to production code for a test's
benefit, which costs more than the coverage is worth; asserting that the
behaviour it skipped still happens does not.

## Static analysis

Each package has its own `analysis_options.yaml`, extending
`package:lints/recommended` or `package:flutter_lints`. The additions are the
same set in every package, so a rule does not mean two different things
depending on which directory it fires in.

Rules are chosen from the code rather than from a list. A rule earns its
place by describing a discipline this project already keeps by hand —
`unawaited_futures` and `cancel_subscriptions` are enforced because every
dropped future and every subscription here is already handled deliberately,
in comments, with nothing checking it. A rule that would produce a large
cleanup is not added alongside the feature that needed it; it gets its own
PR or it waits.

**A rule that fires on correct code is removed, not suppressed.** An
`// ignore:` comment on a wrong rule teaches the next reader that the rule is
noise while leaving it switched on, which is worse than not having it.
`no_adjacent_strings_in_list` was tried and dropped for exactly this: it
flagged test fixtures that wrap one long string across several lines inside a
list literal, and following its suggested fix silently broke two tests by
turning long prose blocks into short ones that then matched a length-gated
boilerplate check.

`flutter analyze` and `dart analyze` run in CI on every push and fail on any
diagnostic, so a rule added is a rule enforced.

## Documentation

Package-level READMEs (`app/README.md`, `server/README.md`, and the
packages under `packages/`) are kept current as part of the change that
makes them stale, not batched into a separate cleanup pass later. If a PR
changes what a README claims about the project, the README changes in the
same PR.

"Not built yet" / "Known limitations" sections are treated as load-bearing,
not decorative — an interviewer reading the README should get an accurate
picture of the project's actual state, including its gaps.

## Windows / PowerShell

The primary development environment is Windows with PowerShell. Git
commands in PR descriptions, commit instructions, and any setup scripts
should use PowerShell syntax where they differ from bash (`$env:VAR = `
rather than `export VAR=`, `New-Item` rather than `mkdir -p`, and so on).
