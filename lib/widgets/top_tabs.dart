import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'glass.dart';

/// The two-segment top tab control (WATCH LIST | UPCOMING, ABOUT | EPISODES),
/// restyled as a frosted-glass segmented pill matching the bottom nav
/// (Task 5): squircle corners, translucent fill, sliding active segment.
class TopTabs extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const TopTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: GlassSurface(
        stadium: true,
        child: SizedBox(
          height: AppLayout.topTabBarHeight,
          child: LayoutBuilder(
            builder: (context, box) {
              final segW = box.maxWidth / labels.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: AppMotion.slide,
                    curve: AppMotion.glide,
                    left: segW * index + 4,
                    top: 4,
                    bottom: 4,
                    width: segW - 8,
                    child: const _ActiveSegment(),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onChanged(i);
                            },
                            child: Center(
                              child: Text(
                                labels[i],
                                style: i == index
                                    ? AppTextStyles.tabLabelActive
                                    : AppTextStyles.tabLabel,
                              ),
                            ),
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
    );
  }
}

/// Sliding frosted capsule with a soft red glow marking the active tab.
/// StadiumBorder keeps it a clean oval with no corner artifacts.
class _ActiveSegment extends StatelessWidget {
  const _ActiveSegment();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: AppColors.accent.withValues(alpha: 0.20),
        shape: StadiumBorder(
          side: BorderSide(
              color: AppColors.accent.withValues(alpha: 0.28), width: 1),
        ),
        shadows: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.22),
            blurRadius: 14,
          ),
        ],
      ),
    );
  }
}
