import 'package:app/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WellScreen app shows updated login screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.pump();

    expect(find.text('WellScreen'), findsOneWidget);
    expect(find.text('Build healthy digital habits together'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);

    expect(
      find.text('Parent access for digital wellness monitoring'),
      findsNothing,
    );
    expect(find.textContaining('Monitored child devices'), findsNothing);
    expect(find.textContaining('QR option'), findsNothing);
  });
}
