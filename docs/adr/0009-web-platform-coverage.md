# 0009. Web coverage is dart2js for the packages, DDC for the app, and a build for the artifact

Date: 2026-08-10

## Status

Accepted. Amended 2026-08-21 to add a real browser run for `app/test/`.
Amended 2026-08-28 to move that run off the pull-request path. Amended
2026-08-29 to gate the rest of the CI stack on what changed.

## Context

Two bugs have reached the deployed web build through the same gap. Both
were integer arithmetic that is exact on the Dart VM and wrong under
`dart2js`, and no automated check ran anywhere except the VM.

They were not the same kind of failure, which is the thing this document
exists to record.

The 64-bit FNV-1a block-id hash was a **compile** failure. `dart2js`
represents `int` as a JS double, exact only to 2^53, and the web compilers
reject integer literals they cannot represent. It never ran; it refused to
build. Any web compilation would have caught it.

`newProfileId` drawing entropy with `nextInt(1 << 32)` was a **runtime**
failure. It compiles cleanly, because `1 << 32` is a legal expression. A
shift is a 32-bit operation in JavaScript, so it evaluates to `0` on that
target and `nextInt(0)` throws. Only execution catches it.

One needs a build. The other needs a browser. Treating "add web testing to
CI" as a single task is what left the second bug uncaught after the first
one had already been paid for.

A third fact was believed to constrain the answer, and was wrong.
`app/test/` builds its database through `package:drift/native.dart`, which
reaches `dart:ffi`, and that was taken to mean `flutter test --platform
chrome` was not a setting to get right but a rewrite of every database test
onto drift's WASM setup, maintained in parallel with the native one. Three
things checked directly show the rewrite is not what this needs:

- `app/lib` has zero `dart:io` imports. The app layer was already
  browser-clean; only the test harness's database setup reached `dart:ffi`.
- Drift's own `WasmDatabase.inMemory`, given a loaded `WasmSqlite3`, is a
  `QueryExecutor` like `NativeDatabase.memory()` is, and constructs
  synchronously (`drift/lib/wasm.dart:82`; the delegate's `openDatabase` at
  `:349` is `_sqlite3!.openInMemory()`, and the `inMemory` factory passes
  `null` for both the path and the filesystem, so there is no real I/O left
  in the open path once the module is loaded). Every call site that
  constructs `AppDatabase(NativeDatabase.memory())` keeps its shape — the
  executor is swapped, not the test.
- Loading the module, however, is a real browser fetch, and **where** it
  happens is the whole constraint. A `testWidgets` body runs inside
  `FakeAsync`, which cannot advance real asynchronous work
  (`flutter_test/lib/src/widget_tester.dart:820-822`; `runAsync` exists to
  escape it). So the load has to complete before any test is declared, in
  `test/flutter_test_config.dart` — which flutter_tools honours on the web
  entrypoint as well as the VM one
  (`flutter_tools/lib/src/test/web_test_compiler.dart:63-78` and
  `web/bootstrap.dart:590-604` emit it as `entryPointRunner`;
  `flutter_test/lib/src/_test_selector_web.dart:52-56` and
  `test_api/lib/src/backend/remote_listener.dart:137` await it ahead of
  `declarer.declare`).
- `flutter_tools/lib/src/test/flutter_web_platform.dart:117` mounts
  `createDirectoryHandler(<cwd>/test)` in the server cascade the browser test
  run serves from. Anything placed in `app/test/` — including a copy of the
  `sqlite3.wasm` the app already ships at `web/sqlite3.wasm` for its own OPFS
  setup — is fetchable at the server root without further configuration.

## Decision

### The pure packages run their suites on Chrome

`dart test -p chrome` runs in CI for `rsvp_engine` and `epub_reader`,
alongside the existing VM run. This is the real `dart2js`, so it covers the
runtime class of failure for everything in those packages.

`epub_golden_test.dart` is annotated `@TestOn('vm')`. It reads its fixture
through `dart:io` and a browser has no filesystem. The annotation makes the
Chrome run skip it rather than fail it. Base64-encoding a 341 KB EPUB into a
Dart source file to make it browser-reachable was considered and rejected as
a large, permanently ugly artifact for one test.

