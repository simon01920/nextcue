import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/demo_seed.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

/// Login / Register in the Bingely design language (dark surface, red
/// accent, Figtree). First registration with a claimed email attaches the
/// seeded profile.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _register = false;
  bool _busy = false;
  String? _error;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    try {
      if (_register) {
        await auth.register(_email.text, _password.text, _name.text);
      } else {
        await auth.login(_email.text, _password.text);
      }
      // Router redirect takes over on success.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One-tap demo session: logs into the shared demo account, registering
  /// it on first use. Content is seeded after login (see demo_seed.dart).
  Future<void> _demo() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthController>();
    try {
      try {
        await auth.login(demoEmail, demoPassword);
      } on AuthException {
        await auth.register(demoEmail, demoPassword, demoDisplayName);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: BingelyWordmark()),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: Text(
                    'Track every show. Miss nothing.',
                    style: AppTextStyles.subtitle,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                _Tabs(
                  register: _register,
                  onChanged: (v) => setState(() {
                    _register = v;
                    _error = null;
                  }),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (_register) ...[
                  _Field(
                      controller: _name,
                      hint: 'Display name',
                      icon: Icons.person_outline),
                  const SizedBox(height: AppSpacing.md),
                ],
                _Field(
                    controller: _email,
                    hint: 'Email',
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress),
                const SizedBox(height: AppSpacing.md),
                _Field(
                    controller: _password,
                    hint: 'Password',
                    icon: Icons.lock_outline,
                    obscure: true,
                    onSubmitted: (_) => _submit()),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!,
                      style: AppTextStyles.subtitle
                          .copyWith(color: AppColors.error)),
                ],
                const SizedBox(height: AppSpacing.xl),
                _busy
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: AppColors.accent),
                        ),
                      )
                    : BrandButton(
                        label: _register ? 'CREATE ACCOUNT' : 'LOG IN',
                        onTap: _submit,
                      ),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _register = !_register;
                      _error = null;
                    }),
                    child: Text(
                      _register
                          ? 'Already have an account?  Log in'
                          : "Don't have an account?  Register",
                      style: AppTextStyles.linkText,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton(
                  onPressed: _busy ? null : _demo,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.borderSubtle),
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.lg),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  child: Text('TRY THE DEMO',
                      style: AppTextStyles.buttonPillCaps
                          .copyWith(color: AppColors.textPrimary)),
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: Text(
                    'Preloaded account with shows to explore',
                    style: AppTextStyles.subtitle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final bool register;
  final ValueChanged<bool> onChanged;
  const _Tabs({required this.register, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool isRegister) {
      final active = register == isRegister;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(isRegister),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: active
                      ? AppTextStyles.tabLabelActive
                      : AppTextStyles.tabLabel,
                ),
              ),
              Container(
                height: 3,
                color:
                    active ? AppColors.accent : Colors.transparent,
              ),
            ],
          ),
        ),
      );
    }

    return Row(children: [tab('LOG IN', false), tab('REGISTER', true)]);
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              onSubmitted: onSubmitted,
              style: AppTextStyles.body,
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle:
                    AppTextStyles.body.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
