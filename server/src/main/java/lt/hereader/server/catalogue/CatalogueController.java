package lt.hereader.server.catalogue;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Locale;

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
    /// the whole Catalogue, paged. [category] and [language] each narrow the
    /// result further and combine with [q] and with each other; either left
    /// blank or absent applies no filter — in particular, no language is
    /// ever assumed, so a reader whose language holds few books does not
    /// open Free books to an empty screen on the strength of a device
    /// setting. An unrecognized [category] or [language] is not an error:
    /// CatalogueService treats it as an ordinary filter that happens to
    /// match nothing. [sort] is "title", "author", "issued" or "popularity",
    /// case-insensitive; left absent, CatalogueService picks a default from
    /// whether [q] is blank.
    @GetMapping("/search")
    CatalogueDtos.SearchResponse search(
            @RequestParam(required = false, defaultValue = "") String q,
            @RequestParam(required = false, defaultValue = "") String category,
            @RequestParam(required = false, defaultValue = "") String language,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort) {

        if (page < 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "page cannot be negative.");
        }
        return service.search(q, category, language, page, size, parseSort(sort));
    }

    /// Every Category at least one Catalogue Entry carries, with how many —
    /// the browse screen's own filter list, not a page of results.
    @GetMapping("/categories")
    List<CatalogueDtos.CategoryCount> categories() {
        return service.categories();
    }

    private static CatalogueDtos.Sort parseSort(String sort) {
        if (sort == null || sort.isBlank()) {
            return null;
        }
        try {
            return CatalogueDtos.Sort.valueOf(sort.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "sort must be 'title', 'author', 'issued' or 'popularity'.");
        }
    }
}
