package lt.hereader.server.auth;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public class UserRepository {

    public record User(UUID id, String email, String passwordHash) {}

    private final JdbcClient jdbc;

    UserRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<User> findByEmail(String email) {
        return jdbc.sql("""
                select id, email, password_hash
                from users
                where email = :email
                """)
                .param("email", email)
                .query(User.class)
                .optional();
    }

    public boolean exists(UUID id) {
        return jdbc.sql("select exists(select 1 from users where id = :id)")
                .param("id", id)
                .query(Boolean.class)
                .single();
    }

    /// Creates the user and their sync state together. A user without a
    /// sync_state row would fail on their first push, so the two are never
    /// separate.
    public User create(UUID id, String email, String passwordHash) {
        jdbc.sql("""
                insert into users (id, email, password_hash)
                values (:id, :email, :hash)
                """)
                .param("id", id)
                .param("email", email)
                .param("hash", passwordHash)
                .update();

        jdbc.sql("insert into user_sync_state (user_id) values (:id)")
                .param("id", id)
                .update();

        return new User(id, email, passwordHash);
    }
}