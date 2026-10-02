import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../theme/tokens.dart';

class CommentsScreen extends StatefulWidget {
  final String titleId;
  const CommentsScreen({super.key, required this.titleId});
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  String _sort = 'Most relevant';

  /// Comments posted this session, shown above the seeded thread. There is
  /// no community server yet, so these are local-only.
  final List<Comment> _posted = [];

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ContentRepository>();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Comments'),
            Text('485 comments', style: AppTextStyles.subtitle),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: AppSpacing.md),
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
                color: AppColors.link, shape: BoxShape.circle),
            child: const Icon(Icons.settings, size: 18, color: Colors.white),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openComposer,
        shape: const CircleBorder(),
        child: const Icon(Icons.edit, color: AppColors.accentInk),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Text('SORT BY ', style: AppTextStyles.captionCaps),
                GestureDetector(
                  onTap: _openSort,
                  child: Text(_sort, style: AppTextStyles.linkText),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Comment>>(
              future: repo.comments(widget.titleId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.accent));
                }
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  children: [
                    for (final c in _posted) _CommentCard(comment: c),
                    for (final c in snap.data!) _CommentCard(comment: c),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openComposer() {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      builder: (sheet) => Padding(
        // Keep the field above the on-screen keyboard.
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(sheet).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a comment',
                style: AppTextStyles.sectionHeader.copyWith(fontSize: 20)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              style: AppTextStyles.body,
              decoration: InputDecoration(
                hintText: 'Share your thoughts (no spoilers!)…',
                hintStyle: AppTextStyles.subtitle,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final body = controller.text.trim();
                  if (body.isEmpty) return;
                  final name = context
                          .read<AuthController>()
                          .account
                          ?.displayName ??
                      'You';
                  setState(() => _posted.insert(
                      0, Comment(user: name, date: 'Just now', body: body)));
                  Navigator.pop(sheet);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        duration: Duration(seconds: 2),
                        content: Text('Comment posted')),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill)),
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                child: Text('POST', style: AppTextStyles.buttonPillCaps),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSort() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      builder: (c) {
        var choice = _sort;
        return StatefulBuilder(
          builder: (c, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sort by',
                      style: AppTextStyles.sectionHeader.copyWith(fontSize: 20)),
                  const SizedBox(height: AppSpacing.md),
                  for (final opt in const [
                    'Most relevant',
                    'Most liked',
                    'Most recent'
                  ])
                    InkWell(
                      onTap: () => setSheet(() => choice = opt),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(opt, style: AppTextStyles.body)),
                            Icon(
                              choice == opt
                                  ? Icons.check_circle
                                  : Icons.radio_button_off,
                              color: choice == opt
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(c),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.textPrimary),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill)),
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md),
                          ),
                          child: Text('CANCEL',
                              style: AppTextStyles.captionCaps
                                  .copyWith(color: AppColors.textPrimary)),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() => _sort = choice);
                            Navigator.pop(c);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill)),
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md),
                          ),
                          child: Text('APPLY',
                              style: AppTextStyles.buttonPillCaps),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommentCard extends StatelessWidget {
  final Comment comment;
  const _CommentCard({required this.comment});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                  radius: 18, backgroundColor: AppColors.surfaceElevated),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(comment.user,
                        style: AppTextStyles.rowTitleList
                            .copyWith(fontSize: 15)),
                    Text(comment.date, style: AppTextStyles.subtitle),
                  ],
                ),
              ),
              Icon(Icons.flag_outlined,
                  size: 18, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(comment.body, style: AppTextStyles.body),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.favorite_border,
                  size: 18, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Text('${comment.likes}', style: AppTextStyles.subtitle),
              const SizedBox(width: AppSpacing.lg),
              Icon(Icons.chat_bubble_outline,
                  size: 16, color: AppColors.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Text('${comment.replies}', style: AppTextStyles.subtitle),
              const Spacer(),
              Icon(Icons.ios_share, size: 18, color: AppColors.textMuted),
            ],
          ),
        ],
      ),
    );
  }
}