### The app is compiled with dart2js, and executed under DDC

`flutter build web` runs in CI, and covers the compile class of failure
against the exact artifact production serves, since deployment is a manual
copy of that folder.

`flutter test --platform chrome` also runs in CI now, against 37 of the
`app/test/` suites — every one not marked `@TestOn('vm')`:
`schema_migration_test.dart`, `web_shell_colors_test.dart` and
`android_device_transfer_backup_test.dart` are the exceptions. That count is
not maintained by hand; see Consequences for the `grep -L` marker that builds
the file list, so the number here is a snapshot and drifts with the
annotation. Each one's database construction was swapped from
`NativeDatabase.memory()` to a `testExecutor()` helper (`test_database.dart`,
conditionally exporting a VM file or a web file, with the module load
hoisted into `flutter_test_config.dart`). This covers the runtime class of
failure for app code, in a real browser, for the first time.

It is not dart2js coverage, and the distinction is load-bearing rather than
pedantic. `flutter test --platform chrome` compiles with **DDC**
(`flutter_tools/lib/src/test/web_test_compiler.dart` resolves DDC artifacts
throughout; there is no dart2js path here and no flag for one). DDC and
dart2js agree on the failures that matter most — a 64-bit literal does not
compile under either, `dart:ffi` does not exist under either — and disagree
on narrower edges. JavaScript masks a shift count to five bits, so `1 << 32`
evaluates to `1` under DDC and `0` under dart2js: the exact bug this ADR
exists to catch would still reach dart2js production undetected by a DDC
test. The rule in the next section is therefore unchanged by this addition;
this section only shrinks the *previously unguarded* half of the gap
(nothing ran app code in a browser at all) down to the narrower one dart2js
already implied (DDC is not the shipped compiler).

Two further gaps stay open deliberately. `WasmDatabase.inMemory` is not the
OPFS-and-worker path `driftDatabase()` actually opens on a real deploy — it
proves the app's queries run under WASM sqlite3, not that persistence itself
works. And DDC is not `flutter build web`'s `--wasm`/CanvasKit-and-Skwasm
runtime either; it is a development compiler with its own module loader.
Both are named rather than papered over; `integration_test` with
chromedriver, discussed under Alternatives below, is what would close the
second one.

### Arithmetic whose correctness depends on the compilation target belongs
### in a pure package

This is the substantive rule, and it is the reason the previous section is
an acceptable gap rather than a hole.

`newProfileId` lived on `LibraryRepository`. The one function in the app
carrying an explicit comment about `dart2js` integer semantics was in the
only layer a browser run cannot reach. It is now `ReadingProfile.newId`, in
`rsvp_engine`, beside the `builtInIdPrefix` constant that defines the
namespace it must avoid.

ADR 0001 already argued that logic worth testing without a widget harness
belongs in the pure packages. Target-sensitive arithmetic is a clear
instance: it is pure computation, it needs no Flutter, and the packages are
where the browser run reaches.

Stated as a rule for future work: hashing, bit manipulation, and anything
depending on integer width or precision goes in `rsvp_engine` or
`epub_reader`, not in `app/`.

### Hash output is asserted, not merely computed

Nothing in the repository checked what `Block.makeId` returns.
`front_matter_test.dart` called it only to obtain distinct ids, and the
golden test asserts counts and text. The 64-bit version was caught by the
compiler rather than by a test, which concealed that the function had no
output coverage at all.

An error in the shift decomposition — the `<<`/`+` sequence that stands in
for multiplication by 16777619 — would compile cleanly, produce different
ids, and pass the entire suite, while invalidating every stored reading
position on every device per ADR 0002.

`block_id_test.dart` asserts literal expected values on both platforms.
Literals rather than a recomputed reference, deliberately: a test that
recomputes the hash agrees with a wrong implementation as readily as a right
one.

### The browser run moves off the pull-request path

Amended 2026-08-28. `flutter test --platform chrome` moves from a step on
every pull request to a nightly run on `main` and a gate on the tag, ahead of
deploy. The measured basis: 3m47s of the `app` job's wall time, 61% of that
job's total, and zero failures across the 100 runs since the step was added,
weighed against a compiler — DDC — that production never executes.

