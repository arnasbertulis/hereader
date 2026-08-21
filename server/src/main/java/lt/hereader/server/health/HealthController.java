package lt.hereader.server.health;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
class HealthController {

    private final JdbcClient jdbc;

    HealthController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /// Reports database reachability. Deliberately answers with nothing about
    /// the data itself — `select 1` costs no sequential scan on the hottest
    /// table this endpoint is polled against, and an unauthenticated caller
    /// has no reason to learn how many accounts exist.
    @GetMapping("/health")
    Map<String, Object> health() {
        jdbc.sql("select 1").query(Integer.class).single();

        return Map.of("status", "ok");
    }
}