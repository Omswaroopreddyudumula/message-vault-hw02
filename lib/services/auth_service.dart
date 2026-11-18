import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'board_service.dart';

class Session {
  const Session(this.uid, this.email);
  final String uid;
  final String? email;
}

class AuthService {
  AuthService({required FirebaseApp app, required this.board})
    : _auth = FirebaseAuth.instanceFor(app: app) {
    authState = _auth.authStateChanges().map(
      (u) => u == null ? null : Session(u.uid, u.email),
    );
  }
  final FirebaseAuth _auth;
  final BoardService board;
  late final Stream<Session?> authState;
  Session? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : Session(u.uid, u.email);
  }

  Future<void> configure({String? emulatorHost}) async {
    if (emulatorHost != null) await _auth.useAuthEmulator(emulatorHost, 9199);
  }

  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = credential.user?.uid;
    if (uid == null) throw StateError('Account creation returned no user.');
    try {
      await board.saveUserRecord(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
      );
    } catch (_) {
      throw StateError(
        'Account created, profile not saved. Complete the profile for this signed-in account; do not register again.',
      );
    }
  }

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();
}

String helpfulError(Object e) {
  if (e is FirebaseAuthException) {
    return switch (e.code) {
      'invalid-email' => 'Enter a valid email address.',
      'weak-password' => 'Use at least six characters for the password.',
      'email-already-in-use' =>
        'This email already has an account. Sign in instead.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Email or password is incorrect.',
      'network-request-failed' =>
        'Unable to connect. Check the network and retry.',
      _ => 'Sign-in could not finish. Please retry.',
    };
  }
  if (e is FirebaseException) {
    return '${e.code}: ${switch (e.code) {
      'permission-denied' => 'Firestore denied this request.',
      'unavailable' => 'The cloud is unavailable. Reconnect and retry the same request.',
      'resource-exhausted' => 'The service quota was reached. Wait before retrying.',
      _ => 'The cloud request could not finish.',
    }}';
  }
  if (e is FormatException) return e.message.toString();
  if (e is StateError) return e.message.toString();
  return 'The request could not finish. Please retry.';
}