### The rest of the CI stack is gated on what changed, too

Amended 2026-08-29. Moving the browser run off the pull-request path leaves
`ci-flutter.yml`'s remaining steps, `ci-java.yml`, `ci-dart.yml` and
`codeql.yml` still running unconditionally, so `dart2js` and DDC are not the
only cost this document has a stake in — a documentation-only or
server-only pull request paid for all of it regardless. The `main` ruleset
requires four contexts (`app`, `server`, `test (rsvp_engine)`,
`test (epub_reader)`), and a required check that is skipped never reports
and blocks the pull request forever, so a native `paths:` filter cannot sit
on any workflow producing one of those four. Two patterns work instead, and
each workflow needed a different one:

- `ci-flutter.yml` (the `app` job): a `changes` gate job using
  `dorny/paths-filter`, with a small `app` job downstream that treats a
  skipped fan-out as success and only failure or cancellation as failure —
  the required context otherwise could never turn green on a
  documentation-only branch.
- `ci-java.yml`: the same gate-and-aggregator shape, but the job the gate
  guards had to be renamed from `server` to `build` and the small aggregator
  takes the `server` name, because the Postgres service container is
  declared at job level and starts as soon as the job is scheduled,
  before any step's `if:` is evaluated — skipping every step would still
  pay for the container. A gate job is what stops it starting at all.
- `ci-dart.yml`: no gate job. Its two required contexts (`test
  (rsvp_engine)`, `test (epub_reader)`) come from a matrix over the package
  list, and a gate job would need a second matrix over the same list to
  produce matching per-package outputs, for no gain over asking the
  question once per matrix job instead. The `test` job keeps its name and
  always runs; every step from checkout onward carries a per-package
  `dorny/paths-filter` condition, scoped to that package's own directory —
  the packages do not depend on the app (ADR 0001), so an app-only change
  should not wake either one.
- `codeql.yml`: a native `paths:` filter on the `pull_request` trigger only.
  Safe here specifically because `analyze` is not one of the four required
  contexts — nothing gates on it, so a skipped run costs nothing. `push` to
  `main` and the weekly schedule stay unfiltered, so the security baseline
  still runs against everything that lands rather than only what a filtered
  pull request happened to touch.

Every job across all six workflow files now carries an explicit
`timeout-minutes`. Before this layer, only the jobs #226 introduced or
touched carried one — `ci-flutter.yml`'s five jobs, `cd.yml`'s
`browser-test` and `deploy`, and `flutter-nightly.yml`'s `browser` job.
`ci-java.yml`'s `server` job, `ci-dart.yml`'s `test` job, `codeql.yml`'s
`analyze` job, and `cd.yml`'s `server-image` and `web-image` jobs still
inherited GitHub's 360-minute default; this layer bounds all five.

## Consequences

CI gains roughly a minute on the Dart workflow, and the Flutter workflow
gains both `flutter test --platform chrome` and the existing `flutter build
web` — see Verification for the wall-clock cost. Both are cheap against the
manual web testing that found the first two bugs.

The browser run is the most expensive step in the workflow: 2m50s on CI
against the VM run's 46s, for very nearly the same assertions. Most of that
is per-suite overhead — each of the 37 suites boots a browser, initialises
the engine and fetches the sqlite3 module — not test time. The
step carries `--timeout 60s` and `timeout-minutes: 15` so that a suite which
stops making progress fails fast and prints what it got through, rather than
holding a runner at the ten-minute per-test default until someone cancels
it.

All three additions are steps inside existing jobs rather than new jobs, so
the required status checks in the repository ruleset — `test (rsvp_engine)`,
`test (epub_reader)`, `app` — are unchanged.

The golden test no longer runs on every platform the package supports. The
parsing behaviour it covers is target-independent, and `block_id_test.dart`
carries the part that is not.

App code can still contain a runtime `dart2js` bug and reach production. The
rule stated above shrinks the surface rather than closing it, since UI code
genuinely cannot move into a pure package, and DDC coverage of the app is not
a substitute for that rule, only a second net under it. Real dart2js
coverage of app code means `integration_test` with chromedriver, which is a
heavier commitment in setup and flakiness than this project can justify
before its deadline. Filed as a follow-on issue rather than pretended away.

