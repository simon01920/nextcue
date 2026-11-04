// PLACEHOLDER — replace by running:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
// which regenerates this file with your real Firebase project config.
//
// Until then currentPlatform throws UnsupportedError, main.dart catches it
// and the app uses the on-device account store (same screens), so nothing
// blocks. The generated file needs no edits: main.dart detects it.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured yet. Run `flutterfire configure` to '
      'generate real options; the app falls back to local accounts.',
    );
  }
}
