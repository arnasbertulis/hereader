# 0030. Shared Spring test contexts for the integration suite

## Status

Accepted.

## Context

#228 asked whether the server suite's ten `@SpringBootTest` classes — each
provably unable to share a Spring `ApplicationContext` with any other — cost
enough to justify rewriting them so they can. #229 measured that, on one
machine, in one sitting, using Spring's own context-cache statistics rather
than inferring anything from the annotations
(`org.springframework.test.context.cache` at `DEBUG`,
`./mvnw test -DargLine="-Dlogging.level.org.springframework.test.context.cache=DEBUG"`).
Full numbers are in the comment on #228; the ones the decision below turns on:

- The cache's own final line for a full `test`-phase run:
  `size = 10, maxSize = 32, hitCount = 1358, missCount = 10, failureCount = 0`.
  Ten classes, ten misses, zero cross-class hits — the cache never even
  approached its 32-entry ceiling, so nothing here is an accidental cache-key
  mismatch waiting to be tidied up.
- The ten `Started <Class> in X seconds` lines Spring Boot logs for each
  context sum to 10.233s. The first (`AuthControllerIntegrationTest`, 5.191s)
  is inflated by JVM class-loading/JIT warm-up; the other nine average 0.560s.
  Against a same-run sum of the thirteen classes' own `Time elapsed` figures
  (23.798s, `target/surefire-reports/*.txt`), context startup is **~43%** of
  total test execution — the single largest cost category.
- Two classes are the suspected fixture problems, sized rather than assumed:
  `CatalogueControllerIntegrationTest` re-reads the CSV fixture in
  `@BeforeEach` for all 37 of its `@Test` methods
  (`server/src/test/java/lt/hereader/server/catalogue/CatalogueControllerIntegrationTest.java:71-78`),
  and `CataloguePopularityIngestionIntegrationTest` rebuilds a `tar.bz2`
  archive with `org.apache.commons.compress` in `@BeforeEach` for all 10 of
  its methods
  (`.../catalogue/CataloguePopularityIngestionIntegrationTest.java:67-75`).
  Their combined non-context time (`Time elapsed` minus that class's own
  context startup) is 5.482s — **~23%** of the 23.798s total, and that figure
  is an upper bound on the fixture cost specifically, since it also contains
  those two classes' real assertions; #229 added no instrumentation to split
  the two further, matching its "no test behaviour changes" scope.
- Contexts (43%) cost more than the two fixture suspects combined (≤23%) and
  more than the remaining eleven classes' actual assertion time. That is the
  basis for the go decision below.

Two structural facts limit how far sharing can go:

- Five classes set `webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT`
  (`AuthRateLimitFilterTest`, `CatalogueCategoriesRateLimitFilterTest`,
  `CatalogueLanguagesRateLimitFilterTest`, `CatalogueProxyRateLimitFilterTest`,
  `CatalogueSearchRateLimitFilterTest`) because `MockMvc`'s
  `webAppContextSetup` never invokes the servlet container's own
  `ForwardedHeaderFilter`, and `X-Forwarded-For` translation only happens
  there — ADR 0026's *Verification* section already establishes this for
  `AuthRateLimitFilterTest`. Those five can never join the same context pool
  as the other five, which stay on the default `MOCK` environment.
- Within that `RANDOM_PORT` group, each class sets a *different* single
  property to 2 via `@SpringBootTest(properties = ...)` — e.g.
  `AuthRateLimitFilterTest` overrides
  `hereader.auth-rate-limit.requests-per-minute`, `CatalogueCategoriesRateLimitFilterTest`
  overrides two different keys again. Spring's context cache key includes the
  exact `properties` array, so as written these five cannot share a context
  with each other either — consistent with the measured `missCount = 10`
  rather than some lower number.