`app/test/schema_migration_test.dart`, `web_shell_colors_test.dart` and
`android_device_transfer_backup_test.dart` stay `@TestOn('vm')`, but that
annotation only stops them *running* on Chrome — it does not stop them
being *compiled* for it. `flutter test --platform chrome` generates one
shared entrypoint that imports every discovered test file's `main` before
any `@TestOn` filtering happens (`generateTestEntrypoint` in
`flutter_tools/lib/src/web/bootstrap.dart`), so any file's own `dart:ffi`
or `dart:io` import breaks the whole run even though none of the three
ever executes on this platform. All three files are therefore also kept
out of the file list `ci-flutter.yml` passes to the Chrome step. That list
is built by `grep -L "@TestOn('vm')" test/*_test.dart` rather than by
naming the files, so the annotation is the single marker and the next
VM-only suite is excluded without anyone remembering the step exists. This
is a real difference from `dart test -p chrome`'s handling of
`epub_golden_test.dart` above, which does exclude at compile time — the two
test runners are not the same tool and this ADR's "cannot work" era
conflated them.

`schema_migration_test.dart` did not in fact carry the annotation when the
sentence above was first written; it was excluded by name only, and this
document asserted a state of the repository that was not true. The
annotation is now on the file, with its own reason — it opens real database
files through `NativeDatabase` — which makes it correct on its own merits
as well as load-bearing for the `grep`.

A future contributor — including this one, later — will try `flutter test
--platform chrome` bare, without the file-list exclusion, because it is the
obvious thing to reach for. The compile-bundling reason it fails is recorded
here and in a comment on the workflow itself.

**Consequence of the move: per-pull-request attribution.** A failure on the
nightly run names a day's merges to `main`, not a commit; the usual
this-PR-broke-it signal is gone for the runtime class of failure this step
catches, in exchange for removing 61% of the `app` job's wall time from the
path every pull request waits on. Stated rather than papered over.

## Alternatives considered

**`flutter test --platform chrome` for the app, rejected as a rewrite.**
This was the original call in this document, on the premise that every
database test would need moving onto drift's WASM setup. The premise was
wrong, and so was the first correction of it — which is worth recording in
full, because this is the second time a rejection in this repository turned
out to rest on a reasoning error rather than on a constraint (ADR 0015's
contrast guard was the first, un-rejected by a test that found the unguarded
fill at 1.92).

The original rejection was wrong because `WasmDatabase.inMemory` is a
drop-in `QueryExecutor`: the fix is a helper (`test_database.dart` and its
two conditional halves) and a mechanical swap at each of the 29
`AppDatabase(NativeDatabase.memory())` call sites across 24 files, not a
parallel test suite.

The first correction then said that helper wrapped the executor in a
`LazyDatabase` for the async load, and that this was what let every call
site keep its shape. The call sites do keep their shape, but not that way.
`LazyDatabase` defers the module load to the first query, which happens
inside a test body, inside `FakeAsync` — so it does not solve the async load
so much as move it to the one zone where it can never complete. It hangs
until the runner's wall-clock timeout: two ten-minute timeouts in one CI job
before it was cancelled at 25 minutes, with no pass/fail list to show for
it. What actually makes the swap work is a suite-level warm-up in
`flutter_test_config.dart`, after which `testExecutor()` is synchronous on
both targets. Dropping `LazyDatabase` is not cosmetic: a synchronous
executor throws immediately and names the reason if the warm-up is ever
skipped, where a lazy one goes back to hanging.

The corrected rejection therefore turns on the `FakeAsync` constraint, not
on the rewrite the original claimed. The result is still not the production
pipeline — DDC is not dart2js, and `WasmDatabase.inMemory` is not the
OPFS-and-worker path a real deploy opens — which is exactly why the rule
under Decision survives this amendment rather than being replaced by it.

**A second tracked copy of `sqlite3.wasm` under `app/test/`.** Rejected: two
paths writing one fact. A stale test copy would test a different SQLite
build than the one `app/web/sqlite3.wasm` actually ships, and 732 KB
duplicated by hand for no reason a tool can enforce is the kind of thing
that drifts silently. The copy is made at test time instead, from the one
tracked file, and gitignored.

