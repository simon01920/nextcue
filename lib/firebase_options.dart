// Firebase configuration for project nextcue-5085d, in the layout
// `flutterfire configure` generates (re-running it overwrites this file;
// main.dart needs no change either way).
//
// These values are client identifiers, not secrets: the web ones ship to
// every browser that opens the app. Access to data is enforced by
// firestore.rules and Firebase Auth, and the browser key is restricted to
// the app's own domains in Google Cloud.
// ignore_for_file: lines_longer_than_80_chars
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Firebase is not configured for $defaultTargetPlatform; the app '
          'falls back to on-device accounts there.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '',
    appId: '1:63944566183:web:6edbdafead58f36d54c282',
    messagingSenderId: '63944566183',
    projectId: 'nextcue-5085d',
    authDomain: 'nextcue-5085d.firebaseapp.com',
    storageBucket: 'nextcue-5085d.firebasestorage.app',
    measurementId: 'G-Q9HR5J0DV5',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '',
    appId: '1:63944566183:android:169d86c925b6518754c282',
    messagingSenderId: '63944566183',
    projectId: 'nextcue-5085d',
    storageBucket: 'nextcue-5085d.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '',
    appId: '1:63944566183:ios:74d623dcf57495b154c282',
    messagingSenderId: '63944566183',
    projectId: 'nextcue-5085d',
    storageBucket: 'nextcue-5085d.firebasestorage.app',
    iosClientId: '63944566183-vtulk3vfvkgvq7jlbvotmltn7b341585.apps.googleusercontent.com',
    iosBundleId: 'app.simondev.nextcue',
  );
}
