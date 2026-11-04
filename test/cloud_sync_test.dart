import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showtrack/services/auth_service.dart';
import 'package:showtrack/services/cloud_sync.dart';
import 'package:showtrack/state/app_state.dart';

/// In-memory stand-in for Firestore: one merged map per uid.
class FakeCloud implements CloudSync {
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
    await auth.register('a@b.co', 'secret1', 'A');
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
}
