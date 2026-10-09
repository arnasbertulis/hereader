import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import 'epub_book.dart';
import 'html_normalizer.dart';
import 'toc.dart';

const _containerPath = 'META-INF/container.xml';

/// Maximum number of entries a zip archive may declare.
///
/// `decodeBytes` only reads the central directory here (no entry is
/// decompressed yet), so this is checked before any bytes are inflated.
/// `test/fixtures/romeo-and-juliet.epub` — an ordinary novel — has 19
/// entries; 10,000 leaves generous headroom for a large illustrated or
/// multi-volume EPUB while still bounding a crafted archive with millions
/// of tiny entries.
const _maxArchiveEntries = 10000;

/// Default for [EpubParser.maxUncompressedBytes]: the most uncompressed
/// content a book may hold, in bytes.
///
/// Enforced twice. The sizes the central directory declares are summed
/// before anything is inflated, which rejects an honest zip bomb cheaply.
/// Those sizes are attacker-controlled, so inflation is also stopped once
/// the bytes it actually produces, summed over every entry read, pass the
/// same number. `test/fixtures/romeo-and-juliet.epub` totals ~489 KiB
/// uncompressed; 512 MiB leaves three orders of magnitude of headroom for a
/// heavily illustrated book.
const _defaultMaxUncompressedBytes = 512 * 1024 * 1024;

const _tooMuchContent =
    'The file contains too much uncompressed content to be a readable EPUB.';

/// A table of contents entry before it has been matched to a document.
///
/// [href] is an archive path; [fragment] is the part after the `#`, empty
/// when the entry names a whole document.
typedef _RawEntry = ({String title, String href, String fragment, int depth});

/// Reads an EPUB from bytes.
///
/// Bytes rather than a path: on Flutter web a picked file arrives as bytes
/// with no filesystem behind it, and books are never written anywhere else.
///
/// Parsing is synchronous and CPU-bound. Run it off the UI isolate for
/// anything larger than a short story.
class EpubParser {
  final HtmlNormalizer normalizer;

  /// The most uncompressed content a book may hold, in bytes, summed over
  /// every entry read. A book past it fails with an [EpubException].
  ///
  /// The default is generous for any real book; lowering it is for tests.
  final int maxUncompressedBytes;

  const EpubParser({
    this.normalizer = const HtmlNormalizer(),
    this.maxUncompressedBytes = _defaultMaxUncompressedBytes,
  });

  EpubBook parse(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw const EpubException('The file is not a readable zip archive.');
    }

    if (zip.length > _maxArchiveEntries) {
      throw const EpubException(
        'The file declares too many entries to be a readable EPUB.',
      );
    }
    var declaredBytes = 0;
    for (final file in zip.files) {
      declaredBytes += file.size;
      if (declaredBytes > maxUncompressedBytes) {
        throw const EpubException(_tooMuchContent);
      }
    }
    final archive = _BoundedArchive(zip, maxUncompressedBytes);

    final opfPath = _findOpfPath(archive);
    final opf = _parseXml(_readString(archive, opfPath), opfPath);
    final opfDir = _dirname(opfPath);

    final manifest = _readManifest(opf);
    final metadata = _readMetadata(opf, manifest, opfDir);
    final documents = _readSpine(archive, opf, manifest, opfDir);

    if (documents.isEmpty) {
      throw const EpubException('The book contains no readable text.');
    }

