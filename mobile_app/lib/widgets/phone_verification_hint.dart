import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Guardians only, and only until a phone number is verified: SMS backup
/// alerts need a verified number to text.
bool shouldShowPhoneVerificationHint({
  required String role,
  required String? verifiedPhoneNumber,
}) {
  if (role != 'parent') return false;
  return verifiedPhoneNumber == null || verifiedPhoneNumber.trim().isEmpty;
}

/// Amber hint shown under "Mobile Number Verification" in Profile Settings.
class PhoneVerificationHint extends StatelessWidget {
  const PhoneVerificationHint({super.key, this.onTap});

  static const String message =
      'Verify your phone number to receive SMS backup alerts when your '
      'child opens a blocked app.';

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warningBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sms_outlined, color: AppColors.warning, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
