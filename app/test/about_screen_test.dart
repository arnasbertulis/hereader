import 'package:app/reading/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'hereader',
      packageName: 'com.hereader.app',
      version: '0.4.1',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the version and build number', (tester) async {
    await pump(tester);

    expect(find.text('Version 0.4.1 (build 1)'), findsOneWidget);
  });

  testWidgets('offers a licence page covering the app and its dependencies', (
    tester,
  ) async {
    await pump(tester);

    final button = find.byKey(aboutLicenseButtonKey);
    await tester.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Licence'), findsOneWidget);
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('tells a reader where to report a problem', (tester) async {
    await pump(tester);

    final row = find.text('Report a problem');
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(row, findsOneWidget);
    expect(
      find.textContaining('github.com/arnasbertulis/hereader/issues'),
      findsOneWidget,
    );
  });
}
