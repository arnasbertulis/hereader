import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

void main() {
  late AppDatabase database;
  late LibraryRepository repository;
  late int stamps;

  Future<String> issueStamp() async {
    stamps++;
    return '000000000000$stamps-00000-test';
  }

  setUp(() {
    database = AppDatabase(testExecutor());
    repository = LibraryRepository(database);
    stamps = 0;
  });

  tearDown(() => database.close());

  testWidgets('a preset draws its name as text, not a TextField', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditScreen(
          profile: Presets.standard,
          repository: repository,
          issueStamp: issueStamp,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Standard'), findsOneWidget);
  });

  testWidgets('a fork still draws its name in an editable TextField', (
    tester,
  ) async {
    final fork = Presets.standard.copyWith(
      id: 'user-profile-1',
      name: 'My reading profile',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditScreen(
          profile: fork,
          repository: repository,
          issueStamp: issueStamp,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'My reading profile',
    );
  });
}
