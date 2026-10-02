import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/poster.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  int _segment = 0; // 0 shows&movies, 1 users, 2 groups
  String _query = '';
  Timer? _debounce;
  Future<List<MediaTitle>>? _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ContentRepository>().search('', null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _future = context.read<ContentRepository>().search(_query, null);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ContentColumn(
          child: Column(
            children: [
              _SearchBar(
                controller: _controller,
                onChanged: _onChanged,
                onCancel: () => context.pop(),
              ),
              _Segments(
                  index: _segment,
                  onChanged: (i) => setState(() => _segment = i)),
              Expanded(
                child: FutureBuilder<List<MediaTitle>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: AppColors.accent),
                        ),
                      );
                    }
                    final results = snap.data ?? const <MediaTitle>[];
                    if (_query.isNotEmpty && results.isEmpty) {
                      return _NoResults(query: _query);
                    }
                    return ListView(
                      children: [
                        for (final t in results) _ResultRow(title: t),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onCancel,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.search, color: AppColors.textDisabled, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              style: AppTextStyles.body,
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search shows and movies',
                hintStyle: AppTextStyles.body
                    .copyWith(color: AppColors.textDisabled),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: Icon(Icons.cancel,
                  color: AppColors.textDisabled, size: 20),
            ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: onCancel,
            child: Text('Cancel', style: AppTextStyles.linkText),
          ),
        ],
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _Segments({required this.index, required this.onChanged});
  static const _labels = ['SHOWS & MOVIES', 'USERS', 'GROUPS'];
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_labels[i],
                        style: i == index
                            ? AppTextStyles.captionCaps
                                .copyWith(color: AppColors.textPrimary)
                            : AppTextStyles.captionCaps),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      height: 2,
                      width: 40,
                      color: i == index
                          ? AppColors.textPrimary
                          : Colors.transparent,
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

class _ResultRow extends StatelessWidget {
  final MediaTitle title;
  const _ResultRow({required this.title});
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tracked = appState.statusOf(title.id) != null;
    final canOpen =
        title.id.startsWith('series') || title.id.startsWith('movie');
    return InkWell(
      onTap: canOpen
          ? () => context.push(
              '/${title.kind == MediaKind.movie ? 'movie' : 'series'}/${title.id}')
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Poster(
                width: 44, height: 64, imageAsset: title.poster,
                label: title.name),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.name, style: AppTextStyles.rowTitleList),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (title.yearLine.isNotEmpty) title.yearLine,
                      title.kind == MediaKind.movie ? 'Movie' : 'Series',
                    ].join(' • '),
                    style: AppTextStyles.subtitle,
                  ),
                ],
              ),
            ),
            if (canOpen)
              GestureDetector(
                onTap: () => context.read<AppState>().setStatus(
                    title.id,
                    tracked ? null : TrackStatus.planToWatch),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tracked ? AppColors.accent : Colors.transparent,
                    border: Border.all(color: AppColors.accent),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(tracked ? Icons.check : Icons.add,
                      color: tracked
                          ? AppColors.accentInk
                          : AppColors.accent,
                      size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  const _NoResults({required this.query});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        children: [
          Text("We're sorry!", style: AppTextStyles.rowTitleList),
          const SizedBox(height: AppSpacing.sm),
          Text('We couldn’t find any matches for “$query”',
              textAlign: TextAlign.center, style: AppTextStyles.body),
        ],
      ),
    );
  }
}
