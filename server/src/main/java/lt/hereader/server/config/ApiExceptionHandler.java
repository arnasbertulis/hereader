package lt.hereader.server.config;

import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

/// Turns thrown status exceptions into a response body before Spring
/// Security's exception translation can rewrite them.
///
/// Without this, a 409 from an endpoint that permits anonymous access
/// reaches the client as a 403, and the app cannot tell "that email is
/// taken" apart from "you are not allowed here".
@RestControllerAdvice
class ApiExceptionHandler {

    @ExceptionHandler(ResponseStatusException.class)
    ProblemDetail handle(ResponseStatusException e) {
        var problem = ProblemDetail.forStatus(e.getStatusCode());
        problem.setDetail(e.getReason());
        return problem;
    }
}