package lt.hereader.server.sync;

import tools.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.ProblemDetail;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/// Rejects an oversized push before Jackson materialises the body.
///
/// Tomcat has no property that bounds a raw request body: `maxPostSize`
/// (`server.tomcat.max-http-form-post-size`) only limits bytes parsed into
/// request *parameters* — `application/x-www-form-urlencoded` and
/// `multipart/form-data` — never a body a controller reads via
/// `@RequestBody`, which is how `SyncController.push` receives this one.
/// Verified against Tomcat's own connector documentation rather than
/// assumed, since the obviously-named property turns out not to apply here.
///
/// Only checks `Content-Length`, so a request that omits it — chunked
/// transfer-encoding — passes through unbounded. Real HTTP clients,
/// including this project's own app, always declare it for a
/// non-streamed POST, so this catches the ordinary case cheaply, before a
/// hostile array is even parsed. The backstop for a client that omits it on
/// purpose is `server/Caddyfile`'s `request_body` directive, which limits
/// bytes as they stream in regardless of what the client claims —
/// `app:8080` is bound to `127.0.0.1` only (`server/compose.yaml`), so
/// Caddy is the only path in from the internet. Keep the two numbers equal;
/// the derivation is written out once, here.
@Component
public class SyncRequestSizeFilter extends OncePerRequestFilter {

    /// 500 events (`SyncDtos.PushRequest`'s `@Size` cap) at up to 8,192
    /// encoded JSON characters of payload each (`SyncService.MAX_PAYLOAD_CHARS`),
    /// plus each event's other capped fields, is on the order of 4.3M
    /// characters for a legitimate maximal batch. Multi-byte UTF-8 can expand
    /// a character to several bytes on the wire, so this is sized at roughly
    /// 4x that character count rather than treating a character and a byte
    /// as the same thing.
    static final long MAX_PUSH_REQUEST_BYTES = 16L * 1024 * 1024;

    private final ObjectMapper json;

    SyncRequestSizeFilter(ObjectMapper json) {
        this.json = json;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {

        // Not getServletPath(): MockMvc's webAppContextSetup, used by
        // SyncControllerIntegrationTest, never populates it — it stays "" —
        // while the real embedded server does. requestURI minus contextPath
        // gives the same answer in both, and is what getServletPath() is
        // supposed to be under a real deployment anyway.
        var path = request.getRequestURI().substring(request.getContextPath().length());

        if (!"POST".equals(request.getMethod()) || !path.equals("/sync/events")) {
            chain.doFilter(request, response);
            return;
        }

        if (request.getContentLengthLong() > MAX_PUSH_REQUEST_BYTES) {
            response.setStatus(413);
            response.setContentType("application/problem+json");
            var problem = ProblemDetail.forStatus(413);
            problem.setDetail("Request body is too large.");
            json.writeValue(response.getWriter(), problem);
            return;
        }

        chain.doFilter(request, response);
    }
}
