import 'package:app/services/sms_alert_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('smsAlertOutcomeLabel', () {
    test('sent and delivered read as plain words', () {
      expect(smsAlertOutcomeLabel('sent'), 'Sent');
      expect(smsAlertOutcomeLabel('delivered'), 'Delivered');
    });

    test('generic failures point at missing load', () {
      expect(
        smsAlertOutcomeLabel('failed_generic'),
        "Failed - the child's phone may have no load",
      );
      expect(
        smsAlertOutcomeLabel('failed_exception'),
        "Failed - the child's phone may have no load",
      );
    });

    test('signal failures say so', () {
      expect(
        smsAlertOutcomeLabel('failed_no_service'),
        "Failed - the child's phone had no signal",
      );
      expect(
        smsAlertOutcomeLabel('failed_radio_off'),
        "Failed - the child's phone had no signal",
      );
    });

    test('undelivered and unknown values', () {
      expect(smsAlertOutcomeLabel('undelivered'), startsWith('Not delivered'));
      expect(smsAlertOutcomeLabel(null), 'Unknown result');
      expect(smsAlertOutcomeLabel(''), 'Unknown result');
      expect(smsAlertOutcomeLabel('something_new'), 'Unknown result');
    });
  });

  test('smsAlertSucceeded', () {
    expect(smsAlertSucceeded('sent'), isTrue);
    expect(smsAlertSucceeded('delivered'), isTrue);
    expect(smsAlertSucceeded('undelivered'), isFalse);
    expect(smsAlertSucceeded('failed_generic'), isFalse);
    expect(smsAlertSucceeded(null), isFalse);
  });
}
