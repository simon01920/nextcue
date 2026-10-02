import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../theme/tokens.dart';

class FollowingScreen extends StatelessWidget {
  const FollowingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Following'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.md),
            child: Icon(Icons.person_add_alt, size: 22),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: Row(
                children: [
                  Icon(Icons.search,
                      color: AppColors.textDisabled, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Search following',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textDisabled)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('People you follow',
                  style: AppTextStyles.rowTitleList),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Person>>(
              future: repo.following(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.accent));
                }
                return ListView(
                  children: [
                    for (final p in snap.data!) _PersonRow(person: p),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatefulWidget {
  final Person person;
  const _PersonRow({required this.person});
  @override
  State<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<_PersonRow> {
  late bool _following = widget.person.following;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
              radius: 20, backgroundColor: AppColors.surface),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.person.name, style: AppTextStyles.rowTitleList),
                if (widget.person.followsYou)
                  Text('FOLLOWS YOU', style: AppTextStyles.microCaps),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _following = !_following),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: _following ? Colors.transparent : AppColors.accent,
                border: Border.all(color: AppColors.textPrimary),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                _following ? 'FOLLOWING' : 'FOLLOW',
                style: AppTextStyles.microCaps.copyWith(
                    color: _following
                        ? AppColors.textPrimary
                        : AppColors.accentInk),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
