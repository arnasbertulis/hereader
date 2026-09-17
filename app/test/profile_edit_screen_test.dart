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

  testWidgets('a preset opens in an editable TextField already', (
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

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Standard',
    );
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

  testWidgets(
    'the first change to a preset forks it, activates the fork, and offers '
    'Undo',
    (tester) async {
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

      await tester.enterText(find.byType(TextField), 'My Standard');
      await tester.pumpAndSettle();

      expect(find.text('Now reading with My Standard'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      final mine = (await repository.allProfiles())
          .where((p) => !p.isBuiltIn)
          .toList();
      expect(mine, hasLength(1));
      expect(mine.single.name, 'My Standard');
      expect((await repository.activeProfile()).id, mine.single.id);
    },
  );

  testWidgets(
    'a later change in the same session edits the fork rather than forking '
    'again',
    (tester) async {
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

      await tester.enterText(find.byType(TextField), 'My Standard');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'My Standard, tuned');
      await tester.pumpAndSettle();

      final mine = (await repository.allProfiles())
          .where((p) => !p.isBuiltIn)
          .toList();
      expect(mine, hasLength(1));
    },
  );

  testWidgets(
    'returning to the preset in a fresh editor forks anew, never reusing '
    'the earlier fork',
    (tester) async {
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

      await tester.enterText(find.byType(TextField), 'My Standard');
      await tester.pumpAndSettle();

      // Tear the first editor down so the second pump below creates a fresh
      // State — a real second visit through Navigator would too — rather
      // than Flutter's widget-tree diffing reusing the same State (and its
      // already-forked `_draft`) because both pumps place a
      // ProfileEditScreen at the same tree position.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));

      // A second, independent visit to the same preset — not the fork just
      // made.
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

      await tester.enterText(find.byType(TextField), 'My Standard, again');
      await tester.pumpAndSettle();

      final mine = (await repository.allProfiles())
          .where((p) => !p.isBuiltIn)
          .toList();
      expect(mine, hasLength(2));
    },
  );

  testWidgets('Undo deletes the fork and restores the preset as active', (
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

    await tester.enterText(find.byType(TextField), 'My Standard');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final mine = (await repository.allProfiles())
        .where((p) => !p.isBuiltIn)
        .toList();
    expect(mine, isEmpty);
    expect((await repository.activeProfile()).id, Presets.standard.id);
  });

  testWidgets(
    'dragging a slider on a locked preset forks exactly once per gesture',
    (tester) async {
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

      // The reading speed slider — first `Slider` on the screen, and the
      // one #491 was filed against. Named rather than left to the default:
      // the name field builds an `EditableText` with a `Scrollable` of its
      // own, so the default matches two. The list is the outer one, so it
      // comes first.
      // `find.byType(Slider)` rather than `.first`: `scrollUntilVisible`
      // checks its finder for emptiness, and `.first` throws instead of
      // reporting empty. The reading speed slider is the first one to enter
      // the cache extent as the list scrolls down, so this still targets it.
      await tester.scrollUntilVisible(
        find.byType(Slider),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // `scrollUntilVisible` stops as soon as the slider is built, which
      // can leave it short of fully on screen; `ensureVisible` re-centres
      // it so `getCenter` below lands on it.
      await tester.ensureVisible(find.byType(Slider).first);
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Slider).first),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final mine = (await repository.allProfiles())
          .where((p) => !p.isBuiltIn)
          .toList();
      expect(
        mine,
        hasLength(1),
        reason:
            'One continuous drag should fork once, not once per '
            'intermediate value dragged across',
      );
    },
  );
}