**A percent-encoded `..` in the fetch URL, reaching `web/sqlite3.wasm`
through the `<cwd>/test` static handler without a copy at all.** Rejected as
a path-traversal trick nobody reading this test helper should have to
recognise as intentional, for a problem a one-line `cp` in CI solves without
cleverness.

**A single `dart test -p vm,chrome` invocation instead of two steps.**
Rejected for signal, not correctness. Separate steps make the failing
platform visible in the checks list without opening a log.

**A browser dimension in the workflow matrix.** Rejected: it would rename
the job contexts and require editing the branch protection ruleset for no
gain over a second step.

**Base64 the EPUB fixture so the golden test runs on Chrome.** Rejected as
disproportionate; see above.

**Doing nothing and relying on manual web testing before each deploy.**
Rejected. It is what has been happening, and it caught both bugs — after
they had already been committed and, in one case, deployed. The check
belongs before merge, not before deploy.

**Revisited 2026-08-28.** That rejection was written against *manual*
pre-deploy testing, which had already let two bugs reach production before
this ADR existed. An automated gate on the tag is a different mechanism, and
under this project's tag-triggered deploy a merge to `main` is not a
release — the two are no longer the same event the original rejection
assumed. This is the third time a rejection in this repository has turned
out to rest on a reasoning error rather than a constraint, after ADR 0015's
contrast guard and this document's own `LazyDatabase` correction above,
which is why rejected options are recorded here at all rather than dropped
once overturned.

## Verification

`dart test -p chrome` passes in both packages, with the golden test
reported as skipped. `flutter build web` passes. Reverting
`ReadingProfile.newId` to `nextInt(1 << 32)` locally fails
`profile_id_test.dart` under Chrome and passes on the VM, which is the
behaviour this whole document is about.

**For the app's addition, from the runs that actually happened rather than
the ones expected:**

`flutter test` (VM) passes, 1061 tests, unchanged in count from before this
amendment. `flutter analyze` and `dart format --output=none
--set-exit-if-changed .` are both clean.

**The browser run passes in full: 1053 tests across 31 suites**, with no
suite needing an exclusion beyond the two already marked `@TestOn('vm')`.
4m56s locally, 2m50s on CI — the runner is faster than this machine, so the
`timeout-minutes: 15` sized from the local number carries more headroom in
the place it actually applies. The arithmetic against the VM run is
exact — 1061 minus the 7 tests in `schema_migration_test.dart` and the 1 in
`web_shell_colors_test.dart` is 1053 — so the browser covers every assertion
the VM does except those two suites.

Three suspects were expected to need attention and did not.
`token_run_measure_test.dart` measures glyph runs, `reader_semantics_test.dart`
reads the semantics tree, and both pass unchanged; the web target gets the
same 800×600 logical surface (`_test_selector_web.dart:47-50` sets 2400×1800
at DPR 3.0, matching `flutter_test/lib/src/binding.dart:99`) and the same
test font (`ui_web.TestEnvironment.flutterTester()` sets `forceTestFonts`
and `disableFontFallbacks`), so layout-sensitive assertions behave
identically. `library_filter_test.dart`'s `compute()` path passes too, since
`compute` runs inline on web.

An earlier attempt at this run did *not* pass, and what it cost is the
reason the executor is shaped the way it is. With the module load behind a
`LazyDatabase`, pure `test()` suites passed in the first 45 seconds and the
first `testWidgets` suite produced two consecutive `TimeoutException after
0:10:00`, the job being cancelled at 25 minutes having reported nothing
about the other 28 suites. No matcher failed anywhere in that log — the
failure was entirely the `FakeAsync` constraint described under Context, and
nothing about layout, fonts or assertions was implicated. Both `--timeout
60s` and `timeout-minutes: 15` exist so that a regression of that shape
costs a minute and prints a list.

The negative control passes on both halves. Reverting `active_profile_test.dart`
to `AppDatabase(NativeDatabase.memory())` with its `drift/native.dart`
import restored makes `flutter test --platform chrome test/active_profile_test.dart`
fail in well under a minute with `Dart library 'dart:ffi' is not available on
this platform` — confirming the file-list exclusion is load-bearing and not
cosmetic — while `flutter test` on the same reverted file still passes on the
VM. Restoring the file leaves an empty diff.

