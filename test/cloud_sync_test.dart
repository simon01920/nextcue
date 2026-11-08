import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtrack/services/auth_service.dart';
import 'package:showtrack/services/cloud_sync.dart';
import 'package:showtrack/state/app_state.dart';

/// In-memory stand-in for Firestore: one merged map per uid.
class FakeCloud implements CloudSync {
  @override
  Future<void> delete(String uid) async => docs.remove(uid);

  final Map<String, Map<String, Object?>> docs = {};
  int saves = 0;
  bool offline = false;

  @override
  Future<Map<String, Object?>?> load(String uid) async {
    if (offline) return null;
    final d = docs[uid];
    return d == null ? null : Map.of(d);
  }

  @override
  Future<void> save(String uid, Map<String, Object?> fields) async {
    if (offline) throw StateError('offline');
    saves++;
    (docs[uid] ??= {}).addAll(fields);
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first sign-in uploads this device\'s data', () async {
    final cloud = FakeCloud();
    final s = AppState(cloud: cloud, cloudDebounce: Duration.zero);
    await s.bind('u');
    s.setStatus('series-1', TrackStatus.watching);
    await _settle();
    await s.syncNow();
    expect(cloud.docs['u']!['statuses'], contains('series-1'));
    expect(cloud.docs['u']!.keys, containsAll(AppState.persistedKeys));
  });

  test('a second device picks up the cloud copy', () async {
    final cloud = FakeCloud();
    final a = AppState(cloud: cloud, cloudDebounce: Duration.zero);
    await a.bind('u');
    a.setManyWatched(['series-1:1:1', 'series-1:1:2'], true);
    a.setThemeMode(ThemeMode.light);
    await a.syncNow();

    // Fresh device: empty local storage, same account.
    SharedPreferences.setMockInitialValues({});
    final b = AppState(cloud: cloud, cloudDebounce: Duration.zero);
    await b.bind('u');
    await _settle();
    expect(b.watchedCountFor('series-1'), 2);
    expect(b.themeMode, ThemeMode.light);
  });

  test('edits made before the cloud copy arrives are kept', () async {
    final cloud = FakeCloud()
      ..docs['u'] = {'statuses': '{"series-9":"completed"}'};
    final s = AppState(cloud: cloud, cloudDebounce: Duration.zero);
    final bound = s.bind('u');
    await bound;
    // Edit immediately, before the pull has been applied.
    s.setStatus('series-2', TrackStatus.watching);
    await _settle();
    expect(s.statusOf('series-2'), TrackStatus.watching);
  });

  test('rapid edits become one cloud write', () async {
    final cloud = FakeCloud();
    final s = AppState(
        cloud: cloud, cloudDebounce: const Duration(milliseconds: 50));
    await s.bind('u');
    await _settle();
    await s.syncNow(); // initial upload
    final before = cloud.saves;
    for (var i = 1; i <= 20; i++) {
      s.setWatched('series-1:1:$i', true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(cloud.saves - before, 1);
    expect(s.watchedCountFor('series-1'), 20);
  });

  test('offline save is retried on the next sync', () async {
    final cloud = FakeCloud();
    final s = AppState(cloud: cloud, cloudDebounce: Duration.zero);
    await s.bind('u');
    await _settle();
    cloud.offline = true;
    s.rate('series-1:1:1', 5);
    await s.syncNow();
    cloud.offline = false;
    await s.syncNow();
    expect(cloud.docs['u']!['ratings'], contains('series-1:1:1'));
  });

  test('corrupt cloud fields are ignored, not loaded', () async {
    final cloud = FakeCloud()
      ..docs['u'] = {'ratings': 'not json', 'themeMode': 99};
    final s = AppState(cloud: cloud, cloudDebounce: Duration.zero);
    await s.bind('u');
    await _settle();
    expect(s.ratingOf('x'), isNull);
    expect(s.themeMode, ThemeMode.values.last);
  });

  test('logout runs the sync hook first', () async {
    var synced = false;
    final auth = AuthController(LocalAuthService(), beforeLogout: () async {
      synced = true;
    });
    await auth.register('a@b.co', 'Tape4Rewind', 'A');
    await auth.logout();
    expect(synced, isTrue);
    expect(auth.loggedIn, isFalse);
  });

  test('Firebase error codes map to readable messages', () {
    expect(friendlyFirebaseError('invalid-credential', 'Login'),
        'Incorrect email or password.');
    expect(friendlyFirebaseError('weird-code', 'Login'),
        'Login failed (weird-code).');
  });

  test('watching an episode adds the show; an explicit status stays', () async {
    final s = AppState();
    await s.bind('u1');
    s.setWatched('series-1:1:1', true);
    expect(s.statusOf('series-1'), TrackStatus.watching);
    s.setStatus('series-2', TrackStatus.completed);
    s.setManyWatched(['series-2:1:1', 'series-2:1:2'], true);
    expect(s.statusOf('series-2'), TrackStatus.completed);
  });

  test('password policy, change password, and delete erases everything',
      () async {
    final cloud = FakeCloud();
    final state = AppState(cloud: cloud, cloudDebounce: Duration.zero);
    final auth = AuthController(LocalAuthService(), eraseData: state.eraseAccount);
    expect(() => auth.register('jane@b.co', 'jane1234', 'Jane'),
        throwsA(isA<AuthException>()));
    await auth.register('jane@b.co', 'Tape4Rewind', 'Jane');
    final uid = auth.account!.uid;
    await state.bind(uid);
    state.setWatched('series-9:1:1', true);
    await state.syncNow();
    expect(cloud.docs[uid], isNotNull);

    expect(() => auth.changePassword('wrong', 'Vhs2Cassette'),
        throwsA(isA<AuthException>()));
    await auth.changePassword('Tape4Rewind', 'Vhs2Cassette');

    await expectLater(auth.deleteAccount(password: 'Tape4Rewind'),
        throwsA(isA<AuthException>()));
    await auth.deleteAccount(password: 'Vhs2Cassette');
    expect(auth.loggedIn, isFalse);
    expect(cloud.docs[uid], isNull);
    final p = await SharedPreferences.getInstance();
    expect(p.getKeys().where((k) => k.startsWith('bingely.$uid.')), isEmpty);
    expect(() => LocalAuthService().login('jane@b.co', 'Vhs2Cassette'),
        throwsA(isA<AuthException>()));
  });
}
