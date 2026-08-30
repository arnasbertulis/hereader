import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/database.dart' as db;
import 'package:app/data/library_repository.dart';
import 'package:app/reading/library_book.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/position_conflict_sheet.dart';
import 'package:app/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'fakes.dart';
import 'test_database.dart';

String _payload(Locator locator) => jsonEncode({
  'blockId': locator.blockId,
  'charOffset': locator.charOffset,
  'parserVersion': locator.parserVersion,
});

void main() {
  late db.AppDatabase database;
  late LibraryRepository repository;
  late AuthStore auth;
  late FakeApi api;
  late SyncEngine sync;

  setUp(() async {
    database = db.AppDatabase(testExecutor());
    repository = LibraryRepository(database);

    auth = AuthStore(storage: FakeSecureStorage());
    await auth.save(
      const Session(accessToken: 'access', refreshToken: 'refresh'),
    );

    api = FakeApi(auth: auth);
    sync = SyncEngine(
      repository: repository,
      api: api,
      auth: auth,
      database: database,
    );
    await sync.start();
  });

  tearDown(() async {
    sync.dispose();
    api.dispose();
    auth.dispose();
    await database.close();
  });

  testWidgets('the last word of a short note reads 100% through, not 95%', (
    tester,
  ) async {
    // A 20-token note: the last word sits at tokenIndex 19, the "index of
    // the last word seen" that _Candidate.progress has to turn into a
    // token *count* of 20, not 19, to read 100%.
    const wordCount = 20;
    final text = TokenizedText.from([
      (id: 'block-0', text: List.filled(wordCount, 'word').join(' ')),
    ], parserVersion: 1);

    final book = LibraryBook(
      id: 'note-1',
      title: 'A Note',
      text: text,
      sourceFormat: BookSourceFormat.note,
    );

    await repository.addBook(book, Uint8List(0));

    final conflict = db.PositionConflict(
      serverId: 1,
      bookId: 'note-1',
      oursJson: _payload(text.locatorAt(19)!),
      theirsJson: _payload(text.locatorAt(5)!),
      createdAt: DateTime.utc(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PositionConflictSheet(
            conflict: conflict,
            bookTitle: 'A Note',
            repository: repository,
            sync: sync,
            bookImporter: StubBookImporter(book),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // tokenIndex 19 of 20 is the last word: (19 + 1) / 20 = 100%.
    expect(find.text('100% through'), findsOneWidget);
    // tokenIndex 5 of 20, for contrast: (5 + 1) / 20 = 30%.
    expect(find.text('30% through'), findsOneWidget);
  });
}
