import 'package:app/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WellScreen app shows the design D login screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.pump();

    // The real WellScreen logo replaces the old wordmark text.
    expect(
      find.byWidgetPredicate(
        (w) => w is Image && w.semanticLabel == 'WellScreen',
      ),
      findsOneWidget,
    );
    expect(find.text('Welcome back'), findsOneWidget);
    expect(
      find.text('Log in to keep your family’s screen time healthy.'),
      findsOneWidget,
    );
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);

    expect(
      find.text('Parent access for digital wellness monitoring'),
      findsNothing,
    );
    expect(find.textContaining('Monitored child devices'), findsNothing);
    expect(find.textContaining('QR option'), findsNothing);
  });
}
