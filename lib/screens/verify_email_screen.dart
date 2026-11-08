import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Shown after registering until the account's email is confirmed. The
/// router keeps unverified accounts here (see buildRouter).
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<String?> Function(AuthController) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final m = await action(context.read<AuthController>());
      if (mounted) setState(() => _message = m);
    } on AuthException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = context.watch<AuthController>().account?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 56, color: AppColors.accent),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Confirm your email',
                      textAlign: TextAlign.center, style: AppTextStyles.sectionHeader),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'We sent a link to $email. Open it to activate your account, '
                    'then come back here. Check your spam folder if it isn\'t there.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.subtitle,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  BrandButton(
                    label: "I'VE CONFIRMED IT",
                    onTap: () => _run((a) async => await a.refreshVerification()
                        ? null
                        : 'Not confirmed yet. Open the link in the email first.'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run((a) async {
                              await a.resendVerification();
                              return 'Sent a new link to $email.';
                            }),
                    child: Text('Send the email again', style: AppTextStyles.linkText),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => context.read<AuthController>().logout(),
                    child: Text('Use a different account', style: AppTextStyles.linkText),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(_message!, textAlign: TextAlign.center, style: AppTextStyles.subtitle),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