    return EpubBook(
      metadata: metadata,
      documents: documents,
      toc: _readToc(archive, opf, manifest, opfDir, documents),
      // Read here rather than by a second pass, because _readMetadata has
      // already worked out which archive entry the cover is and the archive
      // goes out of scope at the end of this method.
      coverBytes: _readCover(archive, metadata.coverHref),
    );
  }

  // -------------------------------------------------------------------

  /// Keeps the xml package's exception type from reaching callers.
  /// Everything this class throws is an [EpubException].
  XmlDocument _parseXml(String source, String path) {
    try {
      return XmlDocument.parse(source);
    } on XmlException {
      throw EpubException('$path is not valid XML.');
    }
  }

  String _findOpfPath(_BoundedArchive archive) {
    final container = _parseXml(
      _readString(archive, _containerPath),
      _containerPath,
    );

    final rootfile = container
        .findAllElements('rootfile', namespaceUri: '*')
        .firstOrNull;
    final path = rootfile?.getAttribute('full-path');

    if (path == null || path.isEmpty) {
      throw const EpubException(
        'The container does not name a package document.',
      );
    }
    return _decode(path);
  }

  /// Manifest id to href, resolved against the OPF directory.
  Map<String, _ManifestItem> _readManifest(XmlDocument opf) {
    final items = <String, _ManifestItem>{};

    for (final element in opf.findAllElements('item', namespaceUri: '*')) {
      final id = element.getAttribute('id');
      final href = element.getAttribute('href');
      if (id == null || href == null) continue;

      items[id] = _ManifestItem(
        href: _decode(href),
        mediaType: element.getAttribute('media-type') ?? '',
        properties: element.getAttribute('properties') ?? '',
      );
    }

    if (items.isEmpty) {
      throw const EpubException('The package document has an empty manifest.');
    }
    return items;
  }

  EpubMetadata _readMetadata(
    XmlDocument opf,
    Map<String, _ManifestItem> manifest,
    String opfDir,
  ) {
    String? first(String name) => opf
        .findAllElements(name, namespaceUri: '*')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty)
        .firstOrNull;

    return EpubMetadata(
      title: first('title') ?? 'Untitled',
      author: first('creator'),
      language: first('language'),
      identifier: first('identifier'),
      coverHref: _findCover(opf, manifest, opfDir),
    );
  }

  /// EPUB 3 marks the cover with `properties="cover-image"`. EPUB 2 uses a
  /// `<meta name="cover" content="manifest-id"/>`. Both appear in the wild.
  String? _findCover(
    XmlDocument opf,
    Map<String, _ManifestItem> manifest,
    String opfDir,
  ) {
    for (final entry in manifest.entries) {
      if (entry.value.properties.contains('cover-image')) {
        return _resolve(opfDir, entry.value.href);
      }
    }

    for (final meta in opf.findAllElements('meta', namespaceUri: '*')) {
      if (meta.getAttribute('name') == 'cover') {
        final id = meta.getAttribute('content');
        final item = id == null ? null : manifest[id];
        if (item != null) return _resolve(opfDir, item.href);
      }
    }
    return null;
  }

  List<EpubDocument> _readSpine(
    _BoundedArchive archive,
    XmlDocument opf,
    Map<String, _ManifestItem> manifest,
    String opfDir,
  ) {
    final spine = opf.findAllElements('spine', namespaceUri: '*').firstOrNull;
    if (spine == null) {
      throw const EpubException('The package document has no spine.');
    }

    final documents = <EpubDocument>[];

    for (final ref in spine.findAllElements('itemref', namespaceUri: '*')) {
      final id = ref.getAttribute('idref');
      final item = id == null ? null : manifest[id];
      if (item == null) continue;

      // Skip anything that is not markup: some spines reference SVG or
      // fixed-layout assets that hold no readable text.
      if (!item.mediaType.contains('xhtml') &&
          !item.mediaType.contains('html')) {
        continue;
      }

      final href = _resolve(opfDir, item.href);
      final String source;
      try {
        source = _readString(archive, href);
      } on EpubException {
        // A missing spine document is a broken book, not a fatal error.
        // Skip it and keep the rest readable.
        continue;
      }

      final normalized = normalizer.normalize(source, href: href);
      if (normalized.blocks.isEmpty) continue;

      documents.add(
        EpubDocument(
          href: href,
          blocks: normalized.blocks,
          anchors: normalized.anchors,
          isLinear: ref.getAttribute('linear') != 'no',
        ),
      );
    }

    return documents;
  }

  // -- table of contents ----------------------------------------------

  /// The book's own table of contents, resolved against what was actually
  /// parsed.
  ///
  /// EPUB 3 puts it in a navigation document flagged `properties="nav"` in
  /// the manifest; EPUB 2 puts it in an NCX named by the spine's `toc`
  /// attribute. Books produced this decade usually carry both, so the newer
  /// form is preferred and the older one is a fallback rather than a second
  /// source to merge.
  ///
  /// Never throws. A book with an unreadable table of contents is still a
  /// readable book, and losing chapter navigation is a smaller failure than
  /// refusing to open it.
  List<TocEntry> _readToc(
    _BoundedArchive archive,
    XmlDocument opf,
    Map<String, _ManifestItem> manifest,
    String opfDir,
    List<EpubDocument> documents,
  ) {
    try {
      var raw = _readNav(archive, manifest, opfDir);
      if (raw.isEmpty) raw = _readNcx(archive, opf, manifest, opfDir);

      return _resolveEntries(raw, documents);
    } catch (_) {
      return const [];
    }
  }

  /// EPUB 3 navigation document.
  ///
  /// The nav document is usually absent from the spine — it is navigation,
  /// not a chapter — so it has to be found through the manifest rather than
  /// among the documents already parsed.
  ///
  /// Parsed as HTML rather than XML. It is XHTML by specification, but the
  /// same tolerance that makes the normalizer work on real books applies
  /// here, and a stray unescaped ampersand should not cost a reader their
  /// chapter list.
  List<_RawEntry> _readNav(
    _BoundedArchive archive,
    Map<String, _ManifestItem> manifest,
    String opfDir,
  ) {
    String? navHref;
    for (final item in manifest.values) {
      if (_hasToken(item.properties, 'nav')) {
        navHref = _resolve(opfDir, item.href);
        break;
      }
    }
    if (navHref == null) return const [];

    final String source;
    try {
      source = _readString(archive, navHref);
    } on EpubException {
      return const [];
    }

    final body = html_parser.parse(source).body;
    if (body == null) return const [];

    final navs = <dom.Element>[];
    _findElements(body, 'nav', navs);
    if (navs.isEmpty) return const [];

    var chosen = navs.first;
    for (final candidate in navs) {
      final type =
          candidate.attributes['epub:type'] ??
          candidate.attributes['type'] ??
          '';
      if (_hasToken(type, 'toc')) {
        chosen = candidate;
        break;
      }
    }

    final entries = <_RawEntry>[];
    final base = _dirname(navHref);

    for (final child in chosen.children) {
      if (child.localName == 'ol' || child.localName == 'ul') {
        _readNavList(child, base, 0, entries);
      }
    }
    return entries;
  }

  void _readNavList(
    dom.Element list,
    String base,
    int depth,
    List<_RawEntry> out,
  ) {
    for (final item in list.children) {
      if (item.localName != 'li') continue;

      for (final child in item.children) {
        if (child.localName != 'a') continue;

        final href = child.attributes['href'];
        final title = _flatten(child);
        if (href != null && href.isNotEmpty && title.isNotEmpty) {
          out.add(_rawEntry(base, href, title, depth));
        }
        break;
      }

      // Nested lists are the child levels of this entry. Walked after the
      // link so entries come out in reading order rather than by level.
      for (final child in item.children) {
        if (child.localName == 'ol' || child.localName == 'ul') {
          _readNavList(child, base, depth + 1, out);
        }
      }
    }
  }

  /// EPUB 2 NCX, used when there is no navigation document.
  List<_RawEntry> _readNcx(
    _BoundedArchive archive,
    XmlDocument opf,
    Map<String, _ManifestItem> manifest,
    String opfDir,
  ) {
    _ManifestItem? item;

    final spine = opf.findAllElements('spine', namespaceUri: '*').firstOrNull;
    final declared = spine?.getAttribute('toc');
    if (declared != null) item = manifest[declared];

    // A spine that names no NCX is common enough in EPUB 3 files that also
    // ship one for backwards compatibility.
    if (item == null) {
      for (final candidate in manifest.values) {
        if (candidate.mediaType.contains('dtbncx')) {
          item = candidate;
          break;
        }
      }
    }
    if (item == null) return const [];

    final href = _resolve(opfDir, item.href);
    final String source;
    try {
      source = _readString(archive, href);
    } on EpubException {
      return const [];
    }

    final XmlDocument ncx;
    try {
      ncx = XmlDocument.parse(source);
    } on XmlException {
      return const [];
    }

    final map = ncx.findAllElements('navMap', namespaceUri: '*').firstOrNull;
    if (map == null) return const [];

    final entries = <_RawEntry>[];
    _readNavPoints(map, _dirname(href), 0, entries);
    return entries;
  }

  void _readNavPoints(
    XmlElement parent,
    String base,
    int depth,
    List<_RawEntry> out,
  ) {
    for (final point in parent.findElements('navPoint', namespaceUri: '*')) {
      String title = '';
      for (final label in point.findElements('navLabel', namespaceUri: '*')) {
        title = label.innerText.replaceAll(_space, ' ').trim();
        break;
      }

      for (final content in point.findElements('content', namespaceUri: '*')) {
        final src = content.getAttribute('src');
        if (src != null && src.isNotEmpty && title.isNotEmpty) {
          out.add(_rawEntry(base, src, title, depth));
        }
        break;
      }

      _readNavPoints(point, base, depth + 1, out);
    }
  }

  /// Matches entries to blocks, dropping anything unreachable.
  ///
  /// An entry surviving with a block id nothing can resolve would render as
  /// a chapter that silently does nothing when tapped, which is worse than
  /// a chapter list that is one entry short.
  List<TocEntry> _resolveEntries(
    List<_RawEntry> raw,
    List<EpubDocument> documents,
  ) {
    final byHref = <String, EpubDocument>{
      for (final document in documents) document.href: document,
    };

    final entries = <TocEntry>[];

    for (final entry in raw) {
      final document = byHref[entry.href];

      // Absent, or outside the reading flow. `readingOrder` skips non-linear
      // documents, so an entry pointing into one names a block the reader
      // can never reach by reading forward.
      if (document == null || !document.isLinear) continue;
      if (document.blocks.isEmpty) continue;

      // An unknown fragment falls back to the top of the document rather
      // than dropping the entry. The book says a chapter starts in this
      // file; landing at its start is close, and losing the entry is not.
      final index = entry.fragment.isEmpty
          ? 0
          : (document.anchors[entry.fragment] ?? 0);

      final block = document.blocks[index.clamp(0, document.blocks.length - 1)];

      entries.add(
        TocEntry(title: entry.title, blockId: block.id, depth: entry.depth),
      );
    }

    return entries;
  }

  /// The archive entry at [path], or null when nothing matches.
  ///
  /// Some writers store paths with a leading slash or in a different case
  /// from the one the OPF gives, so an exact match is tried first and a
  /// case-insensitive one after it.
  ArchiveFile? _findFile(_BoundedArchive archive, String path) =>
      archive.files.where((f) => f.name == path).firstOrNull ??
      archive.files
          .where((f) => f.name.toLowerCase() == path.toLowerCase())
          .firstOrNull;

  /// The bytes of the declared cover, or null.
  ///
  /// Returns null rather than throwing the way [_readString] does. A spine
  /// document the book cannot supply makes the book unreadable; a cover it
  /// cannot supply makes it a book without a picture.
  Uint8List? _readCover(_BoundedArchive archive, String? href) {
    if (href == null) return null;

    final file = _findFile(archive, href);
    final data = file == null ? null : archive.read(file);
    if (data == null || data.isEmpty) return null;

    return Uint8List.fromList(data);
  }

  String _readString(_BoundedArchive archive, String path) {
    final file = _findFile(archive, path);

    if (file == null) {
      throw EpubException('The archive is missing $path.');
    }

    final data = archive.read(file);
    if (data == null) {
      throw EpubException('Could not read $path from the archive.');
    }

    // Most EPUBs are UTF-8. allowMalformed keeps one bad byte from taking
    // down a whole chapter.
    return utf8.decode(data, allowMalformed: true);
  }
}

