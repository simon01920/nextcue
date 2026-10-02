import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repository.dart';
import 'data/tvdb_repository.dart';
import 'firebase_options.dart';
import 'router.dart';
import 'services/anilist_api.dart';
import 'services/api_cache.dart';
import 'services/auth_service.dart';
import 'services/demo_seed.dart';
import 'services/tvdb_api.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase when configured (flutterfire configure), local accounts until
  // then — same screens, same behavior.
  AuthService authService;
  if (DefaultFirebaseOptions.hasRealConfig) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    authService = FirebaseAuthService();
  } else {
    authService = LocalAuthService();
  }

  final auth = AuthController(authService);
  final appState = AppState();
  final prefs = await SharedPreferences.getInstance();

  // Shared response cache for both catalog APIs: repeat requests are served
  // locally instead of re-spending the free-tier quota (strategy PDF §1).
  final apiCache = ApiCache(prefs);
  final anilist = AniListApi(cache: apiCache);

  final onboarded =
      ValueNotifier<bool>(prefs.getBool('nextcue.onboarded') ?? false);
  await auth.restore();
  if (auth.account != null) {
    await appState.bind(auth.account!.uid, seedDemo: auth.isSeededProfile);
    if (auth.account!.email == demoEmail) {
      await seedDemoContent(appState, anilist);
    }
  }

  final repo = TvdbRepository(
    tvdb: TvdbApi(cache: apiCache),
    anilist: anilist,
    appState: appState,
  );

  // Rebind account data whenever the signed-in account changes.
  auth.addListener(() {
    final a = auth.account;
    if (a != null) {
      appState.bind(a.uid, seedDemo: auth.isSeededProfile).then((_) {
        if (a.email == demoEmail) seedDemoContent(appState, anilist);
      });
    }
  });

  // Seed the ambient palette before the first frame so startup never paints
  // one frame with the wrong neutrals (the MaterialApp builder keeps it in
  // sync from then on).
  AppColors.applyBrightness(switch (appState.themeMode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system =>
      PlatformDispatcher.instance.platformBrightness,
  });

  runApp(NextCueApp(
    auth: auth,
    appState: appState,
    repo: repo,
    onboarded: onboarded,
    apiCache: apiCache,
  ));
}

class NextCueApp extends StatefulWidget {
  final AuthController auth;
  final AppState appState;
  final ContentRepository repo;
  final ValueNotifier<bool> onboarded;
  final ApiCache apiCache;
  const NextCueApp({
    super.key,
    required this.auth,
    required this.appState,
    required this.repo,
    required this.onboarded,
    required this.apiCache,
  });

  @override
  State<NextCueApp> createState() => _NextCueAppState();
}

class _NextCueAppState extends State<NextCueApp> {
  late final router =
      buildRouter(widget.auth, onboarded: widget.onboarded);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.appState),
        ChangeNotifierProvider.value(value: widget.auth),
        Provider<ContentRepository>.value(value: widget.repo),
        Provider<ApiCache>.value(value: widget.apiCache),
      ],
      child: Builder(
        builder: (context) {
          final mode = context.watch<AppState>().themeMode;
          return MaterialApp.router(
            title: 'NextCue',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: mode,
            // The neutral palette is ambient (see AppColors.applyBrightness).
            // Set it here — this builder runs before the app subtree is
            // built, so descendants always paint with the right neutrals —
            // and key the subtree on brightness so a theme flip forces a
            // rebuild of widgets that read the statics directly.
            builder: (context, child) {
              final brightness = Theme.of(context).brightness;
              AppColors.applyBrightness(brightness);
              return KeyedSubtree(
                key: ValueKey(brightness),
                child: child ?? const SizedBox.shrink(),
              );
            },
            routerConfig: router,
          );
        },
      ),
    );
  }
}
