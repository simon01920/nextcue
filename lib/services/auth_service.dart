import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider_config.dart';

/// A signed-in Bingely account.
@immutable
class Account {
  final String uid;
  final String email;
  final String displayName;
  const Account({
    required this.uid,
    required this.email,
    required this.displayName,
  });
}

abstract class AuthService {
  Future<Account?> restore();
  Future<Account> register(String email, String password, String displayName);
  Future<Account> login(String email, String password);
  Future<void> logout();

  /// Whether [sendPasswordReset] can do anything (needs an email backend).
  bool get supportsPasswordReset => false;

  Future<void> sendPasswordReset(String email) async =>
      throw AuthException('Password reset needs an online account.');

  /// Whether [signInWithGoogle] is available (Firebase-backed only).
  bool get supportsGoogle => false;

  /// Signs in with a Google account. Throws [AuthCancelled] when the user
  /// closes the account picker.
  Future<Account> signInWithGoogle() async =>
      throw AuthException('Google sign-in needs an online account.');

  /// Whether [signInWithApple] is offered (Firebase-backed, and enabled in
  /// auth_provider_config.dart once Apple is configured).
  bool get supportsApple => false;

  Future<Account> signInWithApple() async =>
      throw AuthException('Apple sign-in needs an online account.');
}

/// The user dismissed a sign-in prompt: not an error to show.
class AuthCancelled extends AuthException {
  AuthCancelled() : super('Sign-in cancelled.');
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// On-device account store: salted SHA-256 password hashes in
/// shared_preferences. Active whenever Firebase isn't configured, so the
/// login/register flow works out of the box.
class LocalAuthService extends AuthService {
  static const _usersKey = 'bingely.users';
  static const _sessionKey = 'bingely.session';

  Future<Map<String, dynamic>> _users(SharedPreferences p) async =>
      (jsonDecode(p.getString(_usersKey) ?? '{}') as Map<String, dynamic>);

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

  @override
  Future<Account?> restore() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_sessionKey);
    if (raw == null) return null;
    final s = jsonDecode(raw) as Map<String, dynamic>;
    return Account(
      uid: s['uid'] as String,
      email: s['email'] as String,
      displayName: s['name'] as String,
    );
  }

  @override
  Future<Account> register(
    String email,
    String password,
    String displayName,
  ) async {
    final p = await SharedPreferences.getInstance();
    final users = await _users(p);
    final key = email.trim().toLowerCase();
    if (key.isEmpty || !key.contains('@')) {
      throw AuthException('Enter a valid email address.');
    }
    if (password.length < 6) {
      throw AuthException('Password must be at least 6 characters.');
    }
    if (users.containsKey(key)) {
      throw AuthException('An account with this email already exists.');
    }
    final salt = DateTime.now().microsecondsSinceEpoch.toString();
    final uid =
        'local-${sha256.convert(utf8.encode(key)).toString().substring(0, 12)}';
    users[key] = {
      'salt': salt,
      'hash': _hash(password, salt),
      'name': displayName.trim().isEmpty ? key.split('@').first : displayName,
      'uid': uid,
    };
    await p.setString(_usersKey, jsonEncode(users));
    final account = Account(
      uid: uid,
      email: key,
      displayName: (users[key] as Map<String, dynamic>)['name'] as String,
    );
    await p.setString(
      _sessionKey,
      jsonEncode({
        'uid': account.uid,
        'email': key,
        'name': account.displayName,
      }),
    );
    return account;
  }

  @override
  Future<Account> login(String email, String password) async {
    final p = await SharedPreferences.getInstance();
    final users = await _users(p);
    final key = email.trim().toLowerCase();
    final u = users[key] as Map<String, dynamic>?;
    if (u == null) {
      throw AuthException('No account found for this email — register first.');
    }
    if (_hash(password, u['salt'] as String) != u['hash']) {
      throw AuthException('Incorrect password.');
    }
    final account = Account(
      uid: u['uid'] as String,
      email: key,
      displayName: u['name'] as String,
    );
    await p.setString(
      _sessionKey,
      jsonEncode({
        'uid': account.uid,
        'email': key,
        'name': account.displayName,
      }),
    );
    return account;
  }

  @override
  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_sessionKey);
  }
}

