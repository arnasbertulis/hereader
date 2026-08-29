package lt.hereader.server.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import static org.mockito.Mockito.spy;

/// The test profile's own PasswordEncoder, wrapped as a Mockito spy so
/// AuthControllerIntegrationTest can verify encoder calls without declaring
/// a @MockitoSpyBean override — a bean override is part of Spring's test
/// context cache key, and was the one thing keeping that class from sharing
/// a context with the other plain @SpringBootTest classes (#231).
///
/// SecurityConfig.passwordEncoder() is @Profile("!test") for exactly this
/// bean to replace it, rather than override it, under the test profile.
@Configuration
@Profile("test")
class TestPasswordEncoderConfig {

    @Bean
    PasswordEncoder passwordEncoder() {
        return spy(new BCryptPasswordEncoder());
    }
}
