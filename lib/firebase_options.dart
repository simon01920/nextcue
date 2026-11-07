// Firebase configuration for project nextcue-5085d, in the layout
// `flutterfire configure` generates.
//
// The API keys are NOT in source control. They are passed at build time
// from the git-ignored .env file:
//
//   flutter run --dart-define-from-file=.env
//
// (see .env.example; `tools/firebase_env.sh` writes .env from the Firebase
// project). Without them, Firebase is reported as not configured for the
// platform and the app falls back to on-device accounts.
//
// The remaining ids are public identifiers. Data access is enforced by
// firestore.rules and Firebase Auth, and each key is restricted in Google
// Cloud to its own app (web referrers, iOS bundle id, Android package).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

const String _webKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
const String _androidKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
const String _iosKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return _require(web);
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _require(android);
      case TargetPlatform.iOS:
        return _require(ios);
      default:
        throw UnsupportedError(
          'Firebase is not configured for $defaultTargetPlatform; the app '
          'falls back to on-device accounts there.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _webKey,
    appId: '1:63944566183:web:6edbdafead58f36d54c282',
    messagingSenderId: '63944566183',
    projectId: 'nextcue-5085d',
    authDomain: 'nextcue-5085d.firebaseapp.com',
    storageBucket: 'nextcue-5085d.firebasestorage.app',
    measurementId: 'G-Q9HR5J0DV5',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _androidKey,
    appId: '1:63944566183:android:169d86c925b6518754c282',
    messagingSenderId: '63944566183',
    projectId: 'nextcue-5085d',
    storageBucket: 'nextcue-5085d.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: _iosKey,
    appId: '1:63944566183:ios:74d623dcf57495b154c282',
    messagingSenderId: '63944566183',
    projectId: 'nextcue-5085d',
    storageBucket: 'nextcue-5085d.firebasestorage.app',
    iosClientId: '63944566183-vtulk3vfvkgvq7jlbvotmltn7b341585.apps.googleusercontent.com',
    iosBundleId: 'app.simondev.nextcue',
  );

  /// A build without the key for this platform runs on local accounts.
  static FirebaseOptions _require(FirebaseOptions o) {
    if (o.apiKey.isEmpty) {
      throw UnsupportedError(
        'Firebase API key not provided; build with '
        '--dart-define-from-file=.env (see .env.example).',
      );
    }
    return o;
  }
}
