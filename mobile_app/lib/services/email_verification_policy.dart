/// Who must verify their email before using WellScreen.
///
/// New parent and child accounts must click the verification link before
/// they can reach a dashboard, so fake or mistyped emails cannot be used.
/// Accounts created before [enforcedFrom] keep working without it (test and
/// study accounts made before this rule existed), and admins are never
/// blocked. The account creation time comes from Firebase Auth
/// (user.metadata.creationTime), not from Firestore, so a client cannot
/// change it.
class EmailVerificationPolicy {
  EmailVerificationPolicy._();

  /// 18 Nov 2026, 6:00 PM Manila time.
  static final DateTime enforcedFrom = DateTime.utc(2026, 11, 18, 10);

  static bool mustVerify({
    required bool emailVerified,
    required bool isAdmin,
    required DateTime? accountCreatedAt,
    DateTime? cutoff,
  }) {
    if (emailVerified || isAdmin) return false;
    final start = cutoff ?? enforcedFrom;
    // No creation time is unexpected; ask for verification rather than
    // letting an unknown account through.
    if (accountCreatedAt == null) return true;
    return !accountCreatedAt.toUtc().isBefore(start);
  }
}
