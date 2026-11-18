# Message Vault

Om Swaroop Reddy Udumula · CSC 4360 · Homework 02

A fresh Android Flutter project for an authenticated public message board. Firebase project: `message-vault-om-261118`; Android package: `com.campusdesk.message_vault`. No previous assignment source or database is reused.

## Setup

Use Flutter 3.47.2 / Dart 3.13.2, Android SDK and Java 21. Run `flutter pub get`. Create your own Firebase project, enable Email/Password Authentication, create Firestore, and run `flutterfire configure --platforms=android`. The committed options originated from FlutterFire CLI; the client API key is read from `FIREBASE_API_KEY` at build time to avoid repository scanner alerts. Firebase client configuration is public app identity, not database authorization. Rules are mandatory.

Keep `android/app/google-services.json` and a local `firebase-defines.json` outside Git. The latter is a JSON object with `FIREBASE_API_KEY` set to your Firebase Android client key. Build with `flutter build apk --release --dart-define-from-file=/absolute/path/firebase-defines.json`. Deploy `firebase deploy --only firestore:rules --project YOUR_PROJECT_ID` after reviewing the target project. The Android main manifest includes INTERNET permission.

The classroom APK uses a local development signing certificate. It is a Flutter release/AOT build; Android shrinking is disabled so external release instrumentation retains all runtime dependencies. It is not configured for Play Store distribution. Signing material is not committed.

## Flow and architecture

The styled splash holds the initialization future and offers retry on failure. Its minimum display time begins after the first rasterized frame, so a cold start cannot consume the timer before the artwork appears. AuthService owns registration, sign-in, sign-out, current user and one stable auth-state stream. AuthGate routes from the stream. ProfileGate waits for a complete private record before entering the board. If Auth succeeds but profile creation fails, repair the record for the existing uid; do not create another account. Registration retries never reset the original server timestamp.

BoardService owns every Firestore call. Widgets render typed UserRecord, BoardMessage and BoardFeed values. The board listens to one `snapshots()` stream, ordered oldest first by `createdAt`. Loading, empty, error and cache/source states have explicit UI. Controllers and route streams are disposed with their widgets.

## Storage key map and field writers

| Location | Fields | Writer and purpose |
|---|---|---|
| Firebase Auth | uid, email, provider credentials | Firebase Authentication; app sends credentials only to Auth. Passwords are never copied to Firestore or logs. |
| `users/{uid}` private | uid | AuthService supplies the authenticated uid; rules require the same uid. |
| `users/{uid}` private | firstName, lastName | Registration/profile repair supplies trimmed values of 1–40 characters. |
| `users/{uid}` private | role | Client writes fixed `student`; descriptive label only, never a privilege. |
| `users/{uid}` private | registrationDateTime | Firestore resolves the create-time server timestamp. Exactly five fields are permitted. |
| `messages/{id}` signed-in board | text | Author creates/edits trimmed 1–500-character content. |
| `messages/{id}` signed-in board | authorUid, authorName | Client captures current uid and profile first name at create; rules verify them and prevent later changes. |
| `messages/{id}` signed-in board | createdAt, editedAt | Server timestamps; editedAt begins null and changes on author edit. |
| Device Auth storage | persisted session tokens | Firebase SDK; survives process death/reboot, removed with app data. No manually stored password. |
| Widget memory | unsent text, pending post id, busy state | Temporary process-local state; lost on process termination. |
| Firestore local view | currently received records | Persistence disabled; runtime cache only, no durable board database on device. |

Public board content excludes last name, email, role, registration time, passwords and tokens. Authenticated members can see first names and message text. Each private profile is readable only by its uid. Do not post personal information on the board.

## Ownership and duplicate protection

Rules deny signed-out board reads. Only a valid current-user profile can create a message. The existing author uid controls edit/delete, and edits can change only text and editedAt. Catch-all deny covers other paths. Client controls are convenience, not authorization.

