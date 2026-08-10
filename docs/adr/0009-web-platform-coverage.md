# 0009. Web coverage is a build for the app and a browser test run for the packages

Date: 2026-08-10

## Status

Accepted.

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

A third fact constrains the answer. `app/test/` builds its database through
`package:drift/native.dart`, which reaches `dart:ffi`. That does not compile
to JavaScript under any configuration. `flutter test --platform chrome` is
therefore not a setting to get right but a rewrite of every database test
onto drift's WASM setup, maintained in parallel with the native one.

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

### The app is compiled, not executed

`flutter build web` runs in CI. It covers the compile class of failure
against the exact artifact production serves, since deployment is a manual
copy of that folder.

It does not cover the runtime class for app code. That limit is accepted
rather than worked around, and the next decision is what keeps it small.

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

## Consequences

CI gains roughly a minute on the Dart workflow and two to four on the
Flutter workflow. Both are cheap against the manual web testing that found
the last two bugs.

Both additions are steps inside existing jobs rather than new jobs, so the
required status checks in the repository ruleset — `test (rsvp_engine)`,
`test (epub_reader)`, `app` — are unchanged.

The golden test no longer runs on every platform the package supports. The
parsing behaviour it covers is target-independent, and `block_id_test.dart`
carries the part that is not.

App code can still contain a runtime `dart2js` bug and reach production. The
rule above shrinks the surface rather than closing it, since UI code
genuinely cannot move into a pure package. Real coverage there means
`integration_test` with chromedriver, which is a heavier commitment in setup
and flakiness than this project can justify before its deadline. Listed on
the roadmap rather than pretended away.

A future contributor — including this one, later — will try `flutter test
--platform chrome`, because it is the obvious thing to reach for. The
`dart:ffi` reason it cannot work is recorded here and in a comment on the
workflow itself, so the discovery costs a search rather than an evening.

## Alternatives considered

**`flutter test --platform chrome` for the app.** Rejected: impossible
without rewriting every database test onto drift's WASM setup, and the
result would still not be the production pipeline. The browser test harness
and `flutter build web` are different toolchains.

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

## Verification

`dart test -p chrome` passes in both packages, with the golden test
reported as skipped. `flutter build web` passes. Reverting
`ReadingProfile.newId` to `nextInt(1 << 32)` locally fails
`profile_id_test.dart` under Chrome and passes on the VM, which is the
behaviour this whole document is about.
