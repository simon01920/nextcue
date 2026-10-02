import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// Centered pill section label ("HAVEN'T WATCHED FOR A WHILE", "WATCH NEXT").
class SectionChip extends StatelessWidget {
  final String label;
  const SectionChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs + 1),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(label, style: AppTextStyles.captionCaps),
      ),
    );
  }
}

/// Outlined show-name pill with trailing chevron, as on watch-list rows.
class ShowPill extends StatelessWidget {
  final String name;
  final VoidCallback? onTap;
  const ShowPill(this.name, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.microCaps
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right,
                size: 12, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Circular watched-toggle button (list rows, season/episode).
class WatchCheck extends StatelessWidget {
  final bool watched;
  final double size;
  final VoidCallback? onTap;
  const WatchCheck({
    super.key,
    required this.watched,
    this.size = AppLayout.checkCircle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.check,
        curve: AppMotion.pop,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: watched ? AppColors.success : Colors.transparent,
          border: watched
              ? null
              : Border.all(color: AppColors.textDisabled, width: 1.5),
        ),
        child: Icon(
          Icons.check,
          size: size * 0.5,
          color: watched ? Colors.white : AppColors.textDisabled,
        ),
      ),
    );
  }
}

/// Small "+N" unwatched-ahead counter shown next to the S/E code.
class CountBadge extends StatelessWidget {
  final int count;
  const CountBadge(this.count, {super.key});
  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs + 2),
      child: Text('+$count', style: AppTextStyles.counterAccent),
    );
  }
}

/// Full-width yellow CTA pill (BROWSE ALL SHOWS, LOG OUT, MARK AS WATCHED…).
class BrandButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool expand;
  const BrandButton(
      {super.key,
      required this.label,
      this.onTap,
      this.leading,
      this.expand = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: expand ? double.infinity : null,
      child: Material(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(label, style: AppTextStyles.buttonPillCaps),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section header row ("Cast", "Stats", "Favorite shows" with heart) + chevron.
class SectionHeader extends StatelessWidget {
  final String title;
  final bool heart;
  final VoidCallback? onMore;
  const SectionHeader(this.title,
      {super.key, this.heart = false, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          if (heart) ...[
            const Icon(Icons.favorite, color: AppColors.love, size: 22),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(child: Text(title, style: AppTextStyles.sectionHeader)),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              child: Icon(Icons.chevron_right,
                  color: AppColors.textPrimary, size: 26),
            ),
        ],
      ),
    );
  }
}

/// Empty-state block (popcorn-style illustration + copy + CTA).
class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback? onCta;
  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                textAlign: TextAlign.center,
                style: AppTextStyles.screenTitle),
            const SizedBox(height: AppSpacing.xl),
            const _PopcornMark(),
            const SizedBox(height: AppSpacing.xl),
            Text(subtitle,
                textAlign: TextAlign.center, style: AppTextStyles.body),
            const SizedBox(height: AppSpacing.xl),
            BrandButton(label: ctaLabel, onTap: onCta, expand: false),
          ],
        ),
      ),
    );
  }
}

class _PopcornMark extends StatelessWidget {
  const _PopcornMark();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const Icon(Icons.local_movies, size: 54, color: AppColors.love),
          const Positioned(
              top: 6, left: 20, child: _Spark(AppColors.link)),
          const Positioned(
              bottom: 14, right: 12, child: _Spark(AppColors.accent)),
          const Positioned(top: 30, right: 4, child: _Spark(AppColors.love)),
        ],
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  final Color color;
  const _Spark(this.color);
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.star, size: 14, color: color);
}

/// SVG icon tinted with a color (nav/cta glyphs authored black, tinted live).
class TintedIcon extends StatelessWidget {
  final String asset;
  final double size;

  /// Null means "follow the theme" — resolved at build time, since the
  /// neutral palette is no longer a compile-time constant.
  final Color? color;
  const TintedIcon(this.asset, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter:
          ColorFilter.mode(color ?? AppColors.textPrimary, BlendMode.srcIn),
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
  }
}

/// Thin yellow progress bar under a poster/season row.
class WatchProgressBar extends StatelessWidget {
  final double progress;
  const WatchProgressBar(this.progress, {super.key});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppLayout.progressBarHeight,
      child: Row(
        children: [
          Expanded(
            flex: (progress * 1000).round().clamp(0, 1000),
            child: const ColoredBox(color: AppColors.accent),
          ),
          Expanded(
            flex: 1000 - (progress * 1000).round().clamp(0, 1000),
            child: ColoredBox(color: AppColors.surface),
          ),
        ],
      ),
    );
  }
}

/// The "+" affordance used on discover rails, feed cards, search results and
/// the browse wall. Adds the title to the account's plan-to-watch list (and
/// removes it again when already tracked), with a confirmation snackbar.
///
/// Lives here rather than in each screen so every "+" in the app behaves the
/// same and actually writes to [AppState].
class AddToListButton extends StatelessWidget {
  final MediaTitle title;
  final bool tracked;
  final double size;
  const AddToListButton({
    super.key,
    required this.title,
    required this.tracked,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        final appState = context.read<AppState>();
        final nowTracked = appState.statusOf(title.id) != null;
        appState.setStatus(
            title.id, nowTracked ? null : TrackStatus.planToWatch);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(nowTracked
                ? 'Removed ${title.name} from your lists'
                : 'Added ${title.name} to Plan to watch'),
          ));
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tracked ? AppColors.accent : Colors.black54,
          border: Border.all(color: AppColors.accent),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(
          tracked ? Icons.check : Icons.add,
          color: tracked ? AppColors.accentInk : AppColors.accent,
          size: size * 0.58,
        ),
      ),
    );
  }
}

/// Constrains page content to the measured 1023px column, centered/letterboxed.
class ContentColumn extends StatelessWidget {
  final Widget child;
  const ContentColumn({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.contentMax),
        child: child,
      ),
    );
  }
}
