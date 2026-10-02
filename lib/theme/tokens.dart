import 'package:flutter/material.dart';

/// Design tokens — SOLE source of truth, mirrors 03-design-spec/DESIGN.md.
/// Screens and widgets consume these constants; no raw literals elsewhere.
class AppColors {
  AppColors._();

  /// Ambient brightness for the neutral palette.
  ///
  /// The neutral tokens below are consumed in ~150 places as plain values
  /// (`color: AppColors.textPrimary`). Rather than thread a BuildContext
  /// through every one of them, the palette flips with the active theme:
  /// [AppTheme] calls [applyBrightness] from the MaterialApp builder before
  /// the subtree is built, so a rebuild always paints the right neutrals.
  /// Brand colours (accent, link, success…) are theme-invariant and stay
  /// `const`.
  static bool _light = false;
  static bool get isLight => _light;

  /// Returns true when the value changed, so callers can decide to rebuild.
  static bool applyBrightness(Brightness brightness) {
    final next = brightness == Brightness.light;
    if (next == _light) return false;
    _light = next;
    return true;
  }

  // Neutrals — resolve against the active theme.
  static Color get bgPrimary => _light ? lightBg : _darkBg;
  static Color get surface => _light ? lightSurface : _darkSurface;
  static Color get surfaceElevated =>
      _light ? lightSkeleton : _darkSurfaceElevated;
  static Color get divider => _light ? lightDivider : _darkDivider;
  static Color get borderSubtle => _light ? lightDivider : _darkBorderSubtle;
  static Color get textPrimary => _light ? lightTextPrimary : _darkTextPrimary;
  static Color get textSecondary =>
      _light ? lightTextSecondary : _darkTextSecondary;
  static Color get textMuted => _light ? lightTextMuted : _darkTextMuted;
  static Color get textDisabled => _light ? lightTextMuted : _darkTextDisabled;

  // Neutrals — dark theme values (the measured source palette).
  static const Color _darkBg = Color(0xFF000000);
  static const Color _darkSurface = Color(0xFF202020);
  static const Color _darkSurfaceElevated = Color(0xFF2B2B2B);
  static const Color _darkDivider = Color(0xFF1E1E1E);
  static const Color _darkBorderSubtle = Color(0xFF333333);
  static const Color _darkTextPrimary = Color(0xFFFFFFFF);
  static const Color _darkTextSecondary = Color(0xFFC0C0C0);
  static const Color _darkTextMuted = Color(0xFF858585);
  static const Color _darkTextDisabled = Color(0xFF808080);

  // Neutrals — light theme
  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF1F1F3);
  static const Color lightSkeleton = Color(0xFFE7E7EA);
  static const Color lightTextPrimary = Color(0xFF101014);
  static const Color lightTextSecondary = Color(0xFF3F3F46);
  static const Color lightTextMuted = Color(0xFF6B6B75);
  static const Color lightDivider = Color(0xFFD9D9DF);

  // Accents (theme-invariant) — Bingely red identity (rebrand from
  // the source app's yellow; every other token stays measured-true).
  static const Color accent = Color(0xFFE60000);
  static const Color accentInk = Color(0xFFFFFFFF);
  static const Color accentAlt = Color(0xFFFF3B30);
  static const Color link = Color(0xFF1A75FF);
  static const Color linkAlt = Color(0xFF0066FF);
  static const Color success = Color(0xFF66CC00);
  static const Color love = Color(0xFFE60000);
  static const Color error = Color(0xFFFA3942);
  static const Color errorSnackbarBg = Color(0xFFFFD9DC);

  // Component colors
  static const Color checkRingUnwatched = Color(0xFFF5F5F5);
  static const Color premiereBg = Color(0xFFF6EED5);
  static const Color premiereText = Color(0xFF2A3556);
  static const Color overlayScrim = Color(0x99000000);
  static const Color bannerScrim = Color(0xBF000000);
  static const Color unofficialRed = Color(0xFFE60000);
}

class AppSpacing {
  AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  AppRadius._();
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double pill = 999;
}

class AppShadows {
  AppShadows._();
  static const List<BoxShadow> none = [];
  static const List<BoxShadow> fab = [
    BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> menu = [
    BoxShadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
}

class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration tab = Duration(milliseconds: 250);
  static const Duration check = Duration(milliseconds: 300);
  static const Duration page = Duration(milliseconds: 200);
  // Glass indicator slides (nav pill, segmented tabs): longer + strong
  // ease-out so the pill glides rather than snaps.
  static const Duration slide = Duration(milliseconds: 340);
  static const Curve glide = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Curve standard = Cubic(0.4, 0, 0.2, 1);
  static const Curve pop = Cubic(0.34, 1.56, 0.64, 1);
  static const Curve easeOut = Curves.easeOut;
}

class AppBreakpoints {
  AppBreakpoints._();
  static const double contentMax = 1023;
  static const double phone = 600;
  static const double tablet = 1024;

