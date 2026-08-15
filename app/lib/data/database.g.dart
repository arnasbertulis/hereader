// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, Book> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<DateTime> importedAt = GeneratedColumn<DateTime>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wordCountMeta = const VerificationMeta(
    'wordCount',
  );
  @override
  late final GeneratedColumn<int> wordCount = GeneratedColumn<int>(
    'word_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    author,
    language,
    bytes,
    importedAt,
    wordCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<Book> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    if (data.containsKey('word_count')) {
      context.handle(
        _wordCountMeta,
        wordCount.isAcceptableOrUnknown(data['word_count']!, _wordCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Book map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Book(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}imported_at'],
      )!,
      wordCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}word_count'],
      )!,
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class Book extends DataClass implements Insertable<Book> {
  /// The book's own identifier where it has one, otherwise title and author.
  /// Shared across devices, so it must not be device-local.
  final String id;
  final String title;
  final String? author;
  final String? language;

  /// The original EPUB. Large books make for large rows; acceptable for
  /// text, noted as a limit for heavily illustrated volumes.
  final Uint8List bytes;
  final DateTime importedAt;

  /// Cached so the library list does not parse every book to draw itself.
  final int wordCount;
  const Book({
    required this.id,
    required this.title,
    this.author,
    this.language,
    required this.bytes,
    required this.importedAt,
    required this.wordCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    map['bytes'] = Variable<Uint8List>(bytes);
    map['imported_at'] = Variable<DateTime>(importedAt);
    map['word_count'] = Variable<int>(wordCount);
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      bytes: Value(bytes),
      importedAt: Value(importedAt),
      wordCount: Value(wordCount),
    );
  }

  factory Book.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Book(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String?>(json['author']),
      language: serializer.fromJson<String?>(json['language']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
      importedAt: serializer.fromJson<DateTime>(json['importedAt']),
      wordCount: serializer.fromJson<int>(json['wordCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String?>(author),
      'language': serializer.toJson<String?>(language),
      'bytes': serializer.toJson<Uint8List>(bytes),
      'importedAt': serializer.toJson<DateTime>(importedAt),
      'wordCount': serializer.toJson<int>(wordCount),
    };
  }

  Book copyWith({
    String? id,
    String? title,
    Value<String?> author = const Value.absent(),
    Value<String?> language = const Value.absent(),
    Uint8List? bytes,
    DateTime? importedAt,
    int? wordCount,
  }) => Book(
    id: id ?? this.id,
    title: title ?? this.title,
    author: author.present ? author.value : this.author,
    language: language.present ? language.value : this.language,
    bytes: bytes ?? this.bytes,
    importedAt: importedAt ?? this.importedAt,
    wordCount: wordCount ?? this.wordCount,
  );
  Book copyWithCompanion(BooksCompanion data) {
    return Book(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      language: data.language.present ? data.language.value : this.language,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
      wordCount: data.wordCount.present ? data.wordCount.value : this.wordCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Book(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('language: $language, ')
          ..write('bytes: $bytes, ')
          ..write('importedAt: $importedAt, ')
          ..write('wordCount: $wordCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    author,
    language,
    $driftBlobEquality.hash(bytes),
    importedAt,
    wordCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Book &&
          other.id == this.id &&
          other.title == this.title &&
          other.author == this.author &&
          other.language == this.language &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.importedAt == this.importedAt &&
          other.wordCount == this.wordCount);
}

class BooksCompanion extends UpdateCompanion<Book> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> author;
  final Value<String?> language;
  final Value<Uint8List> bytes;
  final Value<DateTime> importedAt;
  final Value<int> wordCount;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.language = const Value.absent(),
    this.bytes = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.wordCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    required String title,
    this.author = const Value.absent(),
    this.language = const Value.absent(),
    required Uint8List bytes,
    required DateTime importedAt,
    this.wordCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       bytes = Value(bytes),
       importedAt = Value(importedAt);
  static Insertable<Book> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? language,
    Expression<Uint8List>? bytes,
    Expression<DateTime>? importedAt,
    Expression<int>? wordCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (language != null) 'language': language,
      if (bytes != null) 'bytes': bytes,
      if (importedAt != null) 'imported_at': importedAt,
      if (wordCount != null) 'word_count': wordCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? author,
    Value<String?>? language,
    Value<Uint8List>? bytes,
    Value<DateTime>? importedAt,
    Value<int>? wordCount,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      language: language ?? this.language,
      bytes: bytes ?? this.bytes,
      importedAt: importedAt ?? this.importedAt,
      wordCount: wordCount ?? this.wordCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<DateTime>(importedAt.value);
    }
    if (wordCount.present) {
      map['word_count'] = Variable<int>(wordCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('language: $language, ')
          ..write('bytes: $bytes, ')
          ..write('importedAt: $importedAt, ')
          ..write('wordCount: $wordCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingPositionsTable extends ReadingPositions
    with TableInfo<$ReadingPositionsTable, ReadingPosition> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingPositionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _blockIdMeta = const VerificationMeta(
    'blockId',
  );
  @override
  late final GeneratedColumn<String> blockId = GeneratedColumn<String>(
    'block_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _charOffsetMeta = const VerificationMeta(
    'charOffset',
  );
  @override
  late final GeneratedColumn<int> charOffset = GeneratedColumn<int>(
    'char_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parserVersionMeta = const VerificationMeta(
    'parserVersion',
  );
  @override
  late final GeneratedColumn<int> parserVersion = GeneratedColumn<int>(
    'parser_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenIndexMeta = const VerificationMeta(
    'tokenIndex',
  );
  @override
  late final GeneratedColumn<int> tokenIndex = GeneratedColumn<int>(
    'token_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    blockId,
    charOffset,
    parserVersion,
    tokenIndex,
    hlc,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_positions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingPosition> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('block_id')) {
      context.handle(
        _blockIdMeta,
        blockId.isAcceptableOrUnknown(data['block_id']!, _blockIdMeta),
      );
    } else if (isInserting) {
      context.missing(_blockIdMeta);
    }
    if (data.containsKey('char_offset')) {
      context.handle(
        _charOffsetMeta,
        charOffset.isAcceptableOrUnknown(data['char_offset']!, _charOffsetMeta),
      );
    } else if (isInserting) {
      context.missing(_charOffsetMeta);
    }
    if (data.containsKey('parser_version')) {
      context.handle(
        _parserVersionMeta,
        parserVersion.isAcceptableOrUnknown(
          data['parser_version']!,
          _parserVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parserVersionMeta);
    }
    if (data.containsKey('token_index')) {
      context.handle(
        _tokenIndexMeta,
        tokenIndex.isAcceptableOrUnknown(data['token_index']!, _tokenIndexMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  ReadingPosition map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingPosition(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      blockId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}block_id'],
      )!,
      charOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_offset'],
      )!,
      parserVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parser_version'],
      )!,
      tokenIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}token_index'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReadingPositionsTable createAlias(String alias) {
    return $ReadingPositionsTable(attachedDatabase, alias);
  }
}

class ReadingPosition extends DataClass implements Insertable<ReadingPosition> {
  final String bookId;

  /// Locator fields, stored flat so they can be queried and compared.
  final String blockId;
  final int charOffset;
  final int parserVersion;

  /// How many tokens into the book this position is.
  ///
  /// A hint, not part of the locator. The tokenizer decides what counts as a
  /// token, so this number moves when kParserVersion moves while the locator
  /// stays valid, and nothing may navigate by it. The service compares it to
  /// judge whether two devices have genuinely diverged, and a progress
  /// readout can use it without re-parsing the book.
  ///
  /// Nullable and without a default, because null and zero say different
  /// things: null is no recorded hint, which is every row written before this
  /// column and every event from a client that predates it, while zero is the
  /// first word of the book.
  final int? tokenIndex;

  /// Hybrid logical clock stamp from the device that wrote this. Orders
  /// writes across devices without trusting wall clocks.
  final String hlc;
  final DateTime updatedAt;
  const ReadingPosition({
    required this.bookId,
    required this.blockId,
    required this.charOffset,
    required this.parserVersion,
    this.tokenIndex,
    required this.hlc,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['block_id'] = Variable<String>(blockId);
    map['char_offset'] = Variable<int>(charOffset);
    map['parser_version'] = Variable<int>(parserVersion);
    if (!nullToAbsent || tokenIndex != null) {
      map['token_index'] = Variable<int>(tokenIndex);
    }
    map['hlc'] = Variable<String>(hlc);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReadingPositionsCompanion toCompanion(bool nullToAbsent) {
    return ReadingPositionsCompanion(
      bookId: Value(bookId),
      blockId: Value(blockId),
      charOffset: Value(charOffset),
      parserVersion: Value(parserVersion),
      tokenIndex: tokenIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(tokenIndex),
      hlc: Value(hlc),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReadingPosition.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingPosition(
      bookId: serializer.fromJson<String>(json['bookId']),
      blockId: serializer.fromJson<String>(json['blockId']),
      charOffset: serializer.fromJson<int>(json['charOffset']),
      parserVersion: serializer.fromJson<int>(json['parserVersion']),
      tokenIndex: serializer.fromJson<int?>(json['tokenIndex']),
      hlc: serializer.fromJson<String>(json['hlc']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'blockId': serializer.toJson<String>(blockId),
      'charOffset': serializer.toJson<int>(charOffset),
      'parserVersion': serializer.toJson<int>(parserVersion),
      'tokenIndex': serializer.toJson<int?>(tokenIndex),
      'hlc': serializer.toJson<String>(hlc),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReadingPosition copyWith({
    String? bookId,
    String? blockId,
    int? charOffset,
    int? parserVersion,
    Value<int?> tokenIndex = const Value.absent(),
    String? hlc,
    DateTime? updatedAt,
  }) => ReadingPosition(
    bookId: bookId ?? this.bookId,
    blockId: blockId ?? this.blockId,
    charOffset: charOffset ?? this.charOffset,
    parserVersion: parserVersion ?? this.parserVersion,
    tokenIndex: tokenIndex.present ? tokenIndex.value : this.tokenIndex,
    hlc: hlc ?? this.hlc,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReadingPosition copyWithCompanion(ReadingPositionsCompanion data) {
    return ReadingPosition(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      blockId: data.blockId.present ? data.blockId.value : this.blockId,
      charOffset: data.charOffset.present
          ? data.charOffset.value
          : this.charOffset,
      parserVersion: data.parserVersion.present
          ? data.parserVersion.value
          : this.parserVersion,
      tokenIndex: data.tokenIndex.present
          ? data.tokenIndex.value
          : this.tokenIndex,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingPosition(')
          ..write('bookId: $bookId, ')
          ..write('blockId: $blockId, ')
          ..write('charOffset: $charOffset, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('tokenIndex: $tokenIndex, ')
          ..write('hlc: $hlc, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    blockId,
    charOffset,
    parserVersion,
    tokenIndex,
    hlc,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingPosition &&
          other.bookId == this.bookId &&
          other.blockId == this.blockId &&
          other.charOffset == this.charOffset &&
          other.parserVersion == this.parserVersion &&
          other.tokenIndex == this.tokenIndex &&
          other.hlc == this.hlc &&
          other.updatedAt == this.updatedAt);
}

class ReadingPositionsCompanion extends UpdateCompanion<ReadingPosition> {
  final Value<String> bookId;
  final Value<String> blockId;
  final Value<int> charOffset;
  final Value<int> parserVersion;
  final Value<int?> tokenIndex;
  final Value<String> hlc;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReadingPositionsCompanion({
    this.bookId = const Value.absent(),
    this.blockId = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.parserVersion = const Value.absent(),
    this.tokenIndex = const Value.absent(),
    this.hlc = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingPositionsCompanion.insert({
    required String bookId,
    required String blockId,
    required int charOffset,
    required int parserVersion,
    this.tokenIndex = const Value.absent(),
    required String hlc,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       blockId = Value(blockId),
       charOffset = Value(charOffset),
       parserVersion = Value(parserVersion),
       hlc = Value(hlc),
       updatedAt = Value(updatedAt);
  static Insertable<ReadingPosition> custom({
    Expression<String>? bookId,
    Expression<String>? blockId,
    Expression<int>? charOffset,
    Expression<int>? parserVersion,
    Expression<int>? tokenIndex,
    Expression<String>? hlc,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (blockId != null) 'block_id': blockId,
      if (charOffset != null) 'char_offset': charOffset,
      if (parserVersion != null) 'parser_version': parserVersion,
      if (tokenIndex != null) 'token_index': tokenIndex,
      if (hlc != null) 'hlc': hlc,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingPositionsCompanion copyWith({
    Value<String>? bookId,
    Value<String>? blockId,
    Value<int>? charOffset,
    Value<int>? parserVersion,
    Value<int?>? tokenIndex,
    Value<String>? hlc,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReadingPositionsCompanion(
      bookId: bookId ?? this.bookId,
      blockId: blockId ?? this.blockId,
      charOffset: charOffset ?? this.charOffset,
      parserVersion: parserVersion ?? this.parserVersion,
      tokenIndex: tokenIndex ?? this.tokenIndex,
      hlc: hlc ?? this.hlc,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (blockId.present) {
      map['block_id'] = Variable<String>(blockId.value);
    }
    if (charOffset.present) {
      map['char_offset'] = Variable<int>(charOffset.value);
    }
    if (parserVersion.present) {
      map['parser_version'] = Variable<int>(parserVersion.value);
    }
    if (tokenIndex.present) {
      map['token_index'] = Variable<int>(tokenIndex.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingPositionsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('blockId: $blockId, ')
          ..write('charOffset: $charOffset, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('tokenIndex: $tokenIndex, ')
          ..write('hlc: $hlc, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingPositionsTable extends PendingPositions
    with TableInfo<$PendingPositionsTable, PendingPosition> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingPositionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blockIdMeta = const VerificationMeta(
    'blockId',
  );
  @override
  late final GeneratedColumn<String> blockId = GeneratedColumn<String>(
    'block_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _charOffsetMeta = const VerificationMeta(
    'charOffset',
  );
  @override
  late final GeneratedColumn<int> charOffset = GeneratedColumn<int>(
    'char_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parserVersionMeta = const VerificationMeta(
    'parserVersion',
  );
  @override
  late final GeneratedColumn<int> parserVersion = GeneratedColumn<int>(
    'parser_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenIndexMeta = const VerificationMeta(
    'tokenIndex',
  );
  @override
  late final GeneratedColumn<int> tokenIndex = GeneratedColumn<int>(
    'token_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    blockId,
    charOffset,
    parserVersion,
    tokenIndex,
    hlc,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_positions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingPosition> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('block_id')) {
      context.handle(
        _blockIdMeta,
        blockId.isAcceptableOrUnknown(data['block_id']!, _blockIdMeta),
      );
    } else if (isInserting) {
      context.missing(_blockIdMeta);
    }
    if (data.containsKey('char_offset')) {
      context.handle(
        _charOffsetMeta,
        charOffset.isAcceptableOrUnknown(data['char_offset']!, _charOffsetMeta),
      );
    } else if (isInserting) {
      context.missing(_charOffsetMeta);
    }
    if (data.containsKey('parser_version')) {
      context.handle(
        _parserVersionMeta,
        parserVersion.isAcceptableOrUnknown(
          data['parser_version']!,
          _parserVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parserVersionMeta);
    }
    if (data.containsKey('token_index')) {
      context.handle(
        _tokenIndexMeta,
        tokenIndex.isAcceptableOrUnknown(data['token_index']!, _tokenIndexMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  PendingPosition map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingPosition(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      blockId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}block_id'],
      )!,
      charOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_offset'],
      )!,
      parserVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parser_version'],
      )!,
      tokenIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}token_index'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PendingPositionsTable createAlias(String alias) {
    return $PendingPositionsTable(attachedDatabase, alias);
  }
}

class PendingPosition extends DataClass implements Insertable<PendingPosition> {
  final String bookId;
  final String blockId;
  final int charOffset;
  final int parserVersion;

  /// Carried through the wait, so a book that arrives later arrives with the
  /// reader's progress rather than with a place and no sense of how far in
  /// it is.
  final int? tokenIndex;
  final String hlc;
  final DateTime updatedAt;
  const PendingPosition({
    required this.bookId,
    required this.blockId,
    required this.charOffset,
    required this.parserVersion,
    this.tokenIndex,
    required this.hlc,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['block_id'] = Variable<String>(blockId);
    map['char_offset'] = Variable<int>(charOffset);
    map['parser_version'] = Variable<int>(parserVersion);
    if (!nullToAbsent || tokenIndex != null) {
      map['token_index'] = Variable<int>(tokenIndex);
    }
    map['hlc'] = Variable<String>(hlc);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PendingPositionsCompanion toCompanion(bool nullToAbsent) {
    return PendingPositionsCompanion(
      bookId: Value(bookId),
      blockId: Value(blockId),
      charOffset: Value(charOffset),
      parserVersion: Value(parserVersion),
      tokenIndex: tokenIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(tokenIndex),
      hlc: Value(hlc),
      updatedAt: Value(updatedAt),
    );
  }

  factory PendingPosition.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingPosition(
      bookId: serializer.fromJson<String>(json['bookId']),
      blockId: serializer.fromJson<String>(json['blockId']),
      charOffset: serializer.fromJson<int>(json['charOffset']),
      parserVersion: serializer.fromJson<int>(json['parserVersion']),
      tokenIndex: serializer.fromJson<int?>(json['tokenIndex']),
      hlc: serializer.fromJson<String>(json['hlc']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'blockId': serializer.toJson<String>(blockId),
      'charOffset': serializer.toJson<int>(charOffset),
      'parserVersion': serializer.toJson<int>(parserVersion),
      'tokenIndex': serializer.toJson<int?>(tokenIndex),
      'hlc': serializer.toJson<String>(hlc),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PendingPosition copyWith({
    String? bookId,
    String? blockId,
    int? charOffset,
    int? parserVersion,
    Value<int?> tokenIndex = const Value.absent(),
    String? hlc,
    DateTime? updatedAt,
  }) => PendingPosition(
    bookId: bookId ?? this.bookId,
    blockId: blockId ?? this.blockId,
    charOffset: charOffset ?? this.charOffset,
    parserVersion: parserVersion ?? this.parserVersion,
    tokenIndex: tokenIndex.present ? tokenIndex.value : this.tokenIndex,
    hlc: hlc ?? this.hlc,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PendingPosition copyWithCompanion(PendingPositionsCompanion data) {
    return PendingPosition(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      blockId: data.blockId.present ? data.blockId.value : this.blockId,
      charOffset: data.charOffset.present
          ? data.charOffset.value
          : this.charOffset,
      parserVersion: data.parserVersion.present
          ? data.parserVersion.value
          : this.parserVersion,
      tokenIndex: data.tokenIndex.present
          ? data.tokenIndex.value
          : this.tokenIndex,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingPosition(')
          ..write('bookId: $bookId, ')
          ..write('blockId: $blockId, ')
          ..write('charOffset: $charOffset, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('tokenIndex: $tokenIndex, ')
          ..write('hlc: $hlc, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    blockId,
    charOffset,
    parserVersion,
    tokenIndex,
    hlc,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingPosition &&
          other.bookId == this.bookId &&
          other.blockId == this.blockId &&
          other.charOffset == this.charOffset &&
          other.parserVersion == this.parserVersion &&
          other.tokenIndex == this.tokenIndex &&
          other.hlc == this.hlc &&
          other.updatedAt == this.updatedAt);
}

class PendingPositionsCompanion extends UpdateCompanion<PendingPosition> {
  final Value<String> bookId;
  final Value<String> blockId;
  final Value<int> charOffset;
  final Value<int> parserVersion;
  final Value<int?> tokenIndex;
  final Value<String> hlc;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PendingPositionsCompanion({
    this.bookId = const Value.absent(),
    this.blockId = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.parserVersion = const Value.absent(),
    this.tokenIndex = const Value.absent(),
    this.hlc = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingPositionsCompanion.insert({
    required String bookId,
    required String blockId,
    required int charOffset,
    required int parserVersion,
    this.tokenIndex = const Value.absent(),
    required String hlc,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       blockId = Value(blockId),
       charOffset = Value(charOffset),
       parserVersion = Value(parserVersion),
       hlc = Value(hlc),
       updatedAt = Value(updatedAt);
  static Insertable<PendingPosition> custom({
    Expression<String>? bookId,
    Expression<String>? blockId,
    Expression<int>? charOffset,
    Expression<int>? parserVersion,
    Expression<int>? tokenIndex,
    Expression<String>? hlc,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (blockId != null) 'block_id': blockId,
      if (charOffset != null) 'char_offset': charOffset,
      if (parserVersion != null) 'parser_version': parserVersion,
      if (tokenIndex != null) 'token_index': tokenIndex,
      if (hlc != null) 'hlc': hlc,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingPositionsCompanion copyWith({
    Value<String>? bookId,
    Value<String>? blockId,
    Value<int>? charOffset,
    Value<int>? parserVersion,
    Value<int?>? tokenIndex,
    Value<String>? hlc,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PendingPositionsCompanion(
      bookId: bookId ?? this.bookId,
      blockId: blockId ?? this.blockId,
      charOffset: charOffset ?? this.charOffset,
      parserVersion: parserVersion ?? this.parserVersion,
      tokenIndex: tokenIndex ?? this.tokenIndex,
      hlc: hlc ?? this.hlc,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (blockId.present) {
      map['block_id'] = Variable<String>(blockId.value);
    }
    if (charOffset.present) {
      map['char_offset'] = Variable<int>(charOffset.value);
    }
    if (parserVersion.present) {
      map['parser_version'] = Variable<int>(parserVersion.value);
    }
    if (tokenIndex.present) {
      map['token_index'] = Variable<int>(tokenIndex.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingPositionsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('blockId: $blockId, ')
          ..write('charOffset: $charOffset, ')
          ..write('parserVersion: $parserVersion, ')
          ..write('tokenIndex: $tokenIndex, ')
          ..write('hlc: $hlc, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StoredProfilesTable extends StoredProfiles
    with TableInfo<$StoredProfilesTable, StoredProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pacingJsonMeta = const VerificationMeta(
    'pacingJson',
  );
  @override
  late final GeneratedColumn<String> pacingJson = GeneratedColumn<String>(
    'pacing_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _presentationJsonMeta = const VerificationMeta(
    'presentationJson',
  );
  @override
  late final GeneratedColumn<String> presentationJson = GeneratedColumn<String>(
    'presentation_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rewindWordsMeta = const VerificationMeta(
    'rewindWords',
  );
  @override
  late final GeneratedColumn<int> rewindWords = GeneratedColumn<int>(
    'rewind_words',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    pacingJson,
    presentationJson,
    rewindWords,
    deleted,
    hlc,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('pacing_json')) {
      context.handle(
        _pacingJsonMeta,
        pacingJson.isAcceptableOrUnknown(data['pacing_json']!, _pacingJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_pacingJsonMeta);
    }
    if (data.containsKey('presentation_json')) {
      context.handle(
        _presentationJsonMeta,
        presentationJson.isAcceptableOrUnknown(
          data['presentation_json']!,
          _presentationJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_presentationJsonMeta);
    }
    if (data.containsKey('rewind_words')) {
      context.handle(
        _rewindWordsMeta,
        rewindWords.isAcceptableOrUnknown(
          data['rewind_words']!,
          _rewindWordsMeta,
        ),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      pacingJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pacing_json'],
      )!,
      presentationJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}presentation_json'],
      )!,
      rewindWords: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rewind_words'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StoredProfilesTable createAlias(String alias) {
    return $StoredProfilesTable(attachedDatabase, alias);
  }
}

class StoredProfile extends DataClass implements Insertable<StoredProfile> {
  final String id;
  final String name;

  /// Pacing and presentation as JSON. The engine owns these shapes and
  /// already round-trips them; mirroring every field as a column would mean
  /// a migration for each new setting.
  final String pacingJson;
  final String presentationJson;
  final int rewindWords;

  /// Tombstone. The row outlives the delete so that a later-arriving older
  /// event has a stamp to lose against. Without it, an absent row and a row
  /// deleted a second ago look identical, and any device that was offline
  /// during the deletion would resurrect the profile on its next push.
  ///
  /// ADR 0005 requires this for every deletable entity. A forked profile is
  /// the first one a reader can actually remove.
  final bool deleted;
  final String hlc;
  final DateTime updatedAt;
  const StoredProfile({
    required this.id,
    required this.name,
    required this.pacingJson,
    required this.presentationJson,
    required this.rewindWords,
    required this.deleted,
    required this.hlc,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['pacing_json'] = Variable<String>(pacingJson);
    map['presentation_json'] = Variable<String>(presentationJson);
    map['rewind_words'] = Variable<int>(rewindWords);
    map['deleted'] = Variable<bool>(deleted);
    map['hlc'] = Variable<String>(hlc);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  StoredProfilesCompanion toCompanion(bool nullToAbsent) {
    return StoredProfilesCompanion(
      id: Value(id),
      name: Value(name),
      pacingJson: Value(pacingJson),
      presentationJson: Value(presentationJson),
      rewindWords: Value(rewindWords),
      deleted: Value(deleted),
      hlc: Value(hlc),
      updatedAt: Value(updatedAt),
    );
  }

  factory StoredProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredProfile(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      pacingJson: serializer.fromJson<String>(json['pacingJson']),
      presentationJson: serializer.fromJson<String>(json['presentationJson']),
      rewindWords: serializer.fromJson<int>(json['rewindWords']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      hlc: serializer.fromJson<String>(json['hlc']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'pacingJson': serializer.toJson<String>(pacingJson),
      'presentationJson': serializer.toJson<String>(presentationJson),
      'rewindWords': serializer.toJson<int>(rewindWords),
      'deleted': serializer.toJson<bool>(deleted),
      'hlc': serializer.toJson<String>(hlc),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  StoredProfile copyWith({
    String? id,
    String? name,
    String? pacingJson,
    String? presentationJson,
    int? rewindWords,
    bool? deleted,
    String? hlc,
    DateTime? updatedAt,
  }) => StoredProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    pacingJson: pacingJson ?? this.pacingJson,
    presentationJson: presentationJson ?? this.presentationJson,
    rewindWords: rewindWords ?? this.rewindWords,
    deleted: deleted ?? this.deleted,
    hlc: hlc ?? this.hlc,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StoredProfile copyWithCompanion(StoredProfilesCompanion data) {
    return StoredProfile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      pacingJson: data.pacingJson.present
          ? data.pacingJson.value
          : this.pacingJson,
      presentationJson: data.presentationJson.present
          ? data.presentationJson.value
          : this.presentationJson,
      rewindWords: data.rewindWords.present
          ? data.rewindWords.value
          : this.rewindWords,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredProfile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('pacingJson: $pacingJson, ')
          ..write('presentationJson: $presentationJson, ')
          ..write('rewindWords: $rewindWords, ')
          ..write('deleted: $deleted, ')
          ..write('hlc: $hlc, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    pacingJson,
    presentationJson,
    rewindWords,
    deleted,
    hlc,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredProfile &&
          other.id == this.id &&
          other.name == this.name &&
          other.pacingJson == this.pacingJson &&
          other.presentationJson == this.presentationJson &&
          other.rewindWords == this.rewindWords &&
          other.deleted == this.deleted &&
          other.hlc == this.hlc &&
          other.updatedAt == this.updatedAt);
}

class StoredProfilesCompanion extends UpdateCompanion<StoredProfile> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> pacingJson;
  final Value<String> presentationJson;
  final Value<int> rewindWords;
  final Value<bool> deleted;
  final Value<String> hlc;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const StoredProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.pacingJson = const Value.absent(),
    this.presentationJson = const Value.absent(),
    this.rewindWords = const Value.absent(),
    this.deleted = const Value.absent(),
    this.hlc = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredProfilesCompanion.insert({
    required String id,
    required String name,
    required String pacingJson,
    required String presentationJson,
    this.rewindWords = const Value.absent(),
    this.deleted = const Value.absent(),
    required String hlc,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       pacingJson = Value(pacingJson),
       presentationJson = Value(presentationJson),
       hlc = Value(hlc),
       updatedAt = Value(updatedAt);
  static Insertable<StoredProfile> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? pacingJson,
    Expression<String>? presentationJson,
    Expression<int>? rewindWords,
    Expression<bool>? deleted,
    Expression<String>? hlc,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (pacingJson != null) 'pacing_json': pacingJson,
      if (presentationJson != null) 'presentation_json': presentationJson,
      if (rewindWords != null) 'rewind_words': rewindWords,
      if (deleted != null) 'deleted': deleted,
      if (hlc != null) 'hlc': hlc,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredProfilesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? pacingJson,
    Value<String>? presentationJson,
    Value<int>? rewindWords,
    Value<bool>? deleted,
    Value<String>? hlc,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return StoredProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      pacingJson: pacingJson ?? this.pacingJson,
      presentationJson: presentationJson ?? this.presentationJson,
      rewindWords: rewindWords ?? this.rewindWords,
      deleted: deleted ?? this.deleted,
      hlc: hlc ?? this.hlc,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (pacingJson.present) {
      map['pacing_json'] = Variable<String>(pacingJson.value);
    }
    if (presentationJson.present) {
      map['presentation_json'] = Variable<String>(presentationJson.value);
    }
    if (rewindWords.present) {
      map['rewind_words'] = Variable<int>(rewindWords.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('pacingJson: $pacingJson, ')
          ..write('presentationJson: $presentationJson, ')
          ..write('rewindWords: $rewindWords, ')
          ..write('deleted: $deleted, ')
          ..write('hlc: $hlc, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PreferencesTable extends Preferences
    with TableInfo<$PreferencesTable, Preference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, hlc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<Preference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Preference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Preference(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
    );
  }

  @override
  $PreferencesTable createAlias(String alias) {
    return $PreferencesTable(attachedDatabase, alias);
  }
}

class Preference extends DataClass implements Insertable<Preference> {
  final String key;
  final String value;
  final String hlc;
  const Preference({required this.key, required this.value, required this.hlc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['hlc'] = Variable<String>(hlc);
    return map;
  }

  PreferencesCompanion toCompanion(bool nullToAbsent) {
    return PreferencesCompanion(
      key: Value(key),
      value: Value(value),
      hlc: Value(hlc),
    );
  }

  factory Preference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Preference(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      hlc: serializer.fromJson<String>(json['hlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'hlc': serializer.toJson<String>(hlc),
    };
  }

  Preference copyWith({String? key, String? value, String? hlc}) => Preference(
    key: key ?? this.key,
    value: value ?? this.value,
    hlc: hlc ?? this.hlc,
  );
  Preference copyWithCompanion(PreferencesCompanion data) {
    return Preference(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Preference(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('hlc: $hlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, hlc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Preference &&
          other.key == this.key &&
          other.value == this.value &&
          other.hlc == this.hlc);
}

class PreferencesCompanion extends UpdateCompanion<Preference> {
  final Value<String> key;
  final Value<String> value;
  final Value<String> hlc;
  final Value<int> rowid;
  const PreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.hlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PreferencesCompanion.insert({
    required String key,
    required String value,
    required String hlc,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       hlc = Value(hlc);
  static Insertable<Preference> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<String>? hlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (hlc != null) 'hlc': hlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PreferencesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<String>? hlc,
    Value<int>? rowid,
  }) {
    return PreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      hlc: hlc ?? this.hlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('hlc: $hlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxEventsTable extends OutboxEvents
    with TableInfo<$OutboxEventsTable, OutboxEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    idempotencyKey,
    entityType,
    entityId,
    payloadJson,
    deleted,
    hlc,
    createdAt,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $OutboxEventsTable createAlias(String alias) {
    return $OutboxEventsTable(attachedDatabase, alias);
  }
}

class OutboxEvent extends DataClass implements Insertable<OutboxEvent> {
  final int id;

  /// Client-generated and stable across retries. The server uses it to
  /// recognise a duplicate rather than applying an event twice when a
  /// response is lost.
  final String idempotencyKey;

  /// What changed: 'position', 'profile', 'preference', 'book_metadata'.
  final String entityType;
  final String entityId;

  /// The event body, shaped by entityType.
  final String payloadJson;

  /// Whether this event removes the entity rather than writing it. The wire
  /// format has always carried the field; nothing could set it until
  /// profiles became deletable, so the sender hardcoded false.
  final bool deleted;
  final String hlc;
  final DateTime createdAt;

  /// Incremented on each failed send. Lets a poison event be parked rather
  /// than blocking the queue behind it forever.
  final int attempts;
  final String? lastError;
  const OutboxEvent({
    required this.id,
    required this.idempotencyKey,
    required this.entityType,
    required this.entityId,
    required this.payloadJson,
    required this.deleted,
    required this.hlc,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['payload_json'] = Variable<String>(payloadJson);
    map['deleted'] = Variable<bool>(deleted);
    map['hlc'] = Variable<String>(hlc);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxEventsCompanion toCompanion(bool nullToAbsent) {
    return OutboxEventsCompanion(
      id: Value(id),
      idempotencyKey: Value(idempotencyKey),
      entityType: Value(entityType),
      entityId: Value(entityId),
      payloadJson: Value(payloadJson),
      deleted: Value(deleted),
      hlc: Value(hlc),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEvent(
      id: serializer.fromJson<int>(json['id']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      hlc: serializer.fromJson<String>(json['hlc']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'deleted': serializer.toJson<bool>(deleted),
      'hlc': serializer.toJson<String>(hlc),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxEvent copyWith({
    int? id,
    String? idempotencyKey,
    String? entityType,
    String? entityId,
    String? payloadJson,
    bool? deleted,
    String? hlc,
    DateTime? createdAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => OutboxEvent(
    id: id ?? this.id,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    payloadJson: payloadJson ?? this.payloadJson,
    deleted: deleted ?? this.deleted,
    hlc: hlc ?? this.hlc,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  OutboxEvent copyWithCompanion(OutboxEventsCompanion data) {
    return OutboxEvent(
      id: data.id.present ? data.id.value : this.id,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEvent(')
          ..write('id: $id, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('deleted: $deleted, ')
          ..write('hlc: $hlc, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    idempotencyKey,
    entityType,
    entityId,
    payloadJson,
    deleted,
    hlc,
    createdAt,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEvent &&
          other.id == this.id &&
          other.idempotencyKey == this.idempotencyKey &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.payloadJson == this.payloadJson &&
          other.deleted == this.deleted &&
          other.hlc == this.hlc &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class OutboxEventsCompanion extends UpdateCompanion<OutboxEvent> {
  final Value<int> id;
  final Value<String> idempotencyKey;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> payloadJson;
  final Value<bool> deleted;
  final Value<String> hlc;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  const OutboxEventsCompanion({
    this.id = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.deleted = const Value.absent(),
    this.hlc = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxEventsCompanion.insert({
    this.id = const Value.absent(),
    required String idempotencyKey,
    required String entityType,
    required String entityId,
    required String payloadJson,
    this.deleted = const Value.absent(),
    required String hlc,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : idempotencyKey = Value(idempotencyKey),
       entityType = Value(entityType),
       entityId = Value(entityId),
       payloadJson = Value(payloadJson),
       hlc = Value(hlc),
       createdAt = Value(createdAt);
  static Insertable<OutboxEvent> custom({
    Expression<int>? id,
    Expression<String>? idempotencyKey,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? payloadJson,
    Expression<bool>? deleted,
    Expression<String>? hlc,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (deleted != null) 'deleted': deleted,
      if (hlc != null) 'hlc': hlc,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? idempotencyKey,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? payloadJson,
    Value<bool>? deleted,
    Value<String>? hlc,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<String?>? lastError,
  }) {
    return OutboxEventsCompanion(
      id: id ?? this.id,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      payloadJson: payloadJson ?? this.payloadJson,
      deleted: deleted ?? this.deleted,
      hlc: hlc ?? this.hlc,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEventsCompanion(')
          ..write('id: $id, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('deleted: $deleted, ')
          ..write('hlc: $hlc, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $PositionConflictsTable extends PositionConflicts
    with TableInfo<$PositionConflictsTable, PositionConflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PositionConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _oursJsonMeta = const VerificationMeta(
    'oursJson',
  );
  @override
  late final GeneratedColumn<String> oursJson = GeneratedColumn<String>(
    'ours_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _theirsJsonMeta = const VerificationMeta(
    'theirsJson',
  );
  @override
  late final GeneratedColumn<String> theirsJson = GeneratedColumn<String>(
    'theirs_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    serverId,
    bookId,
    oursJson,
    theirsJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'position_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<PositionConflict> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('ours_json')) {
      context.handle(
        _oursJsonMeta,
        oursJson.isAcceptableOrUnknown(data['ours_json']!, _oursJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_oursJsonMeta);
    }
    if (data.containsKey('theirs_json')) {
      context.handle(
        _theirsJsonMeta,
        theirsJson.isAcceptableOrUnknown(data['theirs_json']!, _theirsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_theirsJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {serverId};
  @override
  PositionConflict map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PositionConflict(
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      oursJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ours_json'],
      )!,
      theirsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theirs_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PositionConflictsTable createAlias(String alias) {
    return $PositionConflictsTable(attachedDatabase, alias);
  }
}

class PositionConflict extends DataClass
    implements Insertable<PositionConflict> {
  /// The service's id for this conflict. Resolving it means telling the
  /// service which side won, so the local row is keyed by the remote id.
  final int serverId;
  final String bookId;

  /// Both candidate positions, whole, so the app can show what each one is.
  final String oursJson;
  final String theirsJson;
  final DateTime createdAt;
  const PositionConflict({
    required this.serverId,
    required this.bookId,
    required this.oursJson,
    required this.theirsJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server_id'] = Variable<int>(serverId);
    map['book_id'] = Variable<String>(bookId);
    map['ours_json'] = Variable<String>(oursJson);
    map['theirs_json'] = Variable<String>(theirsJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PositionConflictsCompanion toCompanion(bool nullToAbsent) {
    return PositionConflictsCompanion(
      serverId: Value(serverId),
      bookId: Value(bookId),
      oursJson: Value(oursJson),
      theirsJson: Value(theirsJson),
      createdAt: Value(createdAt),
    );
  }

  factory PositionConflict.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PositionConflict(
      serverId: serializer.fromJson<int>(json['serverId']),
      bookId: serializer.fromJson<String>(json['bookId']),
      oursJson: serializer.fromJson<String>(json['oursJson']),
      theirsJson: serializer.fromJson<String>(json['theirsJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'serverId': serializer.toJson<int>(serverId),
      'bookId': serializer.toJson<String>(bookId),
      'oursJson': serializer.toJson<String>(oursJson),
      'theirsJson': serializer.toJson<String>(theirsJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PositionConflict copyWith({
    int? serverId,
    String? bookId,
    String? oursJson,
    String? theirsJson,
    DateTime? createdAt,
  }) => PositionConflict(
    serverId: serverId ?? this.serverId,
    bookId: bookId ?? this.bookId,
    oursJson: oursJson ?? this.oursJson,
    theirsJson: theirsJson ?? this.theirsJson,
    createdAt: createdAt ?? this.createdAt,
  );
  PositionConflict copyWithCompanion(PositionConflictsCompanion data) {
    return PositionConflict(
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      oursJson: data.oursJson.present ? data.oursJson.value : this.oursJson,
      theirsJson: data.theirsJson.present
          ? data.theirsJson.value
          : this.theirsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PositionConflict(')
          ..write('serverId: $serverId, ')
          ..write('bookId: $bookId, ')
          ..write('oursJson: $oursJson, ')
          ..write('theirsJson: $theirsJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(serverId, bookId, oursJson, theirsJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PositionConflict &&
          other.serverId == this.serverId &&
          other.bookId == this.bookId &&
          other.oursJson == this.oursJson &&
          other.theirsJson == this.theirsJson &&
          other.createdAt == this.createdAt);
}

class PositionConflictsCompanion extends UpdateCompanion<PositionConflict> {
  final Value<int> serverId;
  final Value<String> bookId;
  final Value<String> oursJson;
  final Value<String> theirsJson;
  final Value<DateTime> createdAt;
  const PositionConflictsCompanion({
    this.serverId = const Value.absent(),
    this.bookId = const Value.absent(),
    this.oursJson = const Value.absent(),
    this.theirsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PositionConflictsCompanion.insert({
    this.serverId = const Value.absent(),
    required String bookId,
    required String oursJson,
    required String theirsJson,
    required DateTime createdAt,
  }) : bookId = Value(bookId),
       oursJson = Value(oursJson),
       theirsJson = Value(theirsJson),
       createdAt = Value(createdAt);
  static Insertable<PositionConflict> custom({
    Expression<int>? serverId,
    Expression<String>? bookId,
    Expression<String>? oursJson,
    Expression<String>? theirsJson,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (serverId != null) 'server_id': serverId,
      if (bookId != null) 'book_id': bookId,
      if (oursJson != null) 'ours_json': oursJson,
      if (theirsJson != null) 'theirs_json': theirsJson,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PositionConflictsCompanion copyWith({
    Value<int>? serverId,
    Value<String>? bookId,
    Value<String>? oursJson,
    Value<String>? theirsJson,
    Value<DateTime>? createdAt,
  }) {
    return PositionConflictsCompanion(
      serverId: serverId ?? this.serverId,
      bookId: bookId ?? this.bookId,
      oursJson: oursJson ?? this.oursJson,
      theirsJson: theirsJson ?? this.theirsJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (oursJson.present) {
      map['ours_json'] = Variable<String>(oursJson.value);
    }
    if (theirsJson.present) {
      map['theirs_json'] = Variable<String>(theirsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PositionConflictsCompanion(')
          ..write('serverId: $serverId, ')
          ..write('bookId: $bookId, ')
          ..write('oursJson: $oursJson, ')
          ..write('theirsJson: $theirsJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $ReadingPositionsTable readingPositions = $ReadingPositionsTable(
    this,
  );
  late final $PendingPositionsTable pendingPositions = $PendingPositionsTable(
    this,
  );
  late final $StoredProfilesTable storedProfiles = $StoredProfilesTable(this);
  late final $PreferencesTable preferences = $PreferencesTable(this);
  late final $OutboxEventsTable outboxEvents = $OutboxEventsTable(this);
  late final $PositionConflictsTable positionConflicts =
      $PositionConflictsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    readingPositions,
    pendingPositions,
    storedProfiles,
    preferences,
    outboxEvents,
    positionConflicts,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('reading_positions', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      required String id,
      required String title,
      Value<String?> author,
      Value<String?> language,
      required Uint8List bytes,
      required DateTime importedAt,
      Value<int> wordCount,
      Value<int> rowid,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> author,
      Value<String?> language,
      Value<Uint8List> bytes,
      Value<DateTime> importedAt,
      Value<int> wordCount,
      Value<int> rowid,
    });

final class $$BooksTableReferences
    extends BaseReferences<_$AppDatabase, $BooksTable, Book> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ReadingPositionsTable, List<ReadingPosition>>
  _readingPositionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.readingPositions,
    aliasName: 'books__id__reading_positions__book_id',
  );

  $$ReadingPositionsTableProcessedTableManager get readingPositionsRefs {
    final manager = $$ReadingPositionsTableTableManager(
      $_db,
      $_db.readingPositions,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingPositionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> readingPositionsRefs(
    Expression<bool> Function($$ReadingPositionsTableFilterComposer f) f,
  ) {
    final $$ReadingPositionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingPositions,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingPositionsTableFilterComposer(
            $db: $db,
            $table: $db.readingPositions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wordCount => $composableBuilder(
    column: $table.wordCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wordCount =>
      $composableBuilder(column: $table.wordCount, builder: (column) => column);

  Expression<T> readingPositionsRefs<T extends Object>(
    Expression<T> Function($$ReadingPositionsTableAnnotationComposer a) f,
  ) {
    final $$ReadingPositionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingPositions,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingPositionsTableAnnotationComposer(
            $db: $db,
            $table: $db.readingPositions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          Book,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (Book, $$BooksTableReferences),
          Book,
          PrefetchHooks Function({bool readingPositionsRefs})
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<DateTime> importedAt = const Value.absent(),
                Value<int> wordCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                author: author,
                language: language,
                bytes: bytes,
                importedAt: importedAt,
                wordCount: wordCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> author = const Value.absent(),
                Value<String?> language = const Value.absent(),
                required Uint8List bytes,
                required DateTime importedAt,
                Value<int> wordCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                author: author,
                language: language,
                bytes: bytes,
                importedAt: importedAt,
                wordCount: wordCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$BooksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({readingPositionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (readingPositionsRefs) db.readingPositions,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (readingPositionsRefs)
                    await $_getPrefetchedData<
                      Book,
                      $BooksTable,
                      ReadingPosition
                    >(
                      currentTable: table,
                      referencedTable: $$BooksTableReferences
                          ._readingPositionsRefsTable(db),
                      managerFromTypedResult: (p0) => $$BooksTableReferences(
                        db,
                        table,
                        p0,
                      ).readingPositionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.bookId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      Book,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (Book, $$BooksTableReferences),
      Book,
      PrefetchHooks Function({bool readingPositionsRefs})
    >;
typedef $$ReadingPositionsTableCreateCompanionBuilder =
    ReadingPositionsCompanion Function({
      required String bookId,
      required String blockId,
      required int charOffset,
      required int parserVersion,
      Value<int?> tokenIndex,
      required String hlc,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReadingPositionsTableUpdateCompanionBuilder =
    ReadingPositionsCompanion Function({
      Value<String> bookId,
      Value<String> blockId,
      Value<int> charOffset,
      Value<int> parserVersion,
      Value<int?> tokenIndex,
      Value<String> hlc,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ReadingPositionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ReadingPositionsTable, ReadingPosition> {
  $$ReadingPositionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('reading_positions__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingPositionsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingPositionsTable> {
  $$ReadingPositionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get blockId => $composableBuilder(
    column: $table.blockId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tokenIndex => $composableBuilder(
    column: $table.tokenIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingPositionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingPositionsTable> {
  $$ReadingPositionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get blockId => $composableBuilder(
    column: $table.blockId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tokenIndex => $composableBuilder(
    column: $table.tokenIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingPositionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingPositionsTable> {
  $$ReadingPositionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get blockId =>
      $composableBuilder(column: $table.blockId, builder: (column) => column);

  GeneratedColumn<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tokenIndex => $composableBuilder(
    column: $table.tokenIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingPositionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingPositionsTable,
          ReadingPosition,
          $$ReadingPositionsTableFilterComposer,
          $$ReadingPositionsTableOrderingComposer,
          $$ReadingPositionsTableAnnotationComposer,
          $$ReadingPositionsTableCreateCompanionBuilder,
          $$ReadingPositionsTableUpdateCompanionBuilder,
          (ReadingPosition, $$ReadingPositionsTableReferences),
          ReadingPosition,
          PrefetchHooks Function({bool bookId})
        > {
  $$ReadingPositionsTableTableManager(
    _$AppDatabase db,
    $ReadingPositionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingPositionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingPositionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingPositionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> blockId = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                Value<int?> tokenIndex = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingPositionsCompanion(
                bookId: bookId,
                blockId: blockId,
                charOffset: charOffset,
                parserVersion: parserVersion,
                tokenIndex: tokenIndex,
                hlc: hlc,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String blockId,
                required int charOffset,
                required int parserVersion,
                Value<int?> tokenIndex = const Value.absent(),
                required String hlc,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReadingPositionsCompanion.insert(
                bookId: bookId,
                blockId: blockId,
                charOffset: charOffset,
                parserVersion: parserVersion,
                tokenIndex: tokenIndex,
                hlc: hlc,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReadingPositionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable:
                                    $$ReadingPositionsTableReferences
                                        ._bookIdTable(db),
                                referencedColumn:
                                    $$ReadingPositionsTableReferences
                                        ._bookIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReadingPositionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingPositionsTable,
      ReadingPosition,
      $$ReadingPositionsTableFilterComposer,
      $$ReadingPositionsTableOrderingComposer,
      $$ReadingPositionsTableAnnotationComposer,
      $$ReadingPositionsTableCreateCompanionBuilder,
      $$ReadingPositionsTableUpdateCompanionBuilder,
      (ReadingPosition, $$ReadingPositionsTableReferences),
      ReadingPosition,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$PendingPositionsTableCreateCompanionBuilder =
    PendingPositionsCompanion Function({
      required String bookId,
      required String blockId,
      required int charOffset,
      required int parserVersion,
      Value<int?> tokenIndex,
      required String hlc,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PendingPositionsTableUpdateCompanionBuilder =
    PendingPositionsCompanion Function({
      Value<String> bookId,
      Value<String> blockId,
      Value<int> charOffset,
      Value<int> parserVersion,
      Value<int?> tokenIndex,
      Value<String> hlc,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PendingPositionsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingPositionsTable> {
  $$PendingPositionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockId => $composableBuilder(
    column: $table.blockId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tokenIndex => $composableBuilder(
    column: $table.tokenIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingPositionsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingPositionsTable> {
  $$PendingPositionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockId => $composableBuilder(
    column: $table.blockId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tokenIndex => $composableBuilder(
    column: $table.tokenIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingPositionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingPositionsTable> {
  $$PendingPositionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get blockId =>
      $composableBuilder(column: $table.blockId, builder: (column) => column);

  GeneratedColumn<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parserVersion => $composableBuilder(
    column: $table.parserVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tokenIndex => $composableBuilder(
    column: $table.tokenIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PendingPositionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingPositionsTable,
          PendingPosition,
          $$PendingPositionsTableFilterComposer,
          $$PendingPositionsTableOrderingComposer,
          $$PendingPositionsTableAnnotationComposer,
          $$PendingPositionsTableCreateCompanionBuilder,
          $$PendingPositionsTableUpdateCompanionBuilder,
          (
            PendingPosition,
            BaseReferences<
              _$AppDatabase,
              $PendingPositionsTable,
              PendingPosition
            >,
          ),
          PendingPosition,
          PrefetchHooks Function()
        > {
  $$PendingPositionsTableTableManager(
    _$AppDatabase db,
    $PendingPositionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingPositionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingPositionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingPositionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> blockId = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<int> parserVersion = const Value.absent(),
                Value<int?> tokenIndex = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingPositionsCompanion(
                bookId: bookId,
                blockId: blockId,
                charOffset: charOffset,
                parserVersion: parserVersion,
                tokenIndex: tokenIndex,
                hlc: hlc,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String blockId,
                required int charOffset,
                required int parserVersion,
                Value<int?> tokenIndex = const Value.absent(),
                required String hlc,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PendingPositionsCompanion.insert(
                bookId: bookId,
                blockId: blockId,
                charOffset: charOffset,
                parserVersion: parserVersion,
                tokenIndex: tokenIndex,
                hlc: hlc,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingPositionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingPositionsTable,
      PendingPosition,
      $$PendingPositionsTableFilterComposer,
      $$PendingPositionsTableOrderingComposer,
      $$PendingPositionsTableAnnotationComposer,
      $$PendingPositionsTableCreateCompanionBuilder,
      $$PendingPositionsTableUpdateCompanionBuilder,
      (
        PendingPosition,
        BaseReferences<_$AppDatabase, $PendingPositionsTable, PendingPosition>,
      ),
      PendingPosition,
      PrefetchHooks Function()
    >;
typedef $$StoredProfilesTableCreateCompanionBuilder =
    StoredProfilesCompanion Function({
      required String id,
      required String name,
      required String pacingJson,
      required String presentationJson,
      Value<int> rewindWords,
      Value<bool> deleted,
      required String hlc,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$StoredProfilesTableUpdateCompanionBuilder =
    StoredProfilesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> pacingJson,
      Value<String> presentationJson,
      Value<int> rewindWords,
      Value<bool> deleted,
      Value<String> hlc,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$StoredProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $StoredProfilesTable> {
  $$StoredProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pacingJson => $composableBuilder(
    column: $table.pacingJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get presentationJson => $composableBuilder(
    column: $table.presentationJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rewindWords => $composableBuilder(
    column: $table.rewindWords,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $StoredProfilesTable> {
  $$StoredProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pacingJson => $composableBuilder(
    column: $table.pacingJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get presentationJson => $composableBuilder(
    column: $table.presentationJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rewindWords => $composableBuilder(
    column: $table.rewindWords,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $StoredProfilesTable> {
  $$StoredProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get pacingJson => $composableBuilder(
    column: $table.pacingJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get presentationJson => $composableBuilder(
    column: $table.presentationJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rewindWords => $composableBuilder(
    column: $table.rewindWords,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StoredProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StoredProfilesTable,
          StoredProfile,
          $$StoredProfilesTableFilterComposer,
          $$StoredProfilesTableOrderingComposer,
          $$StoredProfilesTableAnnotationComposer,
          $$StoredProfilesTableCreateCompanionBuilder,
          $$StoredProfilesTableUpdateCompanionBuilder,
          (
            StoredProfile,
            BaseReferences<_$AppDatabase, $StoredProfilesTable, StoredProfile>,
          ),
          StoredProfile,
          PrefetchHooks Function()
        > {
  $$StoredProfilesTableTableManager(
    _$AppDatabase db,
    $StoredProfilesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> pacingJson = const Value.absent(),
                Value<String> presentationJson = const Value.absent(),
                Value<int> rewindWords = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredProfilesCompanion(
                id: id,
                name: name,
                pacingJson: pacingJson,
                presentationJson: presentationJson,
                rewindWords: rewindWords,
                deleted: deleted,
                hlc: hlc,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String pacingJson,
                required String presentationJson,
                Value<int> rewindWords = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required String hlc,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => StoredProfilesCompanion.insert(
                id: id,
                name: name,
                pacingJson: pacingJson,
                presentationJson: presentationJson,
                rewindWords: rewindWords,
                deleted: deleted,
                hlc: hlc,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StoredProfilesTable,
      StoredProfile,
      $$StoredProfilesTableFilterComposer,
      $$StoredProfilesTableOrderingComposer,
      $$StoredProfilesTableAnnotationComposer,
      $$StoredProfilesTableCreateCompanionBuilder,
      $$StoredProfilesTableUpdateCompanionBuilder,
      (
        StoredProfile,
        BaseReferences<_$AppDatabase, $StoredProfilesTable, StoredProfile>,
      ),
      StoredProfile,
      PrefetchHooks Function()
    >;
typedef $$PreferencesTableCreateCompanionBuilder =
    PreferencesCompanion Function({
      required String key,
      required String value,
      required String hlc,
      Value<int> rowid,
    });
typedef $$PreferencesTableUpdateCompanionBuilder =
    PreferencesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<String> hlc,
      Value<int> rowid,
    });

class $$PreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);
}

class $$PreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PreferencesTable,
          Preference,
          $$PreferencesTableFilterComposer,
          $$PreferencesTableOrderingComposer,
          $$PreferencesTableAnnotationComposer,
          $$PreferencesTableCreateCompanionBuilder,
          $$PreferencesTableUpdateCompanionBuilder,
          (
            Preference,
            BaseReferences<_$AppDatabase, $PreferencesTable, Preference>,
          ),
          Preference,
          PrefetchHooks Function()
        > {
  $$PreferencesTableTableManager(_$AppDatabase db, $PreferencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PreferencesCompanion(
                key: key,
                value: value,
                hlc: hlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required String hlc,
                Value<int> rowid = const Value.absent(),
              }) => PreferencesCompanion.insert(
                key: key,
                value: value,
                hlc: hlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PreferencesTable,
      Preference,
      $$PreferencesTableFilterComposer,
      $$PreferencesTableOrderingComposer,
      $$PreferencesTableAnnotationComposer,
      $$PreferencesTableCreateCompanionBuilder,
      $$PreferencesTableUpdateCompanionBuilder,
      (
        Preference,
        BaseReferences<_$AppDatabase, $PreferencesTable, Preference>,
      ),
      Preference,
      PrefetchHooks Function()
    >;
typedef $$OutboxEventsTableCreateCompanionBuilder =
    OutboxEventsCompanion Function({
      Value<int> id,
      required String idempotencyKey,
      required String entityType,
      required String entityId,
      required String payloadJson,
      Value<bool> deleted,
      required String hlc,
      required DateTime createdAt,
      Value<int> attempts,
      Value<String?> lastError,
    });
typedef $$OutboxEventsTableUpdateCompanionBuilder =
    OutboxEventsCompanion Function({
      Value<int> id,
      Value<String> idempotencyKey,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> payloadJson,
      Value<bool> deleted,
      Value<String> hlc,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<String?> lastError,
    });

class $$OutboxEventsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxEventsTable> {
  $$OutboxEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxEventsTable> {
  $$OutboxEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxEventsTable> {
  $$OutboxEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxEventsTable,
          OutboxEvent,
          $$OutboxEventsTableFilterComposer,
          $$OutboxEventsTableOrderingComposer,
          $$OutboxEventsTableAnnotationComposer,
          $$OutboxEventsTableCreateCompanionBuilder,
          $$OutboxEventsTableUpdateCompanionBuilder,
          (
            OutboxEvent,
            BaseReferences<_$AppDatabase, $OutboxEventsTable, OutboxEvent>,
          ),
          OutboxEvent,
          PrefetchHooks Function()
        > {
  $$OutboxEventsTableTableManager(_$AppDatabase db, $OutboxEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxEventsCompanion(
                id: id,
                idempotencyKey: idempotencyKey,
                entityType: entityType,
                entityId: entityId,
                payloadJson: payloadJson,
                deleted: deleted,
                hlc: hlc,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String idempotencyKey,
                required String entityType,
                required String entityId,
                required String payloadJson,
                Value<bool> deleted = const Value.absent(),
                required String hlc,
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => OutboxEventsCompanion.insert(
                id: id,
                idempotencyKey: idempotencyKey,
                entityType: entityType,
                entityId: entityId,
                payloadJson: payloadJson,
                deleted: deleted,
                hlc: hlc,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxEventsTable,
      OutboxEvent,
      $$OutboxEventsTableFilterComposer,
      $$OutboxEventsTableOrderingComposer,
      $$OutboxEventsTableAnnotationComposer,
      $$OutboxEventsTableCreateCompanionBuilder,
      $$OutboxEventsTableUpdateCompanionBuilder,
      (
        OutboxEvent,
        BaseReferences<_$AppDatabase, $OutboxEventsTable, OutboxEvent>,
      ),
      OutboxEvent,
      PrefetchHooks Function()
    >;
typedef $$PositionConflictsTableCreateCompanionBuilder =
    PositionConflictsCompanion Function({
      Value<int> serverId,
      required String bookId,
      required String oursJson,
      required String theirsJson,
      required DateTime createdAt,
    });
typedef $$PositionConflictsTableUpdateCompanionBuilder =
    PositionConflictsCompanion Function({
      Value<int> serverId,
      Value<String> bookId,
      Value<String> oursJson,
      Value<String> theirsJson,
      Value<DateTime> createdAt,
    });

class $$PositionConflictsTableFilterComposer
    extends Composer<_$AppDatabase, $PositionConflictsTable> {
  $$PositionConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get oursJson => $composableBuilder(
    column: $table.oursJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get theirsJson => $composableBuilder(
    column: $table.theirsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PositionConflictsTableOrderingComposer
    extends Composer<_$AppDatabase, $PositionConflictsTable> {
  $$PositionConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get oursJson => $composableBuilder(
    column: $table.oursJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get theirsJson => $composableBuilder(
    column: $table.theirsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PositionConflictsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PositionConflictsTable> {
  $$PositionConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get oursJson =>
      $composableBuilder(column: $table.oursJson, builder: (column) => column);

  GeneratedColumn<String> get theirsJson => $composableBuilder(
    column: $table.theirsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PositionConflictsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PositionConflictsTable,
          PositionConflict,
          $$PositionConflictsTableFilterComposer,
          $$PositionConflictsTableOrderingComposer,
          $$PositionConflictsTableAnnotationComposer,
          $$PositionConflictsTableCreateCompanionBuilder,
          $$PositionConflictsTableUpdateCompanionBuilder,
          (
            PositionConflict,
            BaseReferences<
              _$AppDatabase,
              $PositionConflictsTable,
              PositionConflict
            >,
          ),
          PositionConflict,
          PrefetchHooks Function()
        > {
  $$PositionConflictsTableTableManager(
    _$AppDatabase db,
    $PositionConflictsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PositionConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PositionConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PositionConflictsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> serverId = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> oursJson = const Value.absent(),
                Value<String> theirsJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PositionConflictsCompanion(
                serverId: serverId,
                bookId: bookId,
                oursJson: oursJson,
                theirsJson: theirsJson,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> serverId = const Value.absent(),
                required String bookId,
                required String oursJson,
                required String theirsJson,
                required DateTime createdAt,
              }) => PositionConflictsCompanion.insert(
                serverId: serverId,
                bookId: bookId,
                oursJson: oursJson,
                theirsJson: theirsJson,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PositionConflictsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PositionConflictsTable,
      PositionConflict,
      $$PositionConflictsTableFilterComposer,
      $$PositionConflictsTableOrderingComposer,
      $$PositionConflictsTableAnnotationComposer,
      $$PositionConflictsTableCreateCompanionBuilder,
      $$PositionConflictsTableUpdateCompanionBuilder,
      (
        PositionConflict,
        BaseReferences<
          _$AppDatabase,
          $PositionConflictsTable,
          PositionConflict
        >,
      ),
      PositionConflict,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$ReadingPositionsTableTableManager get readingPositions =>
      $$ReadingPositionsTableTableManager(_db, _db.readingPositions);
  $$PendingPositionsTableTableManager get pendingPositions =>
      $$PendingPositionsTableTableManager(_db, _db.pendingPositions);
  $$StoredProfilesTableTableManager get storedProfiles =>
      $$StoredProfilesTableTableManager(_db, _db.storedProfiles);
  $$PreferencesTableTableManager get preferences =>
      $$PreferencesTableTableManager(_db, _db.preferences);
  $$OutboxEventsTableTableManager get outboxEvents =>
      $$OutboxEventsTableTableManager(_db, _db.outboxEvents);
  $$PositionConflictsTableTableManager get positionConflicts =>
      $$PositionConflictsTableTableManager(_db, _db.positionConflicts);
}
