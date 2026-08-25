package lt.hereader.server.catalogue;

/// Thrown for anything wrong with the upstream export — unreachable,
/// non-200, malformed or truncated. Always thrown before any row of the new
/// data is written, so the existing Catalogue is untouched (ADR 0029).
public class CatalogueIngestionException extends RuntimeException {

    public CatalogueIngestionException(String message) {
        super(message);
    }

    public CatalogueIngestionException(String message, Throwable cause) {
        super(message, cause);
    }
}