**One local-only obstacle, unrelated to any code in this repository**, sat in
front of all of the above and is worth recording so the discovery costs a
search rather than a repeat of the investigation. On Windows the run
compiles, launches Chrome and then hangs at zero CPU with no output.
Connecting to the browser directly over the Chrome DevTools Protocol
(`Runtime.enable` / `Log.enable` on the page target) rather than trusting
flutter_tools' own output surfaced it: the engine bootstrap fetches
`canvaskit/chromium/canvaskit.js` from the test server, gets a `404`, throws
an uncaught `TypeError`, and nothing downstream of engine initialization
proceeds. The file exists at `<flutter_web_sdk>/canvaskit/chromium/canvaskit.js`
and `flutter_web_platform.dart` has a handler for exactly that path
(`_localCanvasKitHandler`, `:518`), but its guard compares
`_fileSystem.path.fromUri(request.url)` — resolved through the local OS path
context — against the literal `'canvaskit/'`, which a backslash path never
matches. It is Windows-specific: CI runs on `ubuntu-latest`, where the path
context is posix and the comparison matches. The cascade's next handler
serves `<cwd>/test` and builds its path correctly, so copying the SDK's
`canvaskit` directory to `app/test/canvaskit/` serves what the broken
handler should have. That copy is gitignored and documented in
`app/README.md`'s Testing section as a development-environment step, not
here — it is a workaround, not a reason for the decision.

**The CI-gating stack (#225–#227), before-and-after.** The baseline, measured
across five runs on 2026-08-27 before any of the three layers landed (#224):
`app` (`ci-flutter.yml`) 6m47s, `codeql` 1m33s (not required),
`server` (`ci-java.yml`) 1m05s, `test (rsvp_engine)` 1m03s,
`test (epub_reader)` 0m59s. No workflow had a `paths:` filter of any kind, so
a documentation-only pull request paid the full total.

The gate-and-aggregator shape landed first in `ci-flutter.yml` (#226). On the
push that merged it — d768dc2, which touches `app/` so the fan-out ran in
full — the real, observed job durations were: `changes` 4s, `format-analyze`
47s, `test` 1m28s, `web-build` 1m10s, `app` (the aggregator) 3s
(`gh run view 33235508565 --json jobs`). The gate and aggregator overhead
together is single-digit seconds against a job that used to run 6m47s
serially; the 3m47s browser step is no longer in this workflow at all,
having moved to `flutter-nightly.yml` and `cd.yml` under #225.

`ci-java.yml`, `ci-dart.yml` and `codeql.yml`'s skip paths, measured against
three throwaway pull requests (#239–#241, closed unmerged once the runs
completed) rather than against #227's own diff — that diff touches all four
workflow files at once and so exercises every job in full, telling nothing
about a branch that only touches one area. All three figures are wall clock
from the first job's start to the last of the four required contexts
(`app`, `server`, `test (rsvp_engine)`, `test (epub_reader)`) finishing:

A documentation-only branch (#239, `runs/33236715130`, `.../33236715142`,
`.../33236715170`) — every job in `ci-flutter.yml` past its `changes` gate
and the `build` step in `ci-java.yml` skip, leaving only the two gate jobs
and the two dart package suites: **14s**.

A server-only branch (#240, `runs/33236731399`, `.../33236731409`,
`.../33236731396`) — `ci-flutter.yml`'s `format-analyze`/`test`/`web-build`
skip, `ci-java.yml` runs its `build` step (1m10s) in full: **1m23s**.

A packages-only branch (#241, `runs/33236743363`, `.../33236743368`,
`.../33236743374`) — `packages/rsvp_engine` and `packages/epub_reader` reach
`app` through ADR 0001's path dependencies with no publish and no version
bump, so `ci-flutter.yml`'s filter (`ci-flutter.yml:45-48`) treats this the
same as an app-only change and runs `format-analyze`/`test`/`web-build` in
full while `ci-java.yml`'s `build` step skips: **1m35s**.
