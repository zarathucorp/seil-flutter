import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seil_mobile/core/settings/app_settings_repository.dart';
import 'package:seil_mobile/features/auth/auth_repository.dart';
import 'package:seil_mobile/features/connections/connection_repository.dart';
import 'package:seil_mobile/features/connections/host_key_repository.dart';
import 'package:seil_mobile/features/sessions/ssh_session_service.dart';
import 'package:seil_mobile/shared/app_state.dart';
import 'package:seil_mobile/shared/models.dart';

void main() {
  test('reconnects half-open shared client sessions after disconnect mark',
      () async {
    final connection = _connection();
    final oldClient = _FakeSshClient();
    final oldRoot = _FakeLiveSshSession(
      id: 'old-root',
      client: oldClient,
      connection: connection,
      currentPath: '/work/root',
    );
    final oldChild = _FakeLiveSshSession(
      id: 'old-child',
      client: oldClient,
      connection: connection,
      currentPath: '/work/child',
    );
    final replacementRoot = _FakeLiveSshSession(
      id: 'replacement-root',
      client: _FakeSshClient(),
      connection: connection,
      currentPath: '/work/root',
    );
    final sshSessionService = _FakeSshSessionService(replacementRoot);
    final state = _appState(
      connectionRepository: _FakeConnectionRepository(secret: 'secret'),
      sshSessionService: sshSessionService,
    )
      ..currentUser = _user()
      ..liveSessions = [oldRoot, oldChild]
      ..activeSession = oldChild;
    state.sessionDirectories[state.terminalFrameKey(oldRoot)] =
        _directory('/work/root');
    state.sessionDirectories[state.terminalFrameKey(oldChild)] =
        _directory('/work/child');
    state.activeDirectory = state.sessionDirectories[state.terminalFrameKey(
      oldChild,
    )];

    state.markSessionDisconnected(oldRoot);
    await pumpEventQueue(times: 4);

    expect(oldRoot.closed, isTrue);
    expect(oldClient.closed, isTrue);
    expect(sshSessionService.connectCount, 1);
    expect(state.liveSessions, hasLength(2));
    expect(state.liveSessions.map((session) => session.id), [
      'replacement-root',
      'replacement-root-child-1',
    ]);
    expect(state.liveSessions.every((session) => !session.isClosed), isTrue);
    expect(
        state.liveSessions.every(
          (session) => session.client == replacementRoot.client,
        ),
        isTrue);
    expect(state.activeSession?.id, 'replacement-root-child-1');
    expect(state.activeDirectory?.currentPath, '/work/child');
  });

  test('force reconnects active workspace even after manual retry lockout',
      () async {
    final connection = _connection();
    final oldClient = _FakeSshClient();
    final oldSession = _FakeLiveSshSession(
      id: 'old-active',
      client: oldClient,
      connection: connection,
      currentPath: '/work/current',
    );
    final replacement = _FakeLiveSshSession(
      id: 'replacement-active',
      client: _FakeSshClient(),
      connection: connection,
      currentPath: '/work/current',
    );
    final sshSessionService = _FakeSshSessionService(replacement);
    final state = _appState(
      connectionRepository: _FakeConnectionRepository(secret: 'secret'),
      sshSessionService: sshSessionService,
    )
      ..currentUser = _user()
      ..liveSessions = [oldSession]
      ..activeSession = oldSession;
    state.sessionDirectories[state.terminalFrameKey(oldSession)] =
        _directory('/work/current');
    state.activeDirectory = state.sessionDirectories[state.terminalFrameKey(
      oldSession,
    )];
    state.reconnectPolicy.recordFailure(
      connection.fingerprint,
      StateError('previous failure requires manual retry'),
      requiresManualRetry: true,
    );

    await state.reconnectActiveWorkspace();

    expect(oldSession.closed, isTrue);
    expect(oldClient.closed, isTrue);
    expect(sshSessionService.connectCount, 1);
    expect(state.liveSessions.single.id, 'replacement-active');
    expect(state.activeSession?.id, 'replacement-active');
    expect(state.activeDirectory?.currentPath, '/work/current');
    expect(state.reconnectPolicy.failureFor(connection.fingerprint), isNull);
  });
}

AppState _appState({
  required ConnectionRepository connectionRepository,
  required SshSessionService sshSessionService,
}) {
  return AppState(
    authRepository: _FakeAuthRepository(),
    connectionRepository: connectionRepository,
    hostKeyRepository: _FakeHostKeyRepository(),
    settingsRepository: _FakeSettingsRepository(),
    sshSessionService: sshSessionService,
  );
}

SavedConnection _connection() {
  final now = DateTime.utc(2026, 5, 26);
  return SavedConnection(
    id: 'connection-a',
    label: 'Server A',
    host: 'server.example',
    port: 22,
    username: 'seil',
    authMode: AuthMode.password,
    tmuxHistoryLimit: 2000,
    fingerprint: 'fingerprint-a',
    hasStoredSecret: true,
    createdAt: now,
    updatedAt: now,
  );
}

SeilUser _user() {
  final now = DateTime.utc(2026, 5, 26);
  return SeilUser(
    id: 'user-a',
    username: 'admin',
    name: 'Admin',
    createdAt: now,
    updatedAt: now,
    passwordChangedAt: now,
  );
}

RemoteDirectory _directory(String path) {
  return RemoteDirectory(
    currentPath: path,
    parentPath: '/',
    entries: const [],
  );
}

class _FakeSshSessionService implements SshSessionService {
  _FakeSshSessionService(this.replacement);

  final LiveSshSession replacement;
  int connectCount = 0;

  @override
  Future<LiveSshSession> connect({
    required SavedConnection connection,
    required String secret,
  }) async {
    connectCount += 1;
    return replacement;
  }
}

class _FakeLiveSshSession extends LiveSshSession {
  _FakeLiveSshSession({
    required String id,
    required super.client,
    required super.connection,
    required String currentPath,
  }) : super.testing(
          id: id,
        ) {
    hostName = connection.host;
    homePath = '/home/seil';
    tmuxAvailable = true;
    shellFallbackPath = '/bin/sh';
    this.currentPath = currentPath;
    tmuxSelectionReady = true;
  }

  bool closed = false;
  int childSerial = 0;

  @override
  bool get isClosed => closed;

  @override
  Future<RemoteDirectory> listDirectory(String remotePath) async {
    currentPath = remotePath;
    return _directory(remotePath);
  }

  @override
  LiveSshSession createTerminalSession({String? initialPath}) {
    childSerial += 1;
    return _FakeLiveSshSession(
      id: '$id-child-$childSerial',
      client: client,
      connection: connection,
      currentPath: initialPath ?? currentPath,
    );
  }

  @override
  void close({bool closeClient = true}) {
    closed = true;
    if (closeClient && client is _FakeSshClient) {
      (client as _FakeSshClient).close();
    }
  }
}

class _FakeSshClient extends Fake implements SSHClient {
  bool closed = false;

  @override
  bool get isClosed => closed;

  @override
  void close() {
    closed = true;
  }
}

class _FakeConnectionRepository extends Fake implements ConnectionRepository {
  _FakeConnectionRepository({required this.secret});

  final String secret;

  @override
  Future<String?> resolveSecret(SavedConnection connection,
      [String? transientSecret]) async {
    return transientSecret?.isNotEmpty == true ? transientSecret : secret;
  }
}

class _FakeAuthRepository extends Fake implements AuthRepository {}

class _FakeHostKeyRepository extends Fake implements HostKeyRepository {}

class _FakeSettingsRepository extends Fake implements AppSettingsRepository {}
