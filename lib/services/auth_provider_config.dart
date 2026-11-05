// Sign-in provider configuration for the Firebase project nextcue-5085d.
// These are public identifiers (they ship inside google-services.json and
// GoogleService-Info.plist), not secrets. Override at build time with
// --dart-define=GOOGLE_SERVER_CLIENT_ID=... / GOOGLE_IOS_CLIENT_ID=...

/// "Web client (auto created by Google Service)": Android's serverClientId.
const String kGoogleServerClientId =
    '63944566183-2lqi51djof0eqjiu43shnmp8sl7ronqv.apps.googleusercontent.com';

/// iOS client id (CLIENT_ID in GoogleService-Info.plist).
const String kGoogleIosClientId =
    '63944566183-vtulk3vfvkgvq7jlbvotmltn7b341585.apps.googleusercontent.com';

/// Sign in with Apple. Off until the Apple side exists (an Apple Developer
/// Program membership, a Services ID and a key, entered in Firebase Console
/// → Authentication → Apple). App Store rule 4.8: an iOS build that offers
/// Google sign-in must also offer Sign in with Apple, so turn this on
/// before submitting to the App Store.
const bool kAppleSignInEnabled =
    bool.fromEnvironment('APPLE_SIGN_IN', defaultValue: false);
