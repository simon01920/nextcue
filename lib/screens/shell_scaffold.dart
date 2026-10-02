import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// App shell holding the bottom navigation bar. The child is the active
/// top-level screen (Shows / Movies / Explore / Profile).
class ShellScaffold extends StatelessWidget {
  final Widget child;
  final String location;
  const ShellScaffold({super.key, required this.child, required this.location});

  int get _index {
    if (location.startsWith('/movies')) return 1;
    if (location.startsWith('/explore')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  void _go(BuildContext context, int i) {
    switch (i) {
      case 0:
        context.go('/shows/watchlist');
      case 1:
        context.go('/movies/watchlist');
      case 2:
        context.go('/explore/feed');
      case 3:
        context.go('/profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    // extendBody lets content scroll behind the floating glass pill so the
    // backdrop blur has something to frost.
    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: ContentColumn(child: child)),
      bottomNavigationBar: _BottomNav(
        index: _index,
        onTap: (i) => _go(context, i),
      ),
    );
  }
}

/// Floating "liquid glass" tab pill: frosted squircle, soft glowing active
/// indicator that slides between items, content-aware blur behind.
class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.index, required this.onTap});

  static const _items = [
    (Icons.tv, 'Shows'),
    (Icons.movie, 'Movies'),
    (Icons.search, 'Explore'),
    (Icons.person_outline, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      child: Center(
        // heightFactor keeps the bar hugging the pill; without it Center
        // expands into the loose height Scaffold offers bottom widgets.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassSurface(
            stadium: true,
            shadow: true,
            child: SizedBox(
              height: AppLayout.bottomNavHeight + 8,
              child: LayoutBuilder(
                builder: (context, box) {
                  final itemW = box.maxWidth / _items.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: AppMotion.slide,
                        curve: AppMotion.glide,
                        left: itemW * index + 6,
                        top: 6,
                        bottom: 6,
                        width: itemW - 12,
                        child: const _ActivePill(),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            Expanded(
                              child: _NavItem(
                                icon: _items[i].$1,
                                label: _items[i].$2,
                                active: i == index,
                                showDot: i == 2,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onTap(i);
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft red-tinted glow capsule marking the active tab. StadiumBorder —
/// a true oval — avoids the edge-line artifacts a squircle draws when its
/// corner radius exceeds the pill's height.
class _ActivePill extends StatelessWidget {
  const _ActivePill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.accent.withValues(alpha: 0.18),
        shape: StadiumBorder(
          side: BorderSide(
              color: AppColors.accent.withValues(alpha: 0.25), width: 1),
        ),
        shadows: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.25),
            blurRadius: 18,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool showDot;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.showDot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.textPrimary : AppColors.textDisabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedScale(
                duration: AppMotion.tab,
                curve: AppMotion.pop,
                scale: active ? 1.08 : 1.0,
                child: Icon(icon,
                    size: 22, color: active ? AppColors.accentAlt : color),
              ),
              if (showDot)
                Positioned(
                  right: -3,
                  top: -1,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.love,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(label,
              style: active
                  ? AppTextStyles.navLabelActive
                  : AppTextStyles.navLabel),
        ],
      ),
    );
  }
}
