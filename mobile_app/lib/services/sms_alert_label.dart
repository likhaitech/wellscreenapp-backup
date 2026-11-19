/// Turns an SMS backup alert's outcome code (saved by the child's phone,
/// SmsAlertSender.kt / SmsSentReceiver.kt) into plain words for the
/// guardian's Reports screen.
String smsAlertOutcomeLabel(String? outcome) {
  if (outcome == null || outcome.isEmpty) return 'Unknown result';
  switch (outcome) {
    case 'sent':
      return 'Sent';
    case 'delivered':
      return 'Delivered';
    case 'undelivered':
      return 'Not delivered - your phone may be off or out of signal';
    case 'failed_no_service':
    case 'failed_radio_off':
      return "Failed - the child's phone had no signal";
    case 'failed_no_manager':
      return "Failed - this phone can't send SMS";
  }
  if (outcome.startsWith('failed')) {
    return "Failed - the child's phone may have no load";
  }
  return 'Unknown result';
}

/// True for outcomes that mean the text left the child's phone.
bool smsAlertSucceeded(String? outcome) =>
    outcome == 'sent' || outcome == 'delivered';
