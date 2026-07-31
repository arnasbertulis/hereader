import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'epub_book.dart';
import 'html_normalizer.dart';

const _containerPath = 'META-INF/container.xml';

/// Reads an EPUB from bytes.
///
/// Bytes rather than a path: on Flutter web a picked file arrives as bytes
/// with no filesystem behind it, and books are never written anywhere else.
///
/// Parsing is synchronous and CPU-bound. Run it off the UI isolate for
/// anything larger than a short story.
class EpubParser {
  final HtmlNormalizer normalizer;

  const EpubParser({this.normalizer = const HtmlNormalizer()});

  EpubBook parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw const EpubException('The file is not a readable zip archive.');
    }

    final opfPath = _findOpfPath(archive);
    final opf = _parseXml(_readString(archive, opfPath), opfPath);
    final opfDir = _dirname(opfPath);

    final manifest = _readManifest(opf);
    final metadata = _readMetadata(opf, manifest, opfDir);
    final documents = _readSpine(archive, opf, manifest, opfDir);

    if (documents.isEmpty) {
      throw const EpubException('The book contains no readable text.');
    }

    return EpubBook(metadata: metadata, documents: documents);
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

  String _findOpfPath(Archive archive) {
    final container =
        _parseXml(_readString(archive, _containerPath), _containerPath);

    final rootfile =
        container.findAllElements('rootfile', namespaceUri: '*').firstOrNull;
    final path = rootfile?.getAttribute('full-path');

    if (path == null || path.isEmpty) {
      throw const EpubException(
          'The container does not name a package document.');
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
    Archive archive,
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

      final blocks = normalizer.normalize(source, href: href);
      if (blocks.isEmpty) continue;

      documents.add(EpubDocument(
        href: href,
        blocks: blocks,
        isLinear: ref.getAttribute('linear') != 'no',
      ));
    }

    return documents;
  }

  String _readString(Archive archive, String path) {
    final file = archive.files.where((f) => f.name == path).firstOrNull ??
        // Some writers store paths with a leading slash or different case.
        archive.files
            .where((f) => f.name.toLowerCase() == path.toLowerCase())
            .firstOrNull;

    if (file == null) {
      throw EpubException('The archive is missing $path.');
    }

    final data = file.readBytes();
    if (data == null) {
      throw EpubException('Could not read $path from the archive.');
    }

    // Most EPUBs are UTF-8. allowMalformed keeps one bad byte from taking
    // down a whole chapter.
    return utf8.decode(data, allowMalformed: true);
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
