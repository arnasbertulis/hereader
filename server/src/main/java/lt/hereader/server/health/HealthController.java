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

    @GetMapping("/health")
    Map<String, Object> health() {
        var users = jdbc.sql("select count(*) from users")
                .query(Long.class)
                .single();

        return Map.of("status", "ok", "users", users);
    }
}