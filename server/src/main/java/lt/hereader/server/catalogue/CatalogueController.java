package lt.hereader.server.catalogue;

import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.util.List;
import java.util.Locale;

/// Public — browsing free public-domain books does not need an account
/// (ADR 0029). Permitted through SecurityConfig and rate limited on its own
/// path budget, independent of every other budget.
@RestController
@RequestMapping("/catalogue")
class CatalogueController {

    // A cover is immutable for a given Gutenberg book number (ADR 0029), so
    // the client is told to hold on to it indefinitely rather than
    // revalidating on every Library/Free-books render.
    private static final CacheControl COVER_CACHE_CONTROL =
            CacheControl.maxAge(Duration.ofDays(365)).cachePublic();

    private final CatalogueService service;
    private final CatalogueProxyService proxy;

    CatalogueController(CatalogueService service, CatalogueProxyService proxy) {
        this.service = service;
        this.proxy = proxy;
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
    /// case-insensitive; left absent, CatalogueQuery picks a default from
    /// whether [q] is blank. [direction] is "ascending" or "descending",
    /// case-insensitive; left absent, CatalogueQuery picks the resolved
    /// [sort] field's own existing default direction.
    @GetMapping("/search")
    CatalogueDtos.SearchResponse search(
            @RequestParam(required = false, defaultValue = "") String q,
            @RequestParam(required = false, defaultValue = "") String category,
            @RequestParam(required = false, defaultValue = "") String language,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(required = false) Integer size,
            @RequestParam(required = false) String sort,
            @RequestParam(required = false) String direction) {

        if (page < 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "page cannot be negative.");
        }
        return service.search(CatalogueQuery.of(
                q, category, language, page, size, parseSort(sort), parseDirection(direction)));
    }

    /// Every Category at least one Catalogue Entry carries, with how many —
    /// the browse screen's own filter list, not a page of results.
    @GetMapping("/categories")
    List<CatalogueDtos.CategoryCount> categories() {
        return service.categories();
    }

    /// Every Language at least one Catalogue Entry carries, with how many —
    /// the browse screen's own filter list, not a page of results.
    @GetMapping("/languages")
    List<CatalogueDtos.LanguageCount> languages() {
        return service.languages();
    }

    /// Streams a Catalogue Entry's cover through the service — Gutenberg
    /// sends no CORS header the deployed web build's origin restrictions
    /// would accept a direct fetch under (ADR 0029).
    @GetMapping("/cover/{gutenbergId}")
    ResponseEntity<byte[]> cover(@PathVariable int gutenbergId) {
        var file = proxy.fetchCover(gutenbergId);
        return ResponseEntity.ok()
                .contentType(file.contentType())
                .cacheControl(COVER_CACHE_CONTROL)
                .body(file.bytes());
    }

    /// The no-images edition where Gutenberg has one, the advertised
    /// (illustrated) edition otherwise — CatalogueProxyService picks between
    /// them so the app never has to.
    @GetMapping("/download/{gutenbergId}")
    ResponseEntity<byte[]> download(@PathVariable int gutenbergId) {
        var file = proxy.fetchBookFile(gutenbergId);
        return ResponseEntity.ok()
                .contentType(file.contentType())
                .body(file.bytes());
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

    private static CatalogueDtos.Direction parseDirection(String direction) {
        if (direction == null || direction.isBlank()) {
            return null;
        }
        try {
            return CatalogueDtos.Direction.valueOf(direction.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "direction must be 'ascending' or 'descending'.");
        }
    }
}
