import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/info_dot.dart';
import 'package:app/reading/profile_actions.dart';
import 'package:app/reading/profile_file.dart';
import 'package:app/reading/profile_row.dart';
import 'package:app/reading/profiles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late LibraryRepository repository;
  late int stamps;

  Future<String> issueStamp() async {
    stamps++;
    return '000000000000$stamps-00000-test';
  }

  setUp(() {
    db = AppDatabase(testExecutor());
    repository = LibraryRepository(db);
    stamps = 0;
  });

  tearDown(() => db.close());

  Finder infoDotFor(String semanticLabel) => find.byWidgetPredicate(
    (w) => w is InfoDot && w.semanticLabel == semanticLabel,
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    PickProfileBytes pick = pickProfileFile,
    SaveProfileBytes save = saveProfileFile,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilesScreen(
          repository: repository,
          issueStamp: issueStamp,
          pickProfileBytes: pick,
          saveProfileBytes: save,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The Drift stream subscriptions `watchActiveProfile`/`watchProfiles`
  // leave a Timer scheduled; unmounting and pumping past it here is what
  // clears it before teardown, or the framework reports a leaked timer —
  // see .claude/rules/app.md and home_screen_test.dart's `_disposeTree`.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('Your profiles', () {
    testWidgets('prints no explanation by default, only the (i)', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(
        find.textContaining('Your profiles follow you between devices'),
        findsNothing,
      );
      expect(infoDotFor('About your profiles'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('reveals the explanation on tap', (tester) async {
      await pumpScreen(tester);

      await tester.tap(infoDotFor('About your profiles'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Your profiles follow you between devices'),
        findsOneWidget,
      );

      await disposeTree(tester);
    });
  });

  group('profile files', () {
    const evening = ReadingProfile(
      id: 'p.1.aaaaaaaa',
      name: 'Evening',
      pacing: PacingConfig(baseWpm: 410),
      rewindWords: 5,
    );

    Future<void> seed(ReadingProfile profile) =>
        repository.saveProfile(profile, hlc: '0000000000001-00000-seed');

    Uint8List fileNamed(String name) => Uint8List.fromList(
      utf8.encode(
        '{"format":"hereader.profile","version":1,'
        '"profile":{"name":"$name","pacing":{"baseWpm":300}}}',
      ),
    );

    Future<void> openMenu(WidgetTester tester, String profileId) async {
      await tester.ensureVisible(find.byKey(profileRowMenuKey(profileId)));
      await tester.tap(find.byKey(profileRowMenuKey(profileId)));
      await tester.pumpAndSettle();
    }

    Future<List<ReadingProfile>> stored() async => [
      for (final p in await repository.allProfiles())
        if (!p.isBuiltIn) p,
    ];

    testWidgets('Save as file hands the saver the name and the settings', (
      tester,
    ) async {
      await seed(evening);
      String? savedName;
      Uint8List? savedBytes;
      await pumpScreen(
        tester,
        save: (name, bytes) async {
          savedName = name;
          savedBytes = bytes;
        },
      );

      await openMenu(tester, evening.id);
      await tester.tap(find.byKey(profileExportItemKey));
      await tester.pumpAndSettle();

      expect(savedName, 'Evening.hereader-profile.json');
      final root = jsonDecode(utf8.decode(savedBytes!)) as Map<String, dynamic>;
      expect(root['format'], 'hereader.profile');
      expect(root['version'], 1);
      final profile = root['profile'] as Map<String, dynamic>;
      expect(profile['name'], 'Evening');
      expect(profile['rewindWords'], 5);
      expect(profile.containsKey('id'), isFalse);

      await disposeTree(tester);
    });

    testWidgets('a Preset can be saved as a file too', (tester) async {
      String? savedName;
      await pumpScreen(tester, save: (name, bytes) async => savedName = name);

      await openMenu(tester, Presets.standard.id);
      await tester.tap(find.byKey(profileExportItemKey));
      await tester.pumpAndSettle();

      expect(savedName, '${Presets.standard.name}.hereader-profile.json');

      await disposeTree(tester);
    });

    testWidgets('importing stores one new profile, activates it and offers '
        'an undo', (tester) async {
      await pumpScreen(tester, pick: () async => fileNamed('From a friend'));

      await tester.tap(find.byKey(profileImportButtonKey));
      await tester.pumpAndSettle();

      final mine = await stored();
      expect(mine, hasLength(1));
      expect(mine.single.name, 'From a friend');
      expect(mine.single.pacing.baseWpm, 300);
      expect((await repository.activeProfile()).id, mine.single.id);
      expect(find.byKey(profileImportedKey), findsOneWidget);
      expect(find.byType(SnackBarAction), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('undo restores the previous profile and keeps the import', (
      tester,
    ) async {
      await seed(evening);
      await repository.setActiveProfile(
        evening.id,
        hlc: '0000000000002-00000-seed',
      );
      await pumpScreen(tester, pick: () async => fileNamed('From a friend'));

      await tester.tap(find.byKey(profileImportButtonKey));
      await tester.pumpAndSettle();
      expect((await repository.activeProfile()).id, isNot(evening.id));

      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();

      expect((await repository.activeProfile()).id, evening.id);
      expect(
        (await stored()).map((p) => p.name),
        unorderedEquals(['Evening', 'From a friend']),
      );

      await disposeTree(tester);
    });

    testWidgets('an imported Preset arrives as a second profile with its '
        'name marked', (tester) async {
      late Uint8List exported;
      await pumpScreen(
        tester,
        save: (name, bytes) async => exported = bytes,
        pick: () async => exported,
      );

      await openMenu(tester, Presets.standard.id);
      await tester.tap(find.byKey(profileExportItemKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(profileImportButtonKey));
      await tester.pumpAndSettle();

      final mine = await stored();
      expect(mine, hasLength(1));
      expect(mine.single.name, 'Standard (imported)');
      expect(mine.single.isBuiltIn, isFalse);

      await disposeTree(tester);
    });

    testWidgets('a name the sliding switch owns is marked too', (tester) async {
      await pumpScreen(
        tester,
        pick: () async => fileNamed('${Presets.standard.name} (sliding)'),
      );

      await tester.tap(find.byKey(profileImportButtonKey));
      await tester.pumpAndSettle();

      expect((await stored()).single.name, 'Standard (sliding) (imported)');

      await disposeTree(tester);
    });

    testWidgets('a name already stored is marked', (tester) async {
      await seed(evening);
      await pumpScreen(tester, pick: () async => fileNamed('Evening'));

      await tester.tap(find.byKey(profileImportButtonKey));
      await tester.pumpAndSettle();

      expect(
        (await stored()).map((p) => p.name),
        unorderedEquals(['Evening', 'Evening (imported)']),
      );

      await disposeTree(tester);
    });

    for (final (reason, bytes) in <(ProfileFileRejection, Uint8List)>[
      (ProfileFileRejection.tooLarge, Uint8List(64 * 1024 + 1)),
      (
        ProfileFileRejection.notAProfile,
        Uint8List.fromList(utf8.encode('[1, 2]')),
      ),
      (
        ProfileFileRejection.newerVersion,
        Uint8List.fromList(
          utf8.encode('{"format":"hereader.profile","version":2,"profile":{}}'),
        ),
      ),
    ]) {
      testWidgets('a ${reason.name} file stores nothing and says why', (
        tester,
      ) async {
        await pumpScreen(tester, pick: () async => bytes);

        await tester.tap(find.byKey(profileImportButtonKey));
        await tester.pumpAndSettle();

        expect(await stored(), isEmpty);
        expect(find.byKey(profileRejectionKey(reason)), findsOneWidget);
        expect(find.byKey(profileImportedKey), findsNothing);

        await disposeTree(tester);
      });
    }

    testWidgets('a cancelled pick stores nothing and shows nothing', (
      tester,
    ) async {
      await pumpScreen(tester, pick: () async => null);

      await tester.tap(find.byKey(profileImportButtonKey));
      await tester.pumpAndSettle();

      expect(await stored(), isEmpty);
      expect(find.byType(SnackBar), findsNothing);

      await disposeTree(tester);
    });
  });
}
