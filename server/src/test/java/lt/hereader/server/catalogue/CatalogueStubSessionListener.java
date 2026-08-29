package lt.hereader.server.catalogue;

import org.junit.platform.launcher.LauncherSession;
import org.junit.platform.launcher.LauncherSessionListener;

/// Starts the catalogue stub before JUnit executes anything, registered
/// through `META-INF/services` so the platform finds it without any test
/// class naming it.
///
/// The stub publishes its port as system properties, and a system property
/// is only read once — when Spring builds the `Environment` for a context.
/// Since #231 there is exactly one context for the whole suite, built by the
/// first class to run, so "before any test" is the only moment that works.
/// A static initializer on the base class is too late: Surefire runs
/// AuthControllerIntegrationTest first and it never loads that class, so the
/// context bound `application.properties`' real gutenberg.org URLs instead.
///
/// A launcher session listener rather than an `@BeforeAll` or a Spring
/// callback because those all run inside a test class's own lifecycle, which
/// is after the context exists — and because anything the test classes
/// declare themselves would re-enter the context cache key this issue exists
/// to keep uniform.
public class CatalogueStubSessionListener implements LauncherSessionListener {

    @Override
    public void launcherSessionOpened(LauncherSession session) {
        CatalogueStubServerTest.ensureStarted();
    }
}