/// A zip archive whose entries are read against one shared budget of
/// uncompressed bytes.
///
/// The archive package sizes its decompression buffer from the size the
/// central directory declares, and a crafted zip can declare anything. So
/// [read] inflates through [Inflate] into a [_CappedOutput] instead of
/// calling `ArchiveFile.readBytes`: the budget is charged from the bytes
/// actually produced, and inflation stops the moment they exceed it. That
/// also bypasses `dart:io`'s zlib on the VM, which would buffer an entire
/// entry before handing back the first byte.
class _BoundedArchive {
  _BoundedArchive(this._zip, this._remaining);

  final Archive _zip;
  int _remaining;

  Iterable<ArchiveFile> get files => _zip.files;

  /// The uncompressed bytes of [file], or null when it cannot be read.
  ///
  /// Throws [EpubException] when the bytes it holds, added to those of the
  /// entries read before it, would pass the budget. An entry compressed with
  /// anything but deflate or store is unreadable: the EPUB container format
  /// allows nothing else, and no other decoder here is bounded.
  Uint8List? read(ArchiveFile file) {
    final raw = file.rawContent;
    if (raw == null) return null;

    final Uint8List bytes;
    switch (file.compression) {
      case CompressionType.none:
        if (raw.length > _remaining) throw const EpubException(_tooMuchContent);
        bytes = raw.getStream(decompress: false).toUint8List();
      case CompressionType.deflate:
        final input = raw.getStream(decompress: false);
        final start = input.position;
        final output = _CappedOutput(_remaining);
        try {
          Inflate.stream(input, output: output);
        } on _BudgetExceeded {
          throw const EpubException(_tooMuchContent);
        } catch (_) {
          return null;
        } finally {
          input.setPosition(start);
        }
        bytes = output.getBytes();
      case _:
        return null;
    }

    _remaining -= bytes.length;
    return bytes;
  }
}

