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

A pull request is not opened until the claim it exists to make has been
observed to hold, locally, at least once. An adjacent green check is not that
observation: `flutter build web` proves the app compiles, and ADR 0009 exists
because compiling is not executing. Where the run that would prove the claim
cannot be made to finish, that is the work — CI confirms a result already
seen rather than being the first place it is attempted.

The one exception is the browser suite: it is gated on a release tag rather
than on every pull request, so this rule reaches it only there — see
`app/README.md`'s Testing section for when to run it locally.

The cost of getting this backwards is paid in half-hour cycles. #109 was
opened on a browser test run that had never completed on the author's
machine; the CI step then hung for 25 minutes and was cancelled, twice,
before the cause turned out to be readable in `flutter_test`'s own source
without running anything at all.

## Scope of a change

A change is split into a stack of pull requests when it crosses a package
boundary, or when it exceeds roughly 800 lines of hand-written diff, whichever
comes first. Generated files and test fixtures do not count toward that budget.

The stack is built bottom-up, one layer per PR, lowest first: the pure packages,
then the app's plumbing, then the screens that use it, then the documentation
describing the result. **Every PR in the stack passes every required check on
its own**, with the layers above it unwritten. That is what makes `git bisect`
useful and a revert surgical rather than all-or-nothing.

Path dependencies (ADR 0001) make this cheap: an engine change merges and `app`
picks it up with no publish and no version bump. It requires the lower layer to
be **additive**. Where a function changes shape instead, the new form lands
beside the old one, the callers move, and the old form is deleted last, so no
single PR both breaks a caller and fixes it. A change that genuinely cannot be
decomposed that way stays in one PR and says why in its Notes — rarer than it
looks, since adding the new form beside the old usually works even where it
first appears not to.

The ADR opens the stack rather than closing it. An ADR is written the day the
decision is made rather than reconstructed afterward; ordering it first also
means every later PR has the design available without depending on whoever
wrote the one before. Its Verification section states that the work is not yet
built, and the last PR in the stack fills it in with what was actually run.

Two costs, accepted deliberately. Intermediate PRs merge code nothing calls yet,
unreachable on `main` until the stack completes — so a stack is finished rather
than abandoned partway. And each layer carries its own description and CI run.

### Tracking the stack

A stack of three or more layers gets a tracking issue, opened before the first
PR. Its body carries the goal, a link to the ADR, and the layers as a task
list. It is edited whenever the plan changes, which is the reason the plan
lives there rather than in a committed file that would need its own commit to
correct.

Each PR links back from its Notes section: `Part of #96` on every PR but the
last, which uses `Closes #96` so the issue closes on merge. Both go in the PR
description rather than the commit body, where a stray closing keyword would
fire early.

Branches are cut from a freshly pulled `main` each time, never from the
previous layer's branch. Branches based on each other have to be rebased every
time a lower layer changes, and that only pays for itself where waiting on a
reviewer is the bottleneck — which it is not here.

For reference, [#94](https://github.com/arnasbertulis/hereader/pull/94) is the
counter-example: one commit, 33 files, +5,458/−285, across two packages and the
docs. Its engine layer was strictly additive — `playback_session.dart` deleted
nothing at all — so the split was available and simply was not taken.

## Issues

A bug found and not fixed the same day gets an issue, and so does cleanup that
is deferred rather than done. The alternative is a note somewhere outside the
repository, which is invisible to anyone reading the project and is where
deferred work goes to be forgotten.

An issue and a known limitation are not the same thing and the distinction is
worth keeping. An issue is for something meant to change. The README's *Known
limitations* is for a trade taken deliberately, and the issue templates already
point a reporter there first, so a fact that lands in both will drift.

Two templates in `.github/ISSUE_TEMPLATE/`, `bug_report.yml` and
`feature_request.yml`, applying the `bug` and `enhancement` labels. Blank
issues are switched off, so an issue opened through the web interface has to
pick one of them.

`gh issue create` bypasses templates entirely, and that is the path used here,
so an issue filed from the command line carries the same fields by hand: what
happened, what was expected instead, how to reproduce it, and which platform.
Otherwise the templates are enforced on the one path this project does not
take.

Tracking issues for a stack of pull requests are a different thing again, with
their own rules under *Tracking the stack* above.

## Releases

Landing a change on `main` does not ship it. A deploy runs from a `v*` tag, for
the reasons in [ADR 0023](docs/adr/0023-continuous-deployment.md), which also
covers what a rollback needs and why the server only ever pulls.

Versions are semantic and pre-1.0: a release carrying a feature takes the minor
number, one that is only fixes or documentation takes the patch. 1.0 is not a
milestone that arrives by accumulation, and until something decides it, the
major stays at zero.

**Check the workflows are green on the exact commit before tagging, not on the
branch.** The three CI workflows are separate files and cannot gate each other,
so `main` is green only in the sense that each workflow passed independently;
`gh run list --branch main` names the sha each result belongs to. Tagging a
commit whose checks are still running is how a deploy starts from something
nobody has verified.

The tag is annotated, never lightweight — a lightweight tag carries no message,
and the message is the only place a release says what it contains:

```powershell
git tag -a v0.2.0 <commit>    # opens the editor; -F - reads a piped message
git push origin v0.2.0
```

Written as prose, in the same voice as a squash commit body, and for the same
reason: a list of the pull requests in the range is something `git log` already
answers. Say what a reader of the app gets out of this release, and what
changed on the server. The subject line does **not** repeat the version, since
`git tag -n` prints the tag name beside it and `v0.2.0 v0.2.0 ...` is what
repeating it looks like.

After the push, watch the deploy — `gh run watch <id> --exit-status` — and then
check the deployment yourself rather than reading the workflow's own result.
The pipeline polls `/health` and reports what it saw at that moment; a request
to `/api/health` and to the site root afterwards is a different question, asked
from outside the machine that just answered it.

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

`dart format` is verified the same way, in every package including `app`.
Formatting left unchecked is not neutral: it turns up later as reflowed lines
in the diff of whatever change happens to touch that file next, which is churn
a reviewer has to read past to find the actual change.

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
