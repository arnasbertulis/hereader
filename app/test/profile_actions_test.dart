import 'dart:async';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/profile_actions.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

Future<String> _stamp() async => '0000000000001-00000-test';

void main() {
  late AppDatabase database;
  late LibraryRepository repository;
  late ProfileActions actions;

  setUp(() {
    database = AppDatabase(testExecutor());
    repository = LibraryRepository(database);
    actions = ProfileActions(repository: repository, issueStamp: _stamp);
  });

  tearDown(() => database.close());

  // A Builder above a Navigator, nothing else — neither ReaderScreen nor
  // ProfilesScreen is pumped. duplicate() and delete() supply their own
  // navigation and dialogs from the context this hands them.
  Future<BuildContext> harness(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const Scaffold();
          },
        ),
      ),
    );
    return captured;
  }

  group('ProfileActions.duplicate', () {
    testWidgets('forks and activates the source before the editor opens', (
      tester,
    ) async {
      final context = await harness(tester);

      final future = actions.duplicate(context, Presets.standard);
      await tester.pumpAndSettle();

      final saved = await repository.allProfiles();
      final mine = saved.where((p) => !p.isBuiltIn).toList();
      expect(mine, hasLength(1));
      expect((await repository.activeProfile()).id, mine.single.id);
      expect(find.byType(ProfileEditScreen), findsOneWidget);

      // Close the editor without forking again so the pending future
      // resolves.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await future;
    });

    testWidgets('leaves the fork active once the editor closes unforked', (
      tester,
    ) async {
      final context = await harness(tester);

      final future = actions.duplicate(context, Presets.standard);
      await tester.pumpAndSettle();
      final forkId = (await repository.activeProfile()).id;

      await tester.pageBack();
      await tester.pumpAndSettle();
      await future;

      expect((await repository.activeProfile()).id, forkId);
    });
  });

  group('ProfileActions.delete', () {
    Future<ReadingProfile> savedFork() async {
      final profile = Presets.standard.fork(id: ReadingProfile.newId());
      await repository.saveProfile(profile, hlc: await _stamp());
      return profile;
    }

    testWidgets('shows the shared confirmation copy', (tester) async {
      final context = await harness(tester);
      final profile = await savedFork();

      unawaited(actions.delete(context, profile));
      await tester.pumpAndSettle();

      expect(find.text('Delete ${profile.name}?'), findsOneWidget);
      expect(
        find.text(
          'This removes it from every device signed in to your account. '
          'Presets are not affected.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
    });

    testWidgets('keeps the profile and returns false when not confirmed', (
      tester,
    ) async {
      final context = await harness(tester);
      final profile = await savedFork();

      final future = actions.delete(context, profile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(await future, isFalse);
      final saved = await repository.allProfiles();
      expect(saved.any((p) => p.id == profile.id), isTrue);
    });

    testWidgets('deletes the profile and returns true when confirmed', (
      tester,
    ) async {
      final context = await harness(tester);
      final profile = await savedFork();

      final future = actions.delete(context, profile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await future, isTrue);
      final saved = await repository.allProfiles();
      expect(saved.any((p) => p.id == profile.id), isFalse);
    });
  });
}
