import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Notifications. TV Time's own endpoint was erroring during recon, so the
/// clone models both: a populated list and the observed "Loading failed" state
/// (toggle the seed to demo either).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : _failed
              ? _FailedState(onReload: _load)
              : ListView(
                  children: [
                    for (final n in _mock)
                      _NotificationRow(text: n.$1, when: n.$2),
                  ],
                ),
    );
  }

  static const _mock = [
    ('Ren started following you', '2h'),
    ('haruyu liked your comment on Your Lie in April', '5h'),
    ('New episode of Frieren is available', '1d'),
    ('Soni replied to your comment', '2d'),
  ];
}

class _NotificationRow extends StatelessWidget {
  final String text;
  final String when;
  const _NotificationRow({required this.text, required this.when});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(radius: 20, backgroundColor: AppColors.surface),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: AppTextStyles.body)),
          const SizedBox(width: AppSpacing.sm),
          Text(when, style: AppTextStyles.subtitle),
        ],
      ),
    );
  }
}

class _FailedState extends StatelessWidget {
  final VoidCallback onReload;
  const _FailedState({required this.onReload});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 40, color: AppColors.textPrimary),
          const SizedBox(height: AppSpacing.md),
          Text('Loading failed.', style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: onReload,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textPrimary),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text('RELOAD',
                  style: AppTextStyles.captionCaps
                      .copyWith(color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}
