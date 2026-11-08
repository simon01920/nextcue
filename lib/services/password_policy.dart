/// Rules for a new password, in display order, each with whether it's met.
///
/// "Part of your name or email" means any 4 consecutive characters of a
/// word in the display name or the email's local part (3-letter words must
/// not appear whole), compared case-insensitively.
List<(String, bool)> passwordRules(String password,
    {String email = '', String name = ''}) {
  final p = password.toLowerCase();
  final words = [name, email.split('@').first]
      .expand((s) => s.toLowerCase().split(RegExp('[^a-z0-9]+')))
      .where((w) => w.length >= 3);
  final reusesName = words.any((w) => w.length < 4
      ? p.contains(w)
      : List.generate(w.length - 3, (i) => w.substring(i, i + 4)).any(p.contains));
  return [
    ('At least 8 characters', password.length >= 8),
    ('An uppercase letter', password.contains(RegExp('[A-Z]'))),
    ('A lowercase letter', password.contains(RegExp('[a-z]'))),
    ('A number', password.contains(RegExp('[0-9]'))),
    ('No part of your name or email', !reusesName),
  ];
}

/// The unmet rules (empty when the password is acceptable).
List<String> passwordProblems(String password,
        {String email = '', String name = ''}) =>
    [
      for (final (rule, ok) in passwordRules(password, email: email, name: name))
        if (!ok) rule,
    ];
