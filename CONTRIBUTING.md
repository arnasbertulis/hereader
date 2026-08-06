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

## Tests

Tests are written before or alongside the feature, not after. A bug fix
gets a regression test in the same PR as the fix — not a follow-up, unless
the PR notes explicitly say so and explain why.

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
