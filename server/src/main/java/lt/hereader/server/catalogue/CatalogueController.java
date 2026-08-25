package lt.hereader.server.catalogue;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/// Public — browsing free public-domain books does not need an account
/// (ADR 0029). Permitted through SecurityConfig and rate limited on its own
/// path budget, independent of every other budget.
@RestController
@RequestMapping("/catalogue")
class CatalogueController {

    private final CatalogueService service;

    CatalogueController(CatalogueService service) {
        this.service = service;
    }

    /// Matches [q] against title or authors. A blank or absent [q] returns
    /// the whole Catalogue, paged.
    @GetMapping("/search")
    CatalogueDtos.SearchResponse search(
            @RequestParam(required = false, defaultValue = "") String q,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(required = false) Integer size) {

        if (page < 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "page cannot be negative.");
        }
        return service.search(q, page, size);
    }
}
