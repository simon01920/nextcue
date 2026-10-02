// PLACEHOLDER — replace by running:
//   dart pub global activate flutterfire_cli
//   flutterfire configure
// which regenerates this file with your real Firebase project config.
//
// Until then `hasRealConfig` is false and the app uses the on-device
// account store (same screens, same rules) so nothing blocks.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const bool hasRealConfig = false;

  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured yet. Run `flutterfire configure` to '
      'generate real options; the app falls back to local accounts.',
    );
  }
}
