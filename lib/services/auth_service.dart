import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A signed-in Bingely account.
@immutable
class Account {
  final String uid;
  final String email;
  final String displayName;
  const Account(
      {required this.uid, required this.email, required this.displayName});
}

abstract class AuthService {
  Future<Account?> restore();
  Future<Account> register(String email, String password, String displayName);
  Future<Account> login(String email, String password);
  Future<void> logout();
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
class LocalAuthService implements AuthService {
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
        displayName: s['name'] as String);
  }

  @override
  Future<Account> register(
      String email, String password, String displayName) async {
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
    final uid = 'local-${sha256.convert(utf8.encode(key)).toString().substring(0, 12)}';
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
        displayName: (users[key] as Map<String, dynamic>)['name'] as String);
    await p.setString(
        _sessionKey,
        jsonEncode(
            {'uid': account.uid, 'email': key, 'name': account.displayName}));
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
        displayName: u['name'] as String);
    await p.setString(
        _sessionKey,
        jsonEncode(
            {'uid': account.uid, 'email': key, 'name': account.displayName}));
    return account;
  }

  @override
  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_sessionKey);
  }
}

/// Firebase-backed accounts. Selected automatically when
/// DefaultFirebaseOptions.hasRealConfig is true (after `flutterfire configure`).
class FirebaseAuthService implements AuthService {
  fb.FirebaseAuth get _auth => fb.FirebaseAuth.instance;

  Account _map(fb.User u) => Account(
      uid: u.uid,
      email: u.email ?? '',
      displayName: u.displayName ?? (u.email ?? 'user').split('@').first);

  @override
  Future<Account?> restore() async {
    // currentUser is null until the persisted session has been restored
    // (asynchronous on web), so reading it right after initializeApp
    // signs returning users out. The first authStateChanges event is the
    // restored state.
    final u = _auth.currentUser ??
        await _auth
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
    return u == null ? null : _map(u);
  }

  @override
  Future<Account> register(
      String email, String password, String displayName) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      if (displayName.trim().isNotEmpty) {
        await cred.user!.updateDisplayName(displayName.trim());
      }
      return _map(cred.user!);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Registration failed (${e.code}).');
    }
  }

  @override
  Future<Account> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return _map(cred.user!);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Login failed (${e.code}).');
    }
  }

  @override
  Future<void> logout() => _auth.signOut();
}

/// App-facing auth state. Router redirects hang off this notifier.
class AuthController extends ChangeNotifier {
  final AuthService service;
  Account? _account;
  bool _restored = false;

  AuthController(this.service);

  Account? get account => _account;
  bool get loggedIn => _account != null;
  bool get restored => _restored;

  /// Emails whose first registration claims the seeded demo profile; set at
  /// build time with --dart-define=CLAIMED_EMAILS=a@x.com,b@y.com (see .env.example).
  static final claimedEmails = const String.fromEnvironment('CLAIMED_EMAILS')
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

  Future<void> logout() async {
    await service.logout();
    _account = null;
    notifyListeners();
  }
}
