package lt.hereader.server.catalogue;

import java.io.IOException;
import java.io.Reader;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.NoSuchElementException;

/// A minimal RFC 4180 reader for Gutenberg's catalogue export: quoted
/// fields, commas and newlines embedded inside them, and a doubled quote as
/// an escaped one. Written by hand rather than pulling in a library — the
/// format is small enough, and the one property this actually needs, an
/// unterminated quote surfacing as failure rather than silently swallowing
/// the rest of the file, is not something a general-purpose parser
/// guarantees without configuration this project would have to get right
/// anyway.
///
/// Row length is not this class's concern — CatalogueIngestionService
/// checks every row against the header's column count, since "fewer columns
/// than the header" is exactly what a connection cut mid-download produces.
final class GutenbergCsvReader implements Iterator<List<String>>, AutoCloseable {

    private final Reader in;
    private int pushedBack = -2; // -2: nothing pushed back.
    private List<String> nextRow;

    GutenbergCsvReader(Reader in) {
        this.in = in;
        advance();
    }

    @Override
    public boolean hasNext() {
        return nextRow != null;
    }

    @Override
    public List<String> next() {
        if (nextRow == null) {
            throw new NoSuchElementException();
        }
        var row = nextRow;
        advance();
        return row;
    }

    @Override
    public void close() throws IOException {
        in.close();
    }

    private int read() {
        if (pushedBack != -2) {
            var c = pushedBack;
            pushedBack = -2;
            return c;
        }
        try {
            return in.read();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private void advance() {
        var fields = new ArrayList<String>();
        var field = new StringBuilder();
        var quoted = false;

        var c = read();
        if (c == -1) {
            nextRow = null;
            return;
        }

        while (true) {
            if (c == -1) {
                if (quoted) {
                    throw new IllegalStateException(
                            "Catalogue export ended inside a quoted field.");
                }
                fields.add(field.toString());
                nextRow = fields;
                return;
            }

            if (quoted) {
                if (c == '"') {
                    var peeked = read();
                    if (peeked == '"') {
                        field.append('"');
                    } else {
                        quoted = false;
                        if (peeked != -1) {
                            pushedBack = peeked;
                        }
                    }
                } else {
                    field.append((char) c);
                }
            } else if (c == '"' && field.isEmpty()) {
                quoted = true;
            } else if (c == ',') {
                fields.add(field.toString());
                field = new StringBuilder();
            } else if (c == '\r') {
                // Ignored; the '\n' that follows ends the row.
            } else if (c == '\n') {
                fields.add(field.toString());
                nextRow = fields;
                return;
            } else {
                field.append((char) c);
            }

            c = read();
        }
    }
}
