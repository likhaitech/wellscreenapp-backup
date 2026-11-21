import 'package:app/widgets/app_release_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The notice sits in MaterialApp.builder, above the Navigator, where there
/// is no Overlay. A tooltip there threw "No Overlay widget found" and
/// replaced the whole app with an error screen.
void main() {
  testWidgets('shows and hides without an Overlay above it', (tester) async {
    var hidden = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Align(
            alignment: Alignment.topCenter,
            child: MaintenanceNoticeBar(
              message: 'Server maintenance tonight at 10 PM',
              onHide: () => hidden = true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Server maintenance tonight at 10 PM'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hideMaintenanceNotice')));
    expect(hidden, isTrue);
  });
}