/// Firebase-backed accounts. Selected automatically when
/// main.dart finds a generated firebase_options.dart (`flutterfire configure`).
class FirebaseAuthService extends AuthService {
  fb.FirebaseAuth get _auth => fb.FirebaseAuth.instance;

  Account _map(fb.User u) => Account(
    uid: u.uid,
    email: u.email ?? '',
    displayName: u.displayName ?? (u.email ?? 'user').split('@').first,
  );

  @override
  Future<Account?> restore() async {
    // currentUser is null until the persisted session has been restored
    // (asynchronous on web), so reading it right after initializeApp
    // signs returning users out. The first authStateChanges event is the
    // restored state.
    final u =
        _auth.currentUser ??
        await _auth.authStateChanges().first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
    return u == null ? null : _map(u);
  }

  @override
  Future<Account> register(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final name = displayName.trim();
      if (name.isNotEmpty) await cred.user!.updateDisplayName(name);
      // The User object from the credential predates updateDisplayName.
      final a = _map(cred.user!);
      return name.isEmpty
          ? a
          : Account(uid: a.uid, email: a.email, displayName: name);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(friendlyFirebaseError(e.code, 'Registration'));
    }
  }

  @override
  Future<Account> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _map(cred.user!);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(friendlyFirebaseError(e.code, 'Login'));
    }
  }

  @override
  Future<void> logout() async {
    // google_sign_in is only initialized off the web (the web flow is
    // Firebase's popup), and signOut on an uninitialized instance throws.
    if (!kIsWeb && _googleReady != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }

  // Google ---------------------------------------------------------------

  /// OAuth "Web client" id of the Firebase project. Android needs it as the
  /// server client id to receive an ID token for Firebase; it is public (it
  /// ships in google-services.json as default_web_client_id).
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: kGoogleServerClientId,
  );

  /// iOS OAuth client id (also public; from GoogleService-Info.plist).
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: kGoogleIosClientId,
  );

  Future<void>? _googleReady;

  Future<void> _initGoogle() =>
      _googleReady ??= GoogleSignIn.instance
          .initialize(
            clientId:
                defaultTargetPlatform == TargetPlatform.iOS &&
                        googleIosClientId.isNotEmpty
                    ? googleIosClientId
                    : null,
            serverClientId:
                googleServerClientId.isEmpty ? null : googleServerClientId,
          )
          .catchError((Object e) {
            _googleReady = null; // allow a retry after a config fix
            throw e;
          });

  @override
  bool get supportsGoogle => true;

  @override
  Future<Account> signInWithGoogle() async {
    try {
      final fb.UserCredential cred;
      if (kIsWeb) {
        // Firebase's popup flow: no client id or meta tag needed, and
        // google_sign_in's web init would hang without one.
        cred = await _auth.signInWithPopup(
          fb.GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}),
        );
      } else {
        await _initGoogle();
        final account = await GoogleSignIn.instance.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          throw AuthException('Google did not return an ID token.');
        }
        cred = await _auth.signInWithCredential(
          fb.GoogleAuthProvider.credential(idToken: idToken),
        );
      }
      return _map(cred.user!);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw AuthCancelled();
      }
      throw AuthException('Google sign-in failed (${e.code.name}).');
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        throw AuthCancelled();
      }
      throw AuthException(friendlyFirebaseError(e.code, 'Google sign-in'));
    }
  }

  // Apple ----------------------------------------------------------------

  @override
  bool get supportsApple => kAppleSignInEnabled;

  @override
  Future<Account> signInWithApple() async {
    final provider =
        fb.AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');
    try {
      // Native sheet on iOS/macOS; Apple's web flow (popup / Custom Tab)
      // elsewhere, which needs the Services ID configured in Firebase.
      final cred =
          kIsWeb
              ? await _auth.signInWithPopup(provider)
              : await _auth.signInWithProvider(provider);
      final user = cred.user!;
      // Apple sends the name only on the very first sign-in; keep it.
      final given = cred.additionalUserInfo?.profile?['name'];
      var name = user.displayName;
      if ((name == null || name.isEmpty) && given is Map) {
        name =
            [
              given['firstName'],
              given['lastName'],
            ].whereType<String>().join(' ').trim();
        if (name.isNotEmpty) await user.updateDisplayName(name);
      }
      final a = _map(user);
      return name == null || name.isEmpty
          ? a
          : Account(uid: a.uid, email: a.email, displayName: name);
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'canceled' ||
          e.code == 'web-context-canceled' ||
          e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        throw AuthCancelled();
      }
      throw AuthException(friendlyFirebaseError(e.code, 'Apple sign-in'));
    }
  }

  @override
  bool get supportsPasswordReset => true;

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      // Don't reveal whether an account exists for the address.
      if (e.code == 'user-not-found') return;
      throw AuthException(friendlyFirebaseError(e.code, 'Password reset'));
    }
  }
}

