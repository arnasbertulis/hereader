package lt.hereader.server.catalogue;

import javax.xml.stream.XMLInputFactory;
import javax.xml.stream.XMLStreamConstants;
import javax.xml.stream.XMLStreamException;
import java.io.FilterInputStream;
import java.io.InputStream;

/// Reads one Gutenberg per-book RDF/XML record from the bulk archive: the
/// tail of the `pgterms:ebook` element's `rdf:about` subject URI (the
/// Gutenberg book number) and its `pgterms:downloads` count. StAX rather than
/// a DOM, so parsing one entry allocates on the order of that one entry, not
/// the whole archive (ADR 0029, #177) — CataloguePopularityIngestionService
/// hands this class one tar entry's stream at a time and never buffers it.
///
/// External entities and DTDs are disabled: Gutenberg's own archive would
/// never need either, so there is no reason for a parser reading it to
/// resolve anything outside the stream it was given.
final class GutenbergRdfEntryReader {

    private static final String RDF_NS = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
    private static final String PGTERMS_NS = "http://www.gutenberg.org/2009/pgterms/";

    private static final XMLInputFactory FACTORY = createFactory();

    record Record(int gutenbergId, int downloads) {}

    private GutenbergRdfEntryReader() {}

    /// Null when the entry has no ebook subject URI, no downloads figure, or
    /// either fails to parse as an integer, or the entry's XML is malformed —
    /// CataloguePopularityIngestionService treats all of those as "nothing to
    /// join for this one entry", not as a reason to abort the whole refresh.
    static Record read(InputStream entry) {
        try {
            // A shield, not a real stream: CataloguePopularityIngestionService
            // keeps reading further tar entries off [entry] after this method
            // returns, but XMLStreamReader.close() below is documented to
            // leave the underlying source open — closing it here anyway,
            // through a wrapper whose close() is a no-op, means that promise
            // doesn't have to be trusted for every StAX implementation this
            // runs on.
            var reader = FACTORY.createXMLStreamReader(new FilterInputStream(entry) {
                @Override
                public void close() {}
            });
            try {
                Integer gutenbergId = null;
                Integer downloads = null;

                while (reader.hasNext()) {
                    if (reader.next() != XMLStreamConstants.START_ELEMENT) {
                        continue;
                    }
                    if (!PGTERMS_NS.equals(reader.getNamespaceURI())) {
                        continue;
                    }
                    if ("ebook".equals(reader.getLocalName())) {
                        gutenbergId = tailId(reader.getAttributeValue(RDF_NS, "about"));
                    } else if ("downloads".equals(reader.getLocalName())) {
                        downloads = parseIntOrNull(reader.getElementText());
                    }
                }

                return (gutenbergId != null && downloads != null)
                        ? new Record(gutenbergId, downloads)
                        : null;
            } finally {
                reader.close();
            }
        } catch (XMLStreamException e) {
            return null;
        }
    }

    /// [about] looks like "ebooks/11" — the id is the tail after the last
    /// '/', which is also what the catalogue CSV's Text# column carries, so
    /// the two exports join on it directly (ADR 0029).
    private static Integer tailId(String about) {
        if (about == null) {
            return null;
        }
        var slash = about.lastIndexOf('/');
        return parseIntOrNull(slash >= 0 ? about.substring(slash + 1) : about);
    }

    private static Integer parseIntOrNull(String value) {
        if (value == null) {
            return null;
        }
        try {
            return Integer.parseInt(value.trim());
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static XMLInputFactory createFactory() {
        var factory = XMLInputFactory.newInstance();
        factory.setProperty(XMLInputFactory.SUPPORT_DTD, false);
        factory.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, false);
        return factory;
    }
}
