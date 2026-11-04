import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Remote copy of an account's tracking state (watched episodes, statuses,
/// ratings, favourites, artwork choices, theme).
///
/// The payload is the same set of keys AppState persists locally, holding
/// the same values (string lists, JSON strings, ints), so local and remote
/// share one codec and a field is never interpreted in two ways.
abstract class CloudSync {
  /// The account's stored fields, or null when nothing has been uploaded
  /// yet (first sign-in) or the backend could not be reached.
  Future<Map<String, Object?>?> load(String uid);

  /// Merges [fields] into the account's document.
  Future<void> save(String uid, Map<String, Object?> fields);
}

/// Firestore-backed sync: one document per account at `users/{uid}`.
///
/// Firestore's offline cache keeps the app usable without a connection:
/// writes queue locally and replay when the device is back online. Rules
/// in `firestore.rules` restrict each document to its own signed-in user.
///
/// Size: a document holds up to 1 MiB. Watched ids are ~20 bytes plus a
/// ~30-byte timestamp entry, so one document covers ~15,000 watched
/// episodes. Past that, split `watched` / `watchedAt` into a subcollection.
class FirestoreCloudSync implements CloudSync {
  FirestoreCloudSync({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Bump when the payload layout changes in a way old clients can't read.
  static const int schemaVersion = 1;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  @override
  Future<Map<String, Object?>?> load(String uid) async {
    try {
      // Server first so a second device sees the latest state; fall back to
      // the offline cache when the network is slow or absent.
      final snap = await _doc(uid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
      final data = snap.data();
      if (data == null) return null;
      final state = data['state'];
      return state is Map ? Map<String, Object?>.from(state) : null;
    } catch (_) {
      try {
        final cached =
            await _doc(uid).get(const GetOptions(source: Source.cache));
        final state = cached.data()?['state'];
        return state is Map ? Map<String, Object?>.from(state) : null;
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Future<void> save(String uid, Map<String, Object?> fields) {
    return _doc(uid).set({
      'schema': schemaVersion,
      'updatedAt': FieldValue.serverTimestamp(),
      'state': fields,
    }, SetOptions(merge: true));
  }
}
