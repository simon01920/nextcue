import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';

class ProfileEditScreen extends StatelessWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: () => context.pop()),
        title: const Text('Edit profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Text('SAVE',
                  style: AppTextStyles.captionCaps
                      .copyWith(color: AppColors.textDisabled)),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          _PhotoRow(
              label: 'Choose profile photo',
              trailing: Icon(Icons.cancel, color: AppColors.textMuted)),
          const Divider(),
          _PhotoRow(
              label: 'Choose cover photo',
              trailing: Icon(Icons.cancel, color: AppColors.textMuted)),
          const Divider(),
          const _FieldRow(label: 'Display name', value: 'Demo User'),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text('Personal information',
                style: AppTextStyles.sectionHeader.copyWith(fontSize: 18)),
          ),
          const _FieldRow(label: 'Birth year', value: '2003'),
          const _FieldRow(label: 'Gender', value: 'Male'),
          _FieldRow(
              label: 'Country',
              value: 'Slovakia',
              trailing: Icon(Icons.cancel, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  final String label;
  final Widget trailing;
  const _PhotoRow({required this.label, required this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(label, style: AppTextStyles.linkText)),
          trailing,
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  const _FieldRow({required this.label, required this.value, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.body),
                const SizedBox(height: AppSpacing.xs),
                Text(value, style: AppTextStyles.linkText),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
