import 'dart:async' show unawaited;
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
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
import 'services/cloud_sync.dart';
import 'services/demo_seed.dart';
import 'services/tvdb_api.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase when configured (flutterfire configure), local accounts until
  // then — same screens, same behavior.
  AuthService authService = LocalAuthService();
  CloudSync? cloud;
  final firebaseOptions = _firebaseOptions();
  if (firebaseOptions != null) {
    try {
      // On web the Firebase JS SDK is fetched from gstatic.com; a blocked
      // network or an ad blocker must leave a working app, not a blank page.
      await Firebase.initializeApp(options: firebaseOptions)
          .timeout(const Duration(seconds: 10));
      // Offline-first: reads come from the local cache when there is no
      // network and writes queue until it returns (web defaults to memory).
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 40 * 1024 * 1024,
      );
      // `--dart-define=USE_FIREBASE_EMULATOR=true` points the app at the
      // local emulators (`firebase emulators:start`), so rules and sync can
      // be tried without touching the real project.
      if (const bool.fromEnvironment('USE_FIREBASE_EMULATOR')) {
        const host = String.fromEnvironment('FIREBASE_EMULATOR_HOST',
            defaultValue: 'localhost');
        await FirebaseAuth.instance.useAuthEmulator(host, 9099);
        FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      }
      authService = FirebaseAuthService();
      cloud = FirestoreCloudSync();
    } catch (e) {
      debugPrint('Firebase unavailable, using on-device accounts: $e');
    }
  }

  final appState = AppState(cloud: cloud);
  // Push queued edits before the session ends so nothing is stranded on
  // this device.
  final auth = AuthController(authService, beforeLogout: appState.syncNow);
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
      // First-run seeding hits the network; never hold the first frame on
      // it (offline it would stall startup for the full request timeout).
      unawaited(seedDemoContent(appState, anilist));
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

/// The generated Firebase config for this platform, or null when Firebase
/// isn't set up (the placeholder firebase_options.dart, or a platform that
/// `flutterfire configure` skipped; both throw UnsupportedError). Detecting
/// it this way means regenerating firebase_options.dart needs no other edit.
FirebaseOptions? _firebaseOptions() {
  try {
    return DefaultFirebaseOptions.currentPlatform;
  } on UnsupportedError {
    return null;
  }
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

  // Flush pending writes when the app is backgrounded: mobile OSes may kill
  // a paused app without another callback.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onPause: () => widget.appState.syncNow(),
    onHide: () => widget.appState.syncNow(),
  );

  @override
  void initState() {
    super.initState();
    _lifecycle; // instantiate the lazy listener
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

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
              return BackdropGroup(
                child: KeyedSubtree(
                  key: ValueKey(brightness),
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            routerConfig: router,
          );
        },
      ),
    );
  }
}