/// Firebase's own messages are developer-facing ("The supplied auth
/// credential is incorrect, malformed or has expired."); map the common
/// codes to plain sentences.
String friendlyFirebaseError(String code, String action) => switch (code) {
  'invalid-email' => 'Enter a valid email address.',
  'weak-password' => 'Password must be at least 6 characters.',
  'email-already-in-use' => 'An account with this email already exists.',
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'Incorrect email or password.',
  'user-disabled' => 'This account has been disabled.',
  'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
  'network-request-failed' => 'No connection. Check your network.',
  'operation-not-allowed' =>
    'This sign-in method is not enabled for this app yet.',
  'account-exists-with-different-credential' =>
    'This email already has an account. Log in with your password.',
  'popup-blocked' => 'Allow pop-ups for this site, then try again.',
  'unauthorized-domain' => 'This domain is not authorized for sign-in yet.',
  _ => '$action failed ($code).',
};

/// App-facing auth state. Router redirects hang off this notifier.
class AuthController extends ChangeNotifier {
  final AuthService service;
  Account? _account;
  bool _restored = false;

  AuthController(this.service, {this.beforeLogout});

  /// Runs before signing out while the account is still authenticated
  /// (Firestore rules reject writes after sign-out).
  final Future<void> Function()? beforeLogout;

  Account? get account => _account;
  bool get loggedIn => _account != null;
  bool get restored => _restored;

  /// Emails whose first registration claims the seeded demo profile; set at
  /// build time with --dart-define=CLAIMED_EMAILS=a@x.com,b@y.com (see .env.example).
  static final claimedEmails =
      const String.fromEnvironment('CLAIMED_EMAILS')
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();

  bool get isSeededProfile =>
      _account != null && claimedEmails.contains(_account!.email.toLowerCase());

  Future<void> restore() async {
    _account = await service.restore();
    _restored = true;
    notifyListeners();
  }

  Future<void> register(String email, String password, String name) async {
    _account = await service.register(email, password, name);
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    _account = await service.login(email, password);
    notifyListeners();
  }

  bool get supportsPasswordReset => service.supportsPasswordReset;
  bool get supportsGoogle => service.supportsGoogle;
  bool get supportsApple => service.supportsApple;

  Future<void> signInWithApple() async {
    _account = await service.signInWithApple();
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    _account = await service.signInWithGoogle();
    notifyListeners();
  }

  Future<void> sendPasswordReset(String email) =>
      service.sendPasswordReset(email);

  Future<void> logout() async {
    try {
      await beforeLogout?.call();
    } catch (_) {
      // Never block sign-out on a sync failure.
    }
    await service.logout();
    _account = null;
    notifyListeners();
  }
}
