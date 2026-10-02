import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The NextCue mark: red rounded square with a white N — original identity
/// in the same square-letter badge geometry family.
class BingelyMark extends StatelessWidget {
  final double size;
  const BingelyMark({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Text(
        'N',
        style: TextStyle(
          fontFamily: AppTextStyles.displayFamily,
          fontSize: size * 0.62,
          height: 1.0,
          color: AppColors.accentInk,
        ),
      ),
    );
  }
}

/// "NextCue" wordmark used on the auth and onboarding screens.
class BingelyWordmark extends StatelessWidget {
  const BingelyWordmark({super.key});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BingelyMark(size: 44),
        const SizedBox(width: AppSpacing.md),
        Text(
          'NextCue',
          style: AppTextStyles.screenTitle.copyWith(fontSize: 30),
        ),
      ],
    );
  }
}
