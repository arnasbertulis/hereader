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
repeats the individual commit subjects, which is not useful history — the
squash commit's extended description is rewritten by hand to say why the
change exists and what was verified, in plain text with no PR-style
formatting.

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
