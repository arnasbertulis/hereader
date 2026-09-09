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
    testWidgets('forks the preset and activates the fork', (tester) async {
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

    testWidgets('keeps the fork active once the editor closes', (tester) async {
      final context = await harness(tester);

      final future = actions.duplicate(context, Presets.standard);
      await tester.pumpAndSettle();
      final forkId = (await repository.activeProfile()).id;

      await tester.pageBack();
      await tester.pumpAndSettle();
      await future;

      expect((await repository.activeProfile()).id, forkId);
    });

    testWidgets('announces the switch with an undo once the editor closes', (
      tester,
    ) async {
      final context = await harness(tester);

      final future = actions.duplicate(context, Presets.standard);
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      await future;

      expect(
        find.text('Now reading with ${Presets.standard.name} (copy)'),
        findsOneWidget,
      );
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('undo restores whichever profile was active before', (
      tester,
    ) async {
      final context = await harness(tester);
      final outgoingId = (await repository.activeProfile()).id;

      final future = actions.duplicate(context, Presets.standard);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await future;

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect((await repository.activeProfile()).id, outgoingId);
    });

    testWidgets(
      'undo restores the pre-duplicate profile even if the editor forked '
      'again',
      (tester) async {
        final context = await harness(tester);
        final outgoingId = (await repository.activeProfile()).id;

        final future = actions.duplicate(context, Presets.standard);
        await tester.pumpAndSettle();

        // The editor forks again and pops with its own fork, the way
        // editing a preset always does. ProfileEditScreen saves the fork
        // before popping with it; do the same here.
        final refork = Presets.standard.fork(id: ReadingProfile.newId());
        await repository.saveProfile(refork, hlc: await _stamp());
        Navigator.of(context).pop(refork);
        await tester.pumpAndSettle();
        await future;

        expect((await repository.activeProfile()).id, refork.id);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        expect((await repository.activeProfile()).id, outgoingId);
      },
    );
  });

  group('ProfileActions.delete', () {
    Future<ReadingProfile> savedFork() async {
      final profile = Presets.standard.fork(id: ReadingProfile.newId());
      await repository.saveProfile(profile, hlc: await _stamp());
      return profile;
    }

    testWidgets('signed in: states the copy reaches every device', (
      tester,
    ) async {
      final context = await harness(tester);
      final profile = await savedFork();

      unawaited(actions.delete(context, profile, signedIn: true));
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

    testWidgets('signed out: states the removal is local to this device', (
      tester,
    ) async {
      final context = await harness(tester);
      final profile = await savedFork();

      unawaited(actions.delete(context, profile, signedIn: false));
      await tester.pumpAndSettle();

      expect(find.text('Delete ${profile.name}?'), findsOneWidget);
      expect(
        find.text(
          'This removes it from this device. Presets are not '
          'affected.',
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

      final future = actions.delete(context, profile, signedIn: true);
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

      final future = actions.delete(context, profile, signedIn: true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await future, isTrue);
      final saved = await repository.allProfiles();
      expect(saved.any((p) => p.id == profile.id), isFalse);
    });
  });
}
