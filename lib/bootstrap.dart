import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/board_service.dart';

const useEmulators = bool.fromEnvironment('USE_EMULATORS');
const labTests = bool.fromEnvironment('LAB_TESTS', defaultValue: true);

class Services {
  const Services(this.auth, this.board);
  final AuthService auth;
  final BoardService board;
}

Future<Services> initializeServices() async {
  final FirebaseApp app;
  if (useEmulators) {
    app = Firebase.apps.any((a) => a.name == 'vault-emulator')
        ? Firebase.app('vault-emulator')
        : await Firebase.initializeApp(
            name: 'vault-emulator',
            demoProjectId: 'demo-message-vault',
          );
  } else {
    app = Firebase.apps.isEmpty
        ? await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          )
        : Firebase.app();
  }
  late AuthService auth;
  final board = BoardService(app: app, currentUid: () => auth.currentUser?.uid);
  auth = AuthService(app: app, board: board);
  const host = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );
  await auth.configure(emulatorHost: useEmulators ? host : null);
  await board.configure(emulatorHost: useEmulators ? host : null);
  return Services(auth, board);
}
