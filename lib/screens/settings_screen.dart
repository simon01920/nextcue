import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/password_rules.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _tab = 0;
  bool _displayLanguage = false;
  bool _private = false;
  bool _hideWatched = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ContentColumn(
        child: Column(
          children: [
            _SettingsTabs(index: _tab, onChanged: (i) => setState(() => _tab = i)),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 1:
        return _appTab();
      case 2:
        return _upcomingTab();
      default:
        return _accountTab();
    }
  }

  Widget _accountTab() {
    final account = context.watch<AuthController>().account;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _sectionHeaderRow('Identification', trailing: 'SAVE'),
        _labelValue('Username', account?.displayName ?? '—'),
        _labelValue('Email', account?.email ?? '—', link: true),
        _labelValue('User ID', account?.uid ?? '—'),
        if (account?.hasPassword ?? false)
          _navRow('Change password', onTap: _changePassword),
        const Divider(height: AppSpacing.xxl),
        _sectionHeaderRow('Social Networks'),
        _navRow('Edit linked accounts'),
        const Divider(height: AppSpacing.xxl),
        _sectionHeaderRow('Subscription Services'),
        _navRow('Edit your subscription services'),
        const Divider(height: AppSpacing.xxl),
        _sectionHeaderRow('Privacy'),
        _labelValue('Read Privacy & Legal', ''),
        _toggleRow('Set profile to private',
            'If your profile is private, you must approve follow requests. '
            'Only followers can see your activity.',
            _private, (v) => setState(() => _private = v)),
        const SizedBox(height: AppSpacing.xl),
        BrandButton(
          label: 'LOG OUT',
          onTap: () => context.read<AuthController>().logout(),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            onPressed: _deleteAccount,
            child: Text('DELETE ACCOUNT',
                style: AppTextStyles.captionCaps
                    .copyWith(color: AppColors.error)),
          ),
        ),
      ],
    );
  }

  Future<void> _changePassword() async {
    final auth = context.read<AuthController>();
    final current = TextEditingController();
    final next = TextEditingController();
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Change password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                    controller: current,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Current password')),
                TextField(
                    controller: next,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New password')),
                const SizedBox(height: AppSpacing.sm),
                PasswordRulesList(
                    password: next,
                    email: () => auth.account?.email ?? '',
                    name: () => auth.account?.displayName ?? ''),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(error!, style: AppTextStyles.subtitle.copyWith(color: AppColors.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await auth.changePassword(current.text, next.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password changed')));
                        }
                      } on AuthException catch (e) {
                        setLocal(() => error = e.message);
                      } finally {
                        if (ctx.mounted) setLocal(() => busy = false);
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    current.dispose();
    next.dispose();
  }

  Future<void> _deleteAccount() async {
    final auth = context.read<AuthController>();
    final needsPassword = auth.account?.hasPassword ?? false;
    final password = TextEditingController();
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Delete account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This permanently deletes your account, watch history, '
                  'lists and ratings, on every device. It cannot be undone.'),
              if (needsPassword)
                TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password to confirm')),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(error!, style: AppTextStyles.subtitle.copyWith(color: AppColors.error)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await auth.deleteAccount(password: needsPassword ? password.text : null);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } on AuthException catch (e) {
                        if (ctx.mounted) setLocal(() => error = e.message);
                      } catch (_) {
                        if (ctx.mounted) {
                          setLocal(() => error = 'Could not delete the account. Try again.');
                        }
                      } finally {
                        if (ctx.mounted) setLocal(() => busy = false);
                      }
                    },
              child: const Text('Delete forever', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
    password.dispose();
  }

  Widget _appTab() {
    final appState = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _sectionHeaderRow('Titles'),
        _toggleRow('Display in your language',
            'By default, titles will display in English', _displayLanguage,
            (v) => setState(() => _displayLanguage = v)),
        const Divider(height: AppSpacing.xxl),
        _sectionHeaderRow('Comments'),
        _navRow('Select comment languages',
            sub: 'By default, comments are displayed in English and your '
                'device language'),
        const Divider(height: AppSpacing.xxl),
        _sectionHeaderRow('Theme'),
        _radioRow('Automatically sync app with device setting',
            ThemeMode.system, appState),
        _radioRow('Light Mode', ThemeMode.light, appState),
        _radioRow('Dark Mode', ThemeMode.dark, appState),
        const Divider(height: AppSpacing.xxl),
        _sectionHeaderRow('Recommendations'),
        _navRow('Manage disliked shows and movies'),
        const SizedBox(height: AppSpacing.xl),
        BrandButton(
          label: 'CLEAR CACHE',
          onTap: () async {
            await context.read<ApiCache>().clear();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                duration: Duration(seconds: 2),
                content: Text('API cache cleared')));
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
            child: Text('NEXTCUE 1.0.0 · TV data from TheTVDB',
                style: AppTextStyles.microCaps)),
      ],
    );
  }

  Widget _upcomingTab() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _sectionHeaderRow('Episodes to display'),
        _navRow('Filter networks'),
        _toggleRow('Hide watched episodes', '', _hideWatched,
            (v) => setState(() => _hideWatched = v)),
      ],
    );
  }

  Widget _sectionHeaderRow(String title, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
              child: Text(title,
                  style: AppTextStyles.sectionHeader.copyWith(fontSize: 18))),
          if (trailing != null)
            Text(trailing,
                style: AppTextStyles.captionCaps
                    .copyWith(color: AppColors.textDisabled)),
        ],
      ),
    );
  }

  Widget _labelValue(String label, String value, {bool link = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.body),
          if (value.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(value,
                style: link
                    ? AppTextStyles.linkText
                    : AppTextStyles.subtitle
                        .copyWith(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _navRow(String label, {String? sub, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap ??
          // A chevron row must never be silently dead — until the target
          // screen exists it says so instead of ignoring the tap.
          () => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
                duration: Duration(seconds: 2),
                content: Text('Not available yet — coming in an update'))),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.body),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: AppTextStyles.subtitle),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
      ),
    );
  }

  Widget _toggleRow(
      String label, String sub, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.body),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: AppTextStyles.subtitle),
                ],
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _radioRow(String label, ThemeMode mode, AppState appState) {
    final selected = appState.themeMode == mode;
    return InkWell(
      onTap: () => appState.setThemeMode(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.textPrimary : AppColors.textMuted),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: AppTextStyles.body)),
          ],
        ),
      ),
    );
  }
}

class _SettingsTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _SettingsTabs({required this.index, required this.onChanged});
  static const _labels = ['ACCOUNT', 'APP', 'UPCOMING'];
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(_labels[i],
                        style: i == index
                            ? AppTextStyles.tabLabelActive
                            : AppTextStyles.tabLabel),
                    if (i == index)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                            height: 3, color: AppColors.textPrimary),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
