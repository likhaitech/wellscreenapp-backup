/// WellScreen's password rule, shared by registration and Change Password.
///
/// A password must have at least 8 characters, an uppercase letter, a
/// lowercase letter, a number and a special character (for example
/// ! @ # $ % ^ & * ). Existing accounts are not affected until they
/// change their password.
class PasswordPolicy {
  PasswordPolicy._();

  static const int minLength = 8;

  /// Short description shown under password fields.
  static const String hint =
      'At least 8 characters, with an uppercase letter, a lowercase letter, '
      'a number and a special character (e.g. ! @ # \$ % ^ & *).';

  static final RegExp _upper = RegExp(r'[A-Z]');
  static final RegExp _lower = RegExp(r'[a-z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  // Any visible character that is not a letter, digit or space counts as
  // special, so users are not tripped up by an unlisted symbol.
  static final RegExp _special = RegExp(r'[^A-Za-z0-9\s]');

  /// Every requirement with whether [password] meets it, in display order.
  static List<({String label, bool met})> evaluate(String password) {
    return [
      (
        label: 'At least $minLength characters',
        met: password.length >= minLength,
      ),
      (label: 'An uppercase letter (A-Z)', met: _upper.hasMatch(password)),
      (label: 'A lowercase letter (a-z)', met: _lower.hasMatch(password)),
      (label: 'A number (0-9)', met: _digit.hasMatch(password)),
      (
        label: 'A special character (e.g. ! @ # \$ % ^ & *)',
        met: _special.hasMatch(password),
      ),
    ];
  }

  /// The requirements [password] does not meet yet. Empty means valid.
  static List<String> missing(String password) => [
    for (final rule in evaluate(password))
      if (!rule.met) rule.label,
  ];

  static bool isStrong(String password) => missing(password).isEmpty;
}
