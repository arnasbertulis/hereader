import 'package:app/data/database.dart';
import 'package:app/data/library_repository.dart';
import 'package:app/reading/custom_accent_screen.dart';
import 'package:app/reading/profile_edit_screen.dart';
import 'package:app/reading/rgb_sliders.dart';
import 'package:app/reading/setting_slider.dart';
import 'package:app/theme/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rsvp_engine/rsvp_engine.dart';

import 'test_database.dart';

final _hexPattern = RegExp(r'^#[0-9A-F]{6}$');

Finder _hexText() => find.byWidgetPredicate(
  (widget) => widget is Text && _hexPattern.hasMatch(widget.data ?? ''),
);

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

  testWidgets('both colour screens build the shared control', (tester) async {
    final controller = AppearanceController(
      repository: repository,
      issueStamp: issueStamp,
    );

    await tester.pumpWidget(
      MaterialApp(home: CustomAccentScreen(controller: controller)),
    );

    expect(find.byType(RgbSliders), findsOneWidget);
    expect(find.byType(SettingSlider), findsNWidgets(3));
  });

  testWidgets('the accent paints per frame and writes once on release', (
    tester,
  ) async {
    final controller = AppearanceController(
      repository: repository,
      issueStamp: issueStamp,
    );

    await tester.pumpWidget(
      MaterialApp(home: CustomAccentScreen(controller: controller)),
    );

    final hexBefore = (tester.widget(_hexText()) as Text).data;

    await tester.runAsync(() async {
      await tester.drag(find.byType(Slider).first, const Offset(200, 0));
      await tester.pump();
      await tester.pumpAndSettle();
    });

    final hexAfter = (tester.widget(_hexText()) as Text).data;

    expect(hexAfter, isNot(hexBefore));
    expect(stamps, 1);
  });

  testWidgets('the background field honours enabled', (tester) async {
    final navigator = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigator, home: const SizedBox()),
    );

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => ProfileEditScreen(
          // A preset: the editor disables every control, including the
          // background field's sliders.
          profile: Presets.standard,
          repository: repository,
          issueStamp: issueStamp,
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder list() => find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;

    await tester.scrollUntilVisible(
      find.byType(RgbSliders),
      200,
      scrollable: list(),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<RgbSliders>(find.byType(RgbSliders)).enabled, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