  static int gridColumns(double width) {
    if (width < phone) return 3;
    if (width < tablet) return 4;
    return 6;
  }
}

class AppLayout {
  AppLayout._();
  static const double topTabBarHeight = 42;
  static const double tabUnderline = 4;
  static const double bottomNavHeight = 56;
  static const double bannerExpanded = 180;
  static const double bannerCollapsed = 56;
  static const double progressBarHeight = 4;
  static const double checkCircle = 44;
  static const double episodeThumb = 88;
  static const double railPosterW = 106;
  static const double railPosterH = 155;
  static const double castCardW = 104;
  static const double castPhoto = 104;
  static const double avatarLg = 64;
  static const double avatarSm = 36;
  static const double providerSquare = 72;
  static const double emotionChip = 72;
  static const double starSize = 44;
  static const double fabSize = 56;
  static const double gridGap = 6;
}

class AppTextStyles {
  AppTextStyles._();

  static const String uiFamily = 'Figtree';
  static const String displayFamily = 'Anton';

  static TextStyle get displayStat => TextStyle(
    fontFamily: displayFamily,
    fontSize: 26,
    fontWeight: FontWeight.w400,
    height: 1.0,
    color: AppColors.textPrimary,
  );

  static TextStyle get screenTitle => TextStyle(
    fontFamily: uiFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static TextStyle get sectionHeader => TextStyle(
    fontFamily: uiFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  static TextStyle get rowTitle => TextStyle(
    fontFamily: uiFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static TextStyle get rowTitleList => TextStyle(
    fontFamily: uiFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static TextStyle get body => TextStyle(
    fontFamily: uiFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: AppColors.textPrimary,
  );

  static TextStyle get subtitle => TextStyle(
    fontFamily: uiFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
    color: AppColors.textMuted,
  );

  static TextStyle get captionCaps => TextStyle(
    fontFamily: uiFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.5,
    color: AppColors.textDisabled,
  );

  static TextStyle get microCaps => TextStyle(
    fontFamily: uiFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.4,
    color: AppColors.textDisabled,
  );

  static TextStyle get counterAccent => TextStyle(
    fontFamily: uiFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.0,
    color: AppColors.textMuted,
  );

  static TextStyle get tabLabel => TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: 0.5,
    color: AppColors.textSecondary,
  );

  static TextStyle get tabLabelActive => TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get navLabel => TextStyle(
    fontFamily: uiFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.0,
    color: AppColors.textDisabled,
  );

  static TextStyle get navLabelActive => TextStyle(
    fontFamily: uiFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.0,
    color: AppColors.textPrimary,
  );

  static TextStyle get buttonPillCaps => const TextStyle(
    fontFamily: uiFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0.5,
    color: AppColors.accentInk,
  );

  static TextStyle get linkText => const TextStyle(
    fontFamily: uiFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppColors.link,
  );
}

/// Semantic icon asset lookup — files live flat in assets/icons/ with
/// their source path flattened using '__' (see 05-build/notes.md).
class AppIcons {
  AppIcons._();
  static const String _p = 'assets/icons/';

  static const String navShows = '${_p}icons__main__shows.svg';
  static const String navMovies = '${_p}icons__main__movies.svg';
  static const String navExplore = '${_p}icons__main__explore.svg';
  static const String navProfile = '${_p}icons__main__profile.svg';

  static const String checkWatched = '${_p}icons__checkmark_watched.svg';
  static const String checkNotWatched = '${_p}icons__checkmark_not_watched.svg';
  static const String checkYellow = '${_p}icons__checkmark_yellow.svg';
  static const String ctaPlus = '${_p}icons__cta_plus.svg';
  static const String ctaCheck = '${_p}icons__cta_check.svg';
  static const String heartSelected = '${_p}icons__heart_solid_selected.svg';
  static const String heartUnselected = '${_p}icons__heart_solid_unselected.svg';
  static const String bell = '${_p}icons__notification_bell.svg';
  static const String flag = '${_p}icons__flag.svg';
  static const String bubble = '${_p}icons__bubble.svg';
  static const String gridActive = '${_p}icons__grid_active.svg';
  static const String gridInactive = '${_p}icons__grid_inactive.svg';
  static const String gear = '${_p}icons__gear_solid.svg';
  static const String filter = '${_p}icons__filter.svg';
  static const String chevronRight = '${_p}icons__chevron_right.svg';
  static const String chevronBack = '${_p}icons__chevron_back.svg';
  static const String arrowDown = '${_p}icons__arrow_down.svg';
  static const String calendar = '${_p}icons__calendar.svg';
  static const String airdate = '${_p}icons__airdate.svg';
  static const String duration = '${_p}icons__duration.svg';
  static const String fans = '${_p}icons__fans.svg';
  static const String edit = '${_p}icons__edit.svg';
  static const String findFriends = '${_p}icons__find_friends.svg';
  static const String noCover = '${_p}icons__no_cover.svg';
  static const String addToList = '${_p}icons__add_to_list.svg';
  static const String close = '${_p}icons__close.svg';
  static const String clear = '${_p}icons__clear.svg';
  static const String comments = '${_p}icons__comments.svg';

  static const String animWatched = 'assets/animations/animations__watched.json';
  static const String animRemove = 'assets/animations/animations__remove.json';
  static const String animRecommendations =
      'assets/animations/animations__recommendations.json';
}
