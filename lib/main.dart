import 'dart:async';

import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'services/auth_service.dart';
import 'services/board_service.dart';

Widget tagged(String id, Widget child) =>
    Semantics(identifier: id, child: child);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Services? services;
  Object? startupError;
  try {
    // Android's styled launch theme remains visible during this awaited setup.
    services = await initializeServices();
  } catch (error) {
    startupError = error;
  }
  runApp(VaultApp(initialServices: services, startupError: startupError));
}

class VaultApp extends StatelessWidget {
  const VaultApp({super.key, this.initialServices, this.startupError});
  final Services? initialServices;
  final Object? startupError;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Message Vault',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b62)),
      scaffoldBackgroundColor: const Color(0xfffffcf4),
      useMaterial3: true,
    ),
    home: LaunchScreen(
      initialServices: initialServices,
      startupError: startupError,
    ),
  );
}

class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key, this.initialServices, this.startupError});
  final Services? initialServices;
  final Object? startupError;
  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen> {
  late Future<Services> future;
  @override
  void initState() {
    super.initState();
    future = load(ready: widget.initialServices, error: widget.startupError);
  }

  Future<Services> load({Services? ready, Object? error}) async {
    final services = error != null
        ? Future<Services>.error(error)
        : ready != null
        ? Future<Services>.value(ready)
        : initializeServices();
    final minimumVisible = WidgetsBinding.instance.waitUntilFirstFrameRasterized
        .then((_) => Future<void>.delayed(const Duration(milliseconds: 1800)));
    final values = await Future.wait<Object?>([services, minimumVisible]);
    return values.first as Services;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Services>(
    future: future,
    builder: (context, s) {
      if (s.hasData) return AuthGate(services: s.data!);
      if (s.hasError) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 56),
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Unable to initialize Firebase. Check the configuration and connection.',
                    ),
                  ),
                  FilledButton(
                    onPressed: () => setState(() => future = load()),
                    child: const Text('Retry initialization'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return Scaffold(
        body: tagged(
          'splash',
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff0b514b), Color(0xff287f6d)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_open_rounded,
                    size: 88,
                    color: Color(0xffffdc88),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Message Vault',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'One board. Your voice. Your posts.',
                    style: TextStyle(color: Colors.white, fontSize: 17),
                  ),
                  SizedBox(height: 32),
                  CircularProgressIndicator(color: Color(0xffffdc88)),
                  SizedBox(height: 16),
                  Text(
                    'Opening the vault…',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.services});
  final Services services;
  @override
  Widget build(BuildContext context) => StreamBuilder<Session?>(
    stream: services.auth.authState,
    builder: (context, s) {
      if (s.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (s.hasError) {
        return const Scaffold(
          body: Center(
            child: Text(
              'Unable to read account state. Restart and sign in again.',
            ),
          ),
        );
      }
      return s.data == null
          ? AuthScreen(services: services)
          : ProfileGate(
              key: ValueKey(s.data!.uid),
              services: services,
              session: s.data!,
            );
    },
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.services});
  final Services services;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      first = TextEditingController(),
      last = TextEditingController();
  bool registering = false, busy = false;
  String? feedback;
  @override
  void dispose() {
    for (final c in [email, password, first, last]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      if (registering) {
        await widget.services.auth.register(
          email: email.text,
          password: password.text,
          firstName: first.text,
          lastName: last.text,
        );
      } else {
        await widget.services.auth.signIn(email.text, password.text);
      }
    } catch (e) {
      if (mounted) setState(() => feedback = helpfulError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> probe() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.services.board.probeSignedOutRead();
      if (mounted) {
        setState(
          () => feedback = 'Unexpected access. Inspect the deployed rules.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => feedback = helpfulError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Message Vault')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                registering ? 'Join the board' : 'Welcome back',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                useEmulators
                    ? 'LOCAL EMULATORS • isolated test data'
                    : 'A shared board with private account records.',
              ),
              const SizedBox(height: 20),
              Form(
                key: form,
                child: Column(
                  children: [
                    if (registering) ...[
                      tagged(
                        'first_name',
                        TextFormField(
                          controller: first,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            labelText: 'First name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter your first name.'
                              : null,
                        ),
                      ),
                      tagged(
                        'last_name',
                        TextFormField(
                          controller: last,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            labelText: 'Last name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter your last name.'
                              : null,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text('Role: student • profile label only'),
                      ),
                    ],
                    tagged(
                      'email',
                      TextFormField(
                        controller: email,
                        autocorrect: false,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            v != null &&
                                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(v.trim())
                            ? null
                            : 'Enter a valid email.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    tagged(
                      'password',
                      TextFormField(
                        controller: password,
                        obscureText: true,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v != null && v.length >= 6
                            ? null
                            : 'Use at least six characters.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (feedback != null)
                      tagged(
                        'auth_feedback',
                        Text(
                          feedback!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    tagged(
                      'auth_submit',
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: Text(
                          busy
                              ? 'Connecting…'
                              : registering
                              ? 'Create account'
                              : 'Sign in',
                        ),
                      ),
                    ),
                    tagged(
                      'auth_toggle',
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                registering = !registering;
                                feedback = null;
                              }),
                        child: Text(
                          registering
                              ? 'Already registered? Sign in'
                              : 'New here? Create account',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (labTests)
                tagged(
                  'signed_out_probe',
                  OutlinedButton(
                    onPressed: busy ? null : probe,
                    child: const Text('Test signed-out board access'),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Passwords stay with Firebase Authentication. The board stores messages, not credentials.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.services, required this.session});
  final Services services;
  final Session session;
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Stream<UserRecord?> stream;
  @override
  void initState() {
    super.initState();
    stream = widget.services.board.userRecord(widget.session.uid);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<UserRecord?>(
    stream: stream,
    builder: (context, s) {
      if (s.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (s.hasError) {
        return Scaffold(
          appBar: AppBar(title: const Text('Account record')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load your private account record.'),
                FilledButton(
                  onPressed: () => setState(
                    () => stream = widget.services.board.userRecord(
                      widget.session.uid,
                    ),
                  ),
                  child: const Text('Retry account record'),
                ),
                TextButton(
                  onPressed: widget.services.auth.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        );
      }
      if (s.data == null) {
        return RepairProfile(
          services: widget.services,
          session: widget.session,
        );
      }
      return BoardScreen(services: widget.services, profile: s.data!);
    },
  );
}

class RepairProfile extends StatefulWidget {
  const RepairProfile({
    super.key,
    required this.services,
    required this.session,
  });
  final Services services;
  final Session session;
  @override
  State<RepairProfile> createState() => _RepairProfileState();
}

class _RepairProfileState extends State<RepairProfile> {
  final first = TextEditingController(), last = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    first.dispose();
    last.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    if (first.text.trim().isEmpty || last.text.trim().isEmpty) {
      setState(() => error = 'Enter both names.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.services.board.saveUserRecord(
        uid: widget.session.uid,
        firstName: first.text,
        lastName: last.text,
      );
    } catch (e) {
      if (mounted) setState(() => error = helpfulError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Complete your account')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Your account exists. Finish saving its private profile for the same signed-in user; do not register again.',
          ),
          TextField(
            controller: first,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'First name'),
          ),
          TextField(
            controller: last,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Last name'),
          ),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : 'Save account record'),
          ),
          TextButton(
            onPressed: busy ? null : widget.services.auth.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    ),
  );
}

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.services, required this.profile});
  final Services services;
  final UserRecord profile;
  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late final Stream<BoardFeed> feed;
  final draft = TextEditingController();
  PostIntent? pending, lastPost;
  bool busy = false;
  String feedback = '';
  @override
  void initState() {
    super.initState();
    feed = widget.services.board.messages();
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  Future<void> post({bool repeat = false}) async {
    if (busy) return;
    try {
      pending ??= repeat
          ? lastPost
          : widget.services.board.newIntent(widget.profile, draft.text);
      if (pending == null) return;
    } catch (e) {
      setState(() => feedback = helpfulError(e));
      return;
    }
    setState(() => busy = true);
    try {
      final created = await widget.services.board.post(pending!);
      if (mounted) {
        setState(() {
          lastPost = pending;
          pending = null;
          draft.clear();
          feedback = created
              ? 'Message posted.'
              : 'Already saved; no duplicate created.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => feedback =
              '${helpfulError(e)} The same post ID is retained for retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reconcile() async {
    if (busy || pending == null) return;
    setState(() => busy = true);
    try {
      final exists = await widget.services.board.existsOnServer(pending!);
      if (mounted) {
        setState(() {
          if (exists) {
            lastPost = pending;
            pending = null;
            draft.clear();
            feedback = 'The server confirms this post already exists.';
          } else {
            pending = null;
            feedback = 'Server confirms no post at this ID. You can edit or discard this unsent draft.';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => feedback = helpfulError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(BoardMessage m) async {
    final input = TextEditingController(text: m.text);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit your message'),
        content: tagged(
          'edit_input',
          TextField(
            controller: input,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Message text'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          tagged(
            'save_edit',
            FilledButton(
              onPressed: () => Navigator.pop(context, input.text),
              child: const Text('Save edit'),
            ),
          ),
        ],
      ),
    );
    // Keep the controller alive until the closing animation has released the field.
    Future<void>.delayed(const Duration(milliseconds: 350), input.dispose);
    if (value == null || !mounted) return;
    await operation(
      () => widget.services.board.edit(m, value),
      'Message edited.',
    );
    if (lastPost?.id == m.id) lastPost = null;
  }

  Future<void> delete(BoardMessage m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this message?'),
        content: const Text('Only this message will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          tagged(
            'confirm_delete',
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete message'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await operation(() => widget.services.board.delete(m), 'Message deleted.');
    if (lastPost?.id == m.id) lastPost = null;
  }

  Future<void> operation(Future<void> Function() work, String success) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
      if (mounted) setState(() => feedback = success);
    } catch (e) {
      if (mounted) setState(() => feedback = helpfulError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void profile() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Private account record'),
      content: Text(
        'First name: ${widget.profile.firstName}\nLast name: ${widget.profile.lastName}\nRole: ${widget.profile.role}\nUID suffix: …${widget.profile.uid.substring(widget.profile.uid.length - 6)}\nRegistered: ${widget.profile.registeredAt.toUtc().toIso8601String()}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  void checks(List<BoardMessage> messages) {
    final foreign = messages
        .where((m) => m.authorUid != widget.profile.uid)
        .toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'DEVELOPMENT RULES CHECKS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'These requests deliberately bypass UI ownership checks. Firestore must reject them.',
              ),
              if (foreign.isNotEmpty) ...[
                tagged(
                  'probe_foreign_edit',
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      operation(
                        () => widget.services.board.probeForeignEdit(
                          foreign.first,
                        ),
                        'Unexpected edit access. Inspect rules.',
                      );
                    },
                    child: const Text('Try another author’s edit'),
                  ),
                ),
                tagged(
                  'probe_foreign_delete',
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      operation(
                        () => widget.services.board.probeForeignDelete(
                          foreign.first,
                        ),
                        'Unexpected delete access. Inspect rules.',
                      );
                    },
                    child: const Text('Try another author’s delete'),
                  ),
                ),
              ] else
                const Text(
                  'A second author’s post is needed for the cross-user checks.',
                ),
              tagged(
                'probe_forged',
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    operation(
                      () => widget.services.board.probeForgedCreate(
                        widget.profile,
                      ),
                      'Unexpected forged-author access. Inspect rules.',
                    );
                  },
                  child: const Text('Try forged author create'),
                ),
              ),
              if (lastPost != null)
                tagged(
                  'repeat_post',
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      post(repeat: true);
                    },
                    child: const Text('Repeat last post request'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Message Vault'),
      actions: [
        tagged(
          'profile',
          IconButton(
            onPressed: profile,
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Private account record',
          ),
        ),
        tagged(
          'sign_out',
          TextButton(
            onPressed: busy || pending != null
                ? null
                : widget.services.auth.signOut,
            child: const Text('Sign out'),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Hello, ${widget.profile.firstName} • ${useEmulators ? 'Local emulator' : 'Shared cloud board'}',
                  ),
                ),
                const Icon(Icons.forum_outlined),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<BoardFeed>(
              stream: feed,
              builder: (context, s) {
                if (s.hasError) {
                  return Center(
                    child: Text('Board unavailable. ${helpfulError(s.error!)}'),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = s.data!.messages;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: tagged(
                              'stream_status',
                              Text(
                                '${s.data!.fromCache ? 'Cached view' : 'Live cloud stream'} • ${messages.length} messages',
                              ),
                            ),
                          ),
                          if (labTests)
                            tagged(
                              'rules_checks',
                              TextButton(
                                onPressed: busy || pending != null
                                    ? null
                                    : () => checks(messages),
                                child: const Text('Rules checks'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: messages.isEmpty
                          ? tagged(
                              'empty_board',
                              const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.markunread_mailbox_outlined,
                                      size: 48,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'No messages yet. Start the conversation.',
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: messages.length,
                              itemBuilder: (context, i) {
                                final m = messages[i];
                                final own = m.authorUid == widget.profile.uid;
                                return tagged(
                                  'message_${m.id}',
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.text,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '${m.authorName} • ${m.createdAt?.toLocal().toString().substring(0, 16) ?? 'awaiting server time'}${m.editedAt == null ? '' : ' • edited'}${m.pending ? ' • pending' : ''}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          if (own)
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                tagged(
                                                  'edit_${m.id}',
                                                  TextButton(
                                                    onPressed:
                                                        busy || pending != null
                                                        ? null
                                                        : () => edit(m),
                                                    child: const Text('Edit'),
                                                  ),
                                                ),
                                                tagged(
                                                  'delete_${m.id}',
                                                  TextButton(
                                                    onPressed:
                                                        busy || pending != null
                                                        ? null
                                                        : () => delete(m),
                                                    child: const Text('Delete'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (feedback.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: tagged(
                'board_feedback',
                Text(
                  feedback,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tagged(
                    'post_input',
                    TextField(
                      controller: draft,
                      enabled: !busy && pending == null,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Write a message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: tagged(
                          'post_submit',
                          FilledButton.icon(
                            onPressed: busy ? null : post,
                            icon: const Icon(Icons.send_outlined),
                            label: Text(
                              busy
                                  ? 'Working…'
                                  : pending == null
                                  ? 'Post message'
                                  : 'Retry same post',
                            ),
                          ),
                        ),
                      ),
                      if (pending != null)
                        tagged(
                          'reconcile_post',
                          TextButton(
                            onPressed: busy ? null : reconcile,
                            child: const Text('Check original ID'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
