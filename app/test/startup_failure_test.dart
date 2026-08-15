import 'package:app/startup_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('says what happened and offers a retry', (tester) async {
    var retries = 0;

    await tester.pumpWidget(
      StartupFailure(
        error: StateError('database is unreachable'),
        onRetry: () => retries++,
      ),
    );

    expect(find.text('Hereader could not start'), findsOneWidget);

    // The reader cannot act on the message, but whoever they report it to
    // can, so it is on screen rather than only in a console they will never
    // open.
    expect(find.textContaining('database is unreachable'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });
}
