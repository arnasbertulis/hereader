import 'package:app/sync/api_client.dart';
import 'package:app/sync/auth_store.dart';
import 'package:app/sync/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late AuthStore auth;
  late ApiClient api;

  setUp(() {
    auth = AuthStore(storage: FakeSecureStorage());
    api = ApiClient(baseUrl: Uri.parse('http://localhost'), auth: auth);
  });

  tearDown(() {
    api.dispose();
    auth.dispose();
  });

  Future<void> pumpSignIn(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: SignInScreen(api: api)));
  }

  group('password field visibility toggle', () {
    testWidgets('starts obscured', (tester) async {
      await pumpSignIn(tester);

      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.obscureText, isTrue);
    });

    testWidgets('reveals the password on tap and hides it again on a '
        'second tap', (tester) async {
      await pumpSignIn(tester);

      await tester.tap(find.byKey(passwordVisibilityToggleKey));
      await tester.pump();

      var field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.obscureText, isFalse);

      await tester.tap(find.byKey(passwordVisibilityToggleKey));
      await tester.pump();

      field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.obscureText, isTrue);
    });

    testWidgets('tooltip names the action the tap performs', (tester) async {
      await pumpSignIn(tester);

      expect(
        tester
            .widget<IconButton>(find.byKey(passwordVisibilityToggleKey))
            .tooltip,
        'Show password',
      );

      await tester.tap(find.byKey(passwordVisibilityToggleKey));
      await tester.pump();

      expect(
        tester
            .widget<IconButton>(find.byKey(passwordVisibilityToggleKey))
            .tooltip,
        'Hide password',
      );
    });
  });
}
