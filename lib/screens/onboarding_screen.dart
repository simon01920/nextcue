import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/repository.dart';
import '../models/models.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/cover_resize_image.dart';

/// First-launch onboarding, styled after inspiration/onboarding: a
/// full-bleed hero still under a dark scrim, wordmark up top, big two-line
/// headline (white + red), body copy, Continue/Join buttons, terms line
/// and page dots. Shown once; [onFinish] persists the flag.
class OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onFinish;
  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  final String headline;
  final String accent;
  final String body;
  const _Page(this.headline, this.accent, this.body);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    _Page(
      'Track Smarter.',
      "Cue What's Next.",
      'NextCue is your home base for TV shows and movies. Always know '
          'exactly which episode is up next.',
    ),
    _Page(
      'Swipe. Watched.',
      'Done.',
      'One swipe marks an episode watched, one swipe back undoes it. '
          'Keeping up has never been this fast.',
    ),
    _Page(
      "Can't Pick?",
      'Spin for It.',
      'Let the Decide wheel — or a coin flip — choose tonight\'s watch '
          'from your list, so you spend the evening watching, not browsing.',
    ),
    _Page(
      'Your Shelf.',
      'Your Stats.',
      'Finished titles line up on a collector\'s DVD shelf, and every '
          'episode you watch builds your personal stats and charts.',
    ),
  ];

  Future<List<MediaTitle>>? _backdrop;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    if (_index >= _pages.length - 1) {
      widget.onFinish();
    } else {
      HapticFeedback.selectionClick();
      _controller.nextPage(
          duration: AppMotion.slide, curve: AppMotion.glide);
    }
  }

  @override
  Widget build(BuildContext context) {
    _backdrop ??= context.read<ContentRepository>().topForYou();
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Hero backdrop: first trending banner; gradient if offline.
          FutureBuilder<List<MediaTitle>>(
            future: _backdrop,
            builder: (context, snap) {
              final url = snap.data
                  ?.map((t) => t.banner ?? t.poster)
                  .whereType<String>()
                  .cast<String?>()
                  .firstWhere((u) => u != null, orElse: () => null);
              if (url == null) return const _FallbackBackdrop();
              final size = MediaQuery.sizeOf(context) *
                  MediaQuery.devicePixelRatioOf(context);
              return Image(
                image: CoverResizeImage(NetworkImage(url),
                    width: size.width.ceil(), height: size.height.ceil()),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const _FallbackBackdrop(),
              );
            },
          ),
          // Readability scrim.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.35, 0.7, 1],
                colors: [
                  Color(0xB3000000),
                  Color(0x66000000),
                  Color(0xCC000000),
                  Color(0xF2000000),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BingelyWordmark()),
                  Expanded(
                    child: PageView(
                      controller: _controller,
                      onPageChanged: (i) => setState(() => _index = i),
                      children: [
                        for (final p in _pages) _PageCopy(page: p),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _continue,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.lg),
                            shape: const StadiumBorder(),
                          ),
                          child: Text('Continue',
                              style: AppTextStyles.rowTitleList),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => widget.onFinish(),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.lg),
                            shape: const StadiumBorder(),
                          ),
                          child: Text('Join',
                              style: AppTextStyles.rowTitleList),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text.rich(
                      const TextSpan(
                        text: 'By continuing, you agree to our ',
                        children: [
                          TextSpan(
                              text: 'Terms',
                              style:
                                  TextStyle(color: AppColors.accentAlt)),
                          TextSpan(text: ' and '),
                          TextSpan(
                              text: 'Privacy Policy',
                              style:
                                  TextStyle(color: AppColors.accentAlt)),
                        ],
                      ),
                      style: AppTextStyles.subtitle,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: AppMotion.tab,
                          curve: AppMotion.standard,
                          width: i == _index ? 20 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: i == _index
                                ? AppColors.accent
                                : AppColors.textDisabled,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
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

class _PageCopy extends StatelessWidget {
  final _Page page;
  const _PageCopy({required this.page});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(page.headline,
            style: AppTextStyles.screenTitle
                .copyWith(fontSize: 36, height: 1.15)),
        Text(page.accent,
            style: AppTextStyles.screenTitle.copyWith(
                fontSize: 36, height: 1.15, color: AppColors.accentAlt)),
        const SizedBox(height: AppSpacing.lg),
        Text(page.body,
            style: AppTextStyles.body
                .copyWith(fontSize: 17, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _FallbackBackdrop extends StatelessWidget {
  const _FallbackBackdrop();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.4),
          radius: 1.2,
          colors: [Color(0xFF3A0000), Color(0xFF000000)],
        ),
      ),
    );
  }
}