- Two of the five `MOCK`-environment classes
  (`CatalogueControllerIntegrationTest`, `CataloguePopularityIngestionIntegrationTest`)
  each start their own static `HttpServer stub` and register its dynamic port
  via `@DynamicPropertySource`
  (`.../CatalogueControllerIntegrationTest.java:57-62`,
  `.../CataloguePopularityIngestionIntegrationTest.java:52-58`). The measured
  `missCount = 10` confirms these two do not share a context either, most
  likely because each class supplies its own `@DynamicPropertySource` method
  rather than one inherited from a common base.

## Decision

Contexts dominate; the remaining layers of #228 proceed. Target: two shared
context pools instead of ten independent ones — one for the five
`MOCK`-environment classes, one for the five `RANDOM_PORT` rate-limit classes
— which requires closing the two blockers above:

1. **Move the `RANDOM_PORT` classes' rate-limit budget from a
   `@SpringBootTest(properties = ...)` override to a runtime-mutable value.**
   `SecurityConfig.rateLimitBudgets`
   (`server/src/main/java/lt/hereader/server/config/SecurityConfig.java:33-73`)
   binds each `@Value("${hereader.*-rate-limit.requests-per-minute:N}")` once,
   at context startup, into an immutable `RateLimitFilter.PathBudget` record
   (`RateLimitFilter.java:40`). A test-visible mutable holder — read by
   `RateLimitFilter` per request instead of baked in once at construction —
   would let every rate-limit test class share one context and dial its own
   budget down to 2 for just its own test methods, restoring the default
   afterward. `RateLimitFilter`'s per-IP state
   (`TrackedBudget.byIp`, a `ConcurrentHashMap<String, Window>`,
   `RateLimitFilter.java:44,57`) has no reset hook today; sharing the filter
   bean across classes needs an explicit test-only clear between them, since
   the 5-minute evictor cannot guarantee two rate-limit classes exhausting the
   same IP inside the same wall-clock minute stay isolated.
2. **Move the two `@DynamicPropertySource` classes' stub-server registration
   to a shared base class**, so both inherit the same registrar and one
   running stub exposing the union of routes (`/pg_catalog.csv` and
   `/rdf-files.tar.bz2`) instead of one server each.

## Alternatives considered

- **Add `@DirtiesContext` to the classes that seem riskiest to share, and
  trust the rest are already caching.** Rejected — #229's own measurement
  shows the cache already makes zero cross-class hits
  (`missCount = 10` for ten classes); there is no accidental sharing here to
  protect, and `@DirtiesContext` only empties an already-empty cache.
- **Share the five `RANDOM_PORT` contexts as they are, without touching
  `RateLimitFilter` or `SecurityConfig`.** Rejected — the `properties`
  overrides differ per class by design, each isolating a different budget;
  dropping the override in favour of one shared low limit would make every
  non-rate-limit assertion in those five classes flake under the same tiny
  budget.
- **Give every `RANDOM_PORT` class the same overridden properties and reset
  state with `@DirtiesContext(classMode = BEFORE_CLASS)` between them, instead
  of a mutable bean.** Rejected — `@DirtiesContext` closes and rebuilds the
  context, which is exactly the boot cost this decision exists to remove; it
  keeps the shared cache *slot* while paying the shared *startup cost* every
  time regardless.
- **Merge the `MOCK` and `RANDOM_PORT` groups into one pool by moving all five
  rate-limit classes onto `MockMvc`.** Rejected on ADR 0026's own reasoning:
  `X-Forwarded-For` translation happens in the servlet container's
  `ForwardedHeaderFilter`, which `MockMvc`'s `webAppContextSetup` never
  invokes.
- **Leave the two `@DynamicPropertySource` classes on separate stub servers
  and accept two contexts there.** Not rejected outright — kept as a fallback
  if merging the stub servers complicates
  `CataloguePopularityIngestionIntegrationTest`'s truncated/corrupt-archive
  cases. Left for the implementing issue to decide once it is in the code.

## Consequences

