import 'package:flutter/material.dart';

import '../services/password_policy.dart';
import '../theme/tokens.dart';

/// Live checklist of the password rules, updating as the user types.
class PasswordRulesList extends StatelessWidget {
  final TextEditingController password;
  final String Function() email;
  final String Function() name;
  const PasswordRulesList({
    super.key,
    required this.password,
    required this.email,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: password,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (rule, ok)
              in passwordRules(password.text, email: email(), name: name()))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Semantics(
                label: '$rule, ${ok ? 'met' : 'not met'}',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 16, color: ok ? AppColors.success : AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(rule,
                        style: AppTextStyles.subtitle.copyWith(
                            color: ok ? AppColors.textPrimary : AppColors.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
