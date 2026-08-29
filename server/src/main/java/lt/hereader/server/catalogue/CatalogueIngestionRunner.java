package lt.hereader.server.catalogue;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

/// The manual trigger: `docker exec hereader-server java -jar app.jar
/// --spring.profiles.active=catalogue-ingest`, the same idiom as the nightly
/// database backup's `docker exec hereader-db-backup /opt/backup/backup.sh`
/// (ADR 0029). Not an HTTP endpoint — the service has no roles, so an
/// endpoint would let any authenticated caller start a 185MB re-ingest on a
/// small machine.
///
/// A second, short-lived JVM in the same container, not a call into the one
/// already serving traffic — `application-catalogue-ingest.properties` binds
/// its embedded web server to an OS-assigned port rather than 8080, so it
/// cannot collide with the instance already holding that one. Exits
/// explicitly once run() returns rather than relying on every remaining
/// thread being a daemon one, since embedded Tomcat's own threads are not.
///
/// The refresh policy itself lives in `CatalogueRefresh`, shared with
/// `CatalogueIngestionScheduler`'s weekly cron; this class adds only the exit
/// code the shell command that invoked this JVM needs.
@Component
@Profile("catalogue-ingest")
class CatalogueIngestionRunner implements ApplicationRunner {

    private static final Logger log =
            LoggerFactory.getLogger(CatalogueIngestionRunner.class);

    private final CatalogueRefresh refresh;
    private final ConfigurableApplicationContext context;

    CatalogueIngestionRunner(CatalogueRefresh refresh, ConfigurableApplicationContext context) {
        this.refresh = refresh;
        this.context = context;
    }

    @Override
    public void run(ApplicationArguments args) {
        log.info("Running catalogue ingestion by hand.");
        var outcome = refresh.runAll();
        final var code = outcome.succeeded() ? 0 : 1;
        System.exit(SpringApplication.exit(context, () -> code));
    }
}