- Best case, ten contexts become two — one `MOCK` pool of five classes, one
  `RANDOM_PORT` pool of five — each built once instead of once per class.
- `RateLimitFilter` and `SecurityConfig.rateLimitBudgets` gain a test-only
  mutation seam (a production code change), and the two ingestion classes'
  stub servers merge into one shared fixture (a test-only change). Both are
  out of scope for #229 itself and land as follow-up issues under #228.
- **Amendment (#230):** blocker 1's mutation seam turned out unnecessary for
  the `RANDOM_PORT` pool. It was written to let five *separate* classes each
  dial their own budget mid-test; #230 merged the five into one class instead,
  with all six budget properties set together in one static
  `@SpringBootTest(properties = ...)` array. With no class left needing a
  value another didn't share, the cache key stops forking without a
  runtime-mutable seam. `RateLimitFilter`'s per-IP state still has no reset
  hook, and the merged class avoids needing one the same way the original
  five did — distinct synthetic `X-Forwarded-For` octets per test. Blocker 1
  remains relevant only if a future `RANDOM_PORT` class needs a budget value
  the merged class doesn't already set.
- The two fixture problems #229 sized (per-test CSV re-read, per-test archive
  rebuild) are independent of context sharing and can be fixed on their own
  — moving the rebuild to `@BeforeAll` — for a smaller, safer win regardless
  of whether the context work proceeds.

## Verification

Built. Re-measured the way #229 measured it —
`./mvnw test -DargLine="-Dlogging.level.org.springframework.test.context.cache=DEBUG"`,
reading `size` and `missCount` off the cache's own final line and `Time
elapsed` out of `target/surefire-reports/*.txt` — on one machine, in one
sitting, with the before and after runs in the same working tree so the JVM
and Postgres are in comparable states.

**Contexts.** #229's line was
`size = 10, maxSize = 32, hitCount = 1358, missCount = 10, failureCount = 0`.
With #230, #231 and #232 merged it reads
`size = 2, maxSize = 32, contextUsageCount = 1, parentContextCount = 0,
hitCount = 1383, missCount = 2, failureCount = 0`. Ten context builds became
two, which is the number the *Decision* above set as the target.

**Fixtures (#232).** The two classes #229 sized, and the whole `test` phase,
two runs each on the commit before #232 and on #232 itself:

| `Time elapsed`, seconds | before | after |
|---|---|---|
| `CatalogueControllerIntegrationTest` | 3.348, 3.433 | 1.653, 1.593 |
| `CataloguePopularityIngestionIntegrationTest` | 1.100, 1.076 | 0.323, 0.338 |
| whole `test` phase | 14.566, 14.691 | 12.263, 12.092 |

The two classes together fell from ~4.48s to ~1.95s, and the suite from
~14.63s to ~12.18s — the ~2.5s the two classes gave up is the whole of the
suite's drop, within run-to-run noise, which is what should happen when
nothing else changed.

**Against #229's forecast.** #229 did not forecast a saving; it bounded one.
Its figure was the two classes' combined non-context time, 5.482s, stated as
an *upper* bound on the fixture cost because it also contains those classes'
real assertions and the ingestions that are the subject of a test rather than
setup for one. The realised saving, 2.53s, is 46% of that bound, and the
remainder is accounted for: twelve of the thirty-seven controller tests stayed
outside the shared group, ten of them because they ingest or refresh as part
of what they assert, and all ten popularity tests still run a popularity
refresh, which is their subject. So the bound held and was not tight — the
useful correction for next time is that "non-context time in a class with a
suspicious `@BeforeEach`" is roughly half fixture and half work, not mostly
fixture.

One thing that did not move: the suite's largest single line item is still
`AuthControllerIntegrationTest` at ~5.5s, because it runs first and pays for
building the one shared context plus JVM warm-up. That cost is now paid once
for the whole suite rather than ten times, which is the point of this ADR,
but it means the floor under the suite is a context build, not a test.