class _BudgetExceeded implements Exception {
  const _BudgetExceeded();
}

/// An in-memory output that throws [_BudgetExceeded] instead of growing
/// past [limit] bytes.
///
/// Every write is checked before it lands, so the buffer never holds more
/// than [limit] bytes. `writeBackReference` is how archive 4.2 and later
/// writes a deflate back-reference, and it is where a zip bomb spends nearly
/// all of its output; 4.0.9, which the app's lockfile still pins, does not
/// have it and writes a back-reference through `writeBytes` instead.
class _CappedOutput extends OutputMemoryStream {
  _CappedOutput(this.limit);

  final int limit;

  void _reserve(int count) {
    if (length + count > limit) throw const _BudgetExceeded();
  }

  @override
  void writeByte(int value) {
    _reserve(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _reserve(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _reserve(stream.length);
    super.writeStream(stream);
  }

  // No `@override`: the method does not exist before archive 4.2, and a
  // `super` call to it would not compile against 4.0.9. Copying through
  // `writeBytes` works on both, and `n <= distance` keeps source and
  // destination from overlapping within one copy.
  // ignore: annotate_overrides
  void writeBackReference(int distance, int count) {
    _reserve(count);
    var left = count;
    while (left > 0) {
      final n = left < distance ? left : distance;
      final from = length - distance;
      super.writeBytes(subset(from, from + n));
      left -= n;
    }
  }
}

class _ManifestItem {
  final String href;
  final String mediaType;
  final String properties;

  const _ManifestItem({
    required this.href,
    required this.mediaType,
    required this.properties,
  });
}

final _space = RegExp(r'\s+');

/// Whitespace-separated attribute values, matched whole.
///
/// `properties="nav"` and `properties="scripted nav"` both declare a
/// navigation document; `properties="navigation-aid"` does not, and a
/// substring test would take it.
bool _hasToken(String value, String token) =>
    value.split(_space).contains(token);

void _findElements(dom.Element? root, String tag, List<dom.Element> out) {
  if (root == null) return;
  if (root.localName == tag) out.add(root);
  for (final child in root.children) {
    _findElements(child, tag, out);
  }
}

/// Text of an element with whitespace collapsed.
///
/// A navigation label often wraps its text in a span, so the text nodes have
/// to be gathered rather than read off the element.
String _flatten(dom.Node node) {
  final buffer = StringBuffer();

  void collect(dom.Node current) {
    for (final child in current.nodes) {
      if (child is dom.Text) {
        buffer.write(child.text);
      } else if (child is dom.Element) {
        collect(child);
      }
    }
  }

  collect(node);
  return buffer.toString().replaceAll(_space, ' ').trim();
}

_RawEntry _rawEntry(String base, String href, String title, int depth) {
  final hash = href.indexOf('#');
  final path = hash == -1 ? href : href.substring(0, hash);
  final fragment = hash == -1 ? '' : _decode(href.substring(hash + 1));

  return (
    title: title,
    href: _resolve(base, path),
    fragment: fragment,
    depth: depth,
  );
}

String _decode(String value) {
  try {
    return Uri.decodeFull(value);
  } catch (_) {
    return value;
  }
}

String _dirname(String path) {
  final i = path.lastIndexOf('/');
  return i == -1 ? '' : path.substring(0, i);
}

/// Resolves an href against the OPF's directory, collapsing `.` and `..`.
String _resolve(String base, String href) {
  if (href.startsWith('/')) return href.substring(1);

  final segments = <String>[
    if (base.isNotEmpty) ...base.split('/'),
    ..._decode(href).split('/'),
  ];

  final out = <String>[];
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(segment);
  }
  return out.join('/');
}
