import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class UserRecord {
  const UserRecord(
    this.uid,
    this.firstName,
    this.lastName,
    this.role,
    this.registeredAt,
  );
  final String uid, firstName, lastName, role;
  final DateTime registeredAt;
}

class BoardMessage {
  const BoardMessage(
    this.id,
    this.text,
    this.authorUid,
    this.authorName,
    this.createdAt,
    this.editedAt,
    this.pending,
  );
  final String id, text, authorUid, authorName;
  final DateTime? createdAt, editedAt;
  final bool pending;
}

class BoardFeed {
  const BoardFeed(this.messages, this.fromCache);
  final List<BoardMessage> messages;
  final bool fromCache;
}

class PostIntent {
  const PostIntent(this.id, this.uid, this.authorName, this.text);
  final String id, uid, authorName, text;
}

class BoardService {
  BoardService({required FirebaseApp app, required this.currentUid})
    : _db = FirebaseFirestore.instanceFor(app: app);
  final FirebaseFirestore _db;
  final String? Function() currentUid;
  Future<void> configure({String? emulatorHost}) async {
    if (emulatorHost != null) _db.useFirestoreEmulator(emulatorHost, 8180);
    _db.settings = const Settings(persistenceEnabled: false);
  }

  String _uid() {
    final uid = currentUid();
    if (uid == null) throw StateError('Sign in to continue.');
    return uid;
  }

  String validateText(String input) {
    final text = input.trim();
    if (text.isEmpty || text.length > 500) {
      throw const FormatException('Enter a message of 1–500 characters.');
    }
    return text;
  }

  Future<void> saveUserRecord({
    required String uid,
    required String firstName,
    required String lastName,
  }) async {
    if (uid != _uid()) throw StateError('The account changed. Sign in again.');
    final ref = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return; // Never reset registration time on retry.
      tx.set(ref, {
        'uid': uid,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'role': 'student',
        'registrationDateTime': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<UserRecord?> userRecord(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((snap) {
        final d = snap.data();
        if (d == null) return null;
        if (d.length != 5 ||
            d['uid'] != uid ||
            d['firstName'] is! String ||
            d['lastName'] is! String ||
            d['role'] is! String ||
            d['registrationDateTime'] is! Timestamp) {
          throw const FormatException('The user record is incomplete.');
        }
        return UserRecord(
          uid,
          d['firstName'] as String,
          d['lastName'] as String,
          d['role'] as String,
          (d['registrationDateTime'] as Timestamp).toDate(),
        );
      });
  Stream<BoardFeed> messages() => _db
      .collection('messages')
      .orderBy('createdAt')
      .snapshots(includeMetadataChanges: true)
      .map(
        (snap) => BoardFeed(
          snap.docs
              .map((doc) {
                final d = doc.data();
                return BoardMessage(
                  doc.id,
                  d['text'] as String,
                  d['authorUid'] as String,
                  d['authorName'] as String,
                  (d['createdAt'] as Timestamp?)?.toDate(),
                  (d['editedAt'] as Timestamp?)?.toDate(),
                  doc.metadata.hasPendingWrites,
                );
              })
              .toList(growable: false),
          snap.metadata.isFromCache,
        ),
      );
  PostIntent newIntent(UserRecord profile, String text) {
    if (profile.uid != _uid()) throw StateError('The account changed.');
    return PostIntent(
      _db.collection('messages').doc().id,
      profile.uid,
      profile.firstName,
      validateText(text),
    );
  }

  Future<bool> post(PostIntent intent) async {
    if (_uid() != intent.uid) {
      throw StateError('This pending post belongs to another session.');
    }
    final ref = _db.collection('messages').doc(intent.id);
    return _db.runTransaction((tx) async {
      final old = await tx.get(ref);
      if (old.exists) {
        final d = old.data()!;
        if (d['authorUid'] != intent.uid ||
            d['authorName'] != intent.authorName ||
            d['text'] != intent.text) {
          throw StateError('This post ID already contains different content.');
        }
        return false;
      }
      tx.set(ref, {
        'text': intent.text,
        'authorUid': intent.uid,
        'authorName': intent.authorName,
        'createdAt': FieldValue.serverTimestamp(),
        'editedAt': null,
      });
      return true;
    });
  }

  Future<void> edit(BoardMessage message, String text) async {
    if (message.authorUid != _uid()) {
      throw StateError('Only the author can edit this message.');
    }
    await _db.collection('messages').doc(message.id).update({
      'text': validateText(text),
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(BoardMessage message) async {
    if (message.authorUid != _uid()) {
      throw StateError('Only the author can delete this message.');
    }
    await _db.collection('messages').doc(message.id).delete();
  }

  Future<bool> existsOnServer(PostIntent intent) async {
    if (_uid() != intent.uid) throw StateError('Account changed.');
    return (await _db
            .collection('messages')
            .doc(intent.id)
            .get(const GetOptions(source: Source.server)))
        .exists;
  }

  // Explicit diagnostic requests deliberately bypass UI ownership checks; rules still enforce them.
  Future<void> probeSignedOutRead() async {
    await _db
        .collection('messages')
        .limit(1)
        .get(const GetOptions(source: Source.server));
  }

  Future<void> probeForeignEdit(BoardMessage message) async {
    await _db.collection('messages').doc(message.id).update({
      'text': 'Denied test edit',
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> probeForeignDelete(BoardMessage message) async {
    await _db.collection('messages').doc(message.id).delete();
  }

  Future<void> probeForgedCreate(UserRecord profile) async {
    await _db.collection('messages').doc().set({
      'text': 'Denied forged author',
      'authorUid': 'not-the-caller',
      'authorName': profile.firstName,
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
    });
  }
}
