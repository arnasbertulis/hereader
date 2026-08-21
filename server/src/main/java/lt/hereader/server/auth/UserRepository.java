package lt.hereader.server.auth;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public class UserRepository {

    public record User(UUID id, String email, String passwordHash, long tokenVersion) {}

    private final JdbcClient jdbc;

    UserRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public Optional<User> findByEmail(String email) {
        return jdbc.sql("""
                select id, email, password_hash, token_version
                from users
                where email = :email
                """)
                .param("email", email)
                .query(User.class)
                .optional();
    }

    public Optional<User> findById(UUID id) {
        return jdbc.sql("""
                select id, email, password_hash, token_version
                from users
                where id = :id
                """)
                .param("id", id)
                .query(User.class)
                .optional();
    }

    /// Invalidates every refresh token already issued for this user: the
    /// next `/auth/refresh` compares its claim against this new value and
    /// no longer matches.
    public void bumpTokenVersion(UUID id) {
        jdbc.sql("update users set token_version = token_version + 1 where id = :id")
                .param("id", id)
                .update();
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

        return new User(id, email, passwordHash, 0);
    }
}