Each submit intent allocates one document id before the transaction. The button locks immediately; network retry reuses the same immutable id and content. The transaction reads that id and returns already-saved for an identical record. A diagnostic repeat issues the same request again. Unknown failures preserve the id; “Check original ID” reconciles with the server before permitting another intent. Transactions fail offline; they are not a durable offline queue. Pending ids are memory-only, so force-killing during an unknown commit loses that identity. A durable, privacy-aware outbox would be the next improvement. Do not claim cross-process exactly-once delivery.

## Run and test

`flutter analyze` checks the Flutter project. Install the release APK, then test validation, register two fictional accounts, inspect the five-field private record, create/edit/delete only the first author's post, retain the other author's post, and check a second-window live update. Development rules checks deliberately send forbidden edit/delete/forged-author requests; permission-denied must come from Firestore. A signed-out probe verifies server denial. These diagnostics use the same rules as normal requests and confer no additional access.

`android/app/src/androidTest/.../ReleaseGateTest.java` drives the installed release through UI Automator. It is a separate test APK, not a replacement Flutter entry point. Runtime instrumentation arguments supply fictional test emails/passwords; none are compiled into source. Build the test runner with `cd android && ./gradlew app:assembleReleaseAndroidTest`. Install the exact release and runner APKs, then invoke AndroidJUnitRunner with runtime test arguments. Evidence records identify the delivered APK hash.

## Selected spices

1. Emulator Explorer: `firebase emulators:start --only auth,firestore --project demo-message-vault`. Ports are Auth 9199, Firestore 8180, UI 4100, hub 4500. Build a separate emulator app with `--dart-define=USE_EMULATORS=true`. Android Emulator uses host 10.0.2.2. Emulator FirebaseApp is named and uses only demo project identity. Use before/after cloud snapshots to prove isolation. Never point emulator seed commands at the live project.
2. Rules Unit Tester: `cd tests && npm ci && npm test` while the demo Firestore emulator is running. Ten cases include signed-out read, cross-uid edit/delete, forged author, valid CRUD, private profiles, immutable identity/time, invalid content and descriptive role validation.
4. Idempotent Alchemist: stable intent id plus transaction read-before-write, immediate submit lock and identical-request retry. Validate one board document remains after a duplicate attempt; preserve another author's document during single delete.

The Main Spice is the end-to-end test on the exact submitted release APK. See the accompanying evidence document and test logs for observed results, limits and screenshots.

## Second window

`tools/window-client` is a minimal independent browser client using the same public/private model and ownership rules. Bundle client.js using esbuild with the Firebase JS dependency from tests, serve its index/client/config files on localhost, and sign in as a fictional second account. config.json is local Firebase Web SDK configuration, excluded from Git. A browser post must appear in the Android release without refreshing.

## Official references

- https://firebase.google.com/docs/flutter/setup
- https://firebase.google.com/docs/auth/flutter/manage-users
- https://firebase.google.com/docs/firestore/query-data/listen
- https://firebase.google.com/docs/firestore/manage-data/transactions
- https://firebase.google.com/docs/firestore/security/rules-conditions
- https://firebase.google.com/docs/firestore/security/test-rules-emulator
- https://docs.flutter.dev/deployment/android
- https://developer.android.com/training/testing/other-components/ui-automator-legacy

## Observed results November 18 2026

The release gate, independent browser live update, process restart, device reboot, clear-data recovery, physical-offline retry, intentional empty board and separate emulator demonstration passed. All 10 automated rules cases passed with 0 failures/skips; Flutter analyze reported no issues. `evidence/test-summary.json` identifies the exact delivery APK hash, observed emulator isolation hash and test outcomes. `evidence/rules-tests.txt` is the actual rules process output. The evidence document contains 27 captioned screenshots, reflections, lifetime analysis and two case-file arguments.

[Download the reflection and evidence document](docs/HW02_OmSwaroopReddyUdumula.docx). It contains 27 real captioned screenshots across 26 visually checked pages.
