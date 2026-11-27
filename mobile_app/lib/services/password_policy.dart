
class PasswordPolicy {
  PasswordPolicy._();

  static const int minLength = 8;


  static const String hint =
      'At least 8 characters, with an uppercase letter, a lowercase letter, '
      'a number and a special character (e.g. ! @ # \$ % ^ & *).';

  static final RegExp _upper = RegExp(r'[A-Z]');
  static final RegExp _lower = RegExp(r'[a-z]');
  static final RegExp _digit = RegExp(r'[0-9]');

  static final RegExp _special = RegExp(r'[^A-Za-z0-9\s]');


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


  static List<String> missing(String password) => [
    for (final rule in evaluate(password))
      if (!rule.met) rule.label,
  ];

  static bool isStrong(String password) => missing(password).isEmpty;
}
