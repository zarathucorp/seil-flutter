import 'dart:typed_data';

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
  test('formats dartssh2 MD5 host key fingerprint', () {
    expect(
      formatSshMd5Fingerprint(Uint8List.fromList(List<int>.generate(
        16,
        (index) => index,
      ))),
      'MD5:00:01:02:03:04:05:06:07:08:09:0a:0b:0c:0d:0e:0f',
    );
  });

  test('prompts and stores first host key before connecting', () async {
    final connection = _connection();
    final hostKeyRepository = _FakeHostKeyRepository();
    final request = _hostKeyRequest(connection);
    final replacement = _FakeLiveSshSession(
      id: 'session-a',
      client: _FakeSshClient(),
      connection: connection,
    );
    final state = _appState(
      connectionRepository: _FakeConnectionRepository(secret: 'secret'),
      hostKeyRepository: hostKeyRepository,
      sshSessionService: _HostKeyCheckingSshSessionService(
        request: request,
        replacement: replacement,
      ),
    )..currentUser = _user();
    HostKeyVerificationRequest? prompted;

    await state.connectSaved(
      connection,
      confirmHostKey: (request) async {
        prompted = request;
        return true;
      },
    );

    expect(prompted?.fingerprint, request.fingerprint);
    expect(
        hostKeyRepository.keys.single.fingerprintSha256, request.fingerprint);
    expect(state.liveSessions.single.id, 'session-a');
    expect(state.errorMessage, isNull);
  });

  test('blocks changed host key without asking to trust again', () async {
    final connection = _connection();
    final hostKeyRepository = _FakeHostKeyRepository()
      ..keys.add(_trustedHostKey(
        connection: connection,
        fingerprint: 'MD5:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00',
      ));
    final replacement = _FakeLiveSshSession(
      id: 'session-a',
      client: _FakeSshClient(),
      connection: connection,
    );
    final state = _appState(
      connectionRepository: _FakeConnectionRepository(secret: 'secret'),
      hostKeyRepository: hostKeyRepository,
      sshSessionService: _HostKeyCheckingSshSessionService(
        request: _hostKeyRequest(connection),
        replacement: replacement,
      ),
    )..currentUser = _user();
    var promptCount = 0;

    await state.connectSaved(
      connection,
      confirmHostKey: (_) async {
        promptCount += 1;
        return true;
      },
    );

    expect(promptCount, 0);
    expect(state.liveSessions, isEmpty);
    expect(state.errorMessage, contains('host key'));
  });
}

AppState _appState({
  required ConnectionRepository connectionRepository,
  required HostKeyRepository hostKeyRepository,
  required SshSessionService sshSessionService,
}) {
  return AppState(
    authRepository: _FakeAuthRepository(),
    connectionRepository: connectionRepository,
    hostKeyRepository: hostKeyRepository,
    settingsRepository: _FakeSettingsRepository(),
    sshSessionService: sshSessionService,
  );
}

SavedConnection _connection() {
  final now = DateTime.utc(2026, 5, 27);
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
  final now = DateTime.utc(2026, 5, 27);
  return SeilUser(
    id: 'user-a',
    username: 'admin',
    name: 'Admin',
    createdAt: now,
    updatedAt: now,
    passwordChangedAt: now,
  );
}

HostKeyVerificationRequest _hostKeyRequest(SavedConnection connection) {
  return HostKeyVerificationRequest(
    host: connection.host,
    port: connection.port,
    keyType: 'ssh-ed25519',
    fingerprint: 'MD5:11:11:11:11:11:11:11:11:11:11:11:11:11:11:11:11',
  );
}

TrustedHostKey _trustedHostKey({
  required SavedConnection connection,
  required String fingerprint,
}) {
  final now = DateTime.utc(2026, 5, 27);
  return TrustedHostKey(
    id: 'host-key-${fingerprint.hashCode}',
    host: connection.host,
    port: connection.port,
    keyType: 'ssh-ed25519',
    fingerprintSha256: fingerprint,
    createdAt: now,
    updatedAt: now,
    lastVerifiedAt: null,
  );
}

RemoteDirectory _directory(String path) {
  return RemoteDirectory(
    currentPath: path,
    parentPath: '/',
    entries: const [],
  );
}

class _HostKeyCheckingSshSessionService implements SshSessionService {
  const _HostKeyCheckingSshSessionService({
    required this.request,
    required this.replacement,
  });

  final HostKeyVerificationRequest request;
  final LiveSshSession replacement;

  @override
  Future<LiveSshSession> connect({
    required SavedConnection connection,
    required String secret,
    HostKeyVerifier? verifyHostKey,
  }) async {
    final trusted = await verifyHostKey?.call(request) ?? false;
    if (!trusted) {
      throw StateError('Hostkey verification failed');
    }
    return replacement;
  }
}

class _FakeLiveSshSession extends LiveSshSession {
  _FakeLiveSshSession({
    required String id,
    required super.client,
    required super.connection,
  }) : super.testing(id: id) {
    hostName = connection.host;
    homePath = '/home/seil';
    tmuxAvailable = true;
    shellFallbackPath = '/bin/sh';
    currentPath = homePath;
    tmuxSelectionReady = true;
  }

  @override
  Future<RemoteDirectory> listDirectory(String remotePath) async {
    currentPath = remotePath;
    return _directory(remotePath);
  }
}

class _FakeSshClient extends Fake implements SSHClient {
  @override
  bool get isClosed => false;
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

class _FakeHostKeyRepository extends Fake implements HostKeyRepository {
  final keys = <TrustedHostKey>[];

  @override
  Future<List<TrustedHostKey>> listTrustedHostKeys() async {
    return List<TrustedHostKey>.from(keys);
  }

  @override
  Future<List<TrustedHostKey>> listTrustedHostKeysForHost({
    required String host,
    required int port,
  }) async {
    return keys
        .where(
            (key) => key.host == host.trim().toLowerCase() && key.port == port)
        .toList();
  }

  @override
  Future<bool> isTrusted({
    required String host,
    required int port,
    required String fingerprintSha256,
  }) async {
    return keys.any((key) =>
        key.host == host.trim().toLowerCase() &&
        key.port == port &&
        key.fingerprintSha256 == fingerprintSha256.trim());
  }

  @override
  Future<TrustedHostKey> trustHostKey({
    required String host,
    required int port,
    required String keyType,
    required String fingerprintSha256,
  }) async {
    final key = _trustedHostKey(
      connection: _connection(),
      fingerprint: fingerprintSha256.trim(),
    );
    keys.add(key);
    return key;
  }
}

class _FakeAuthRepository extends Fake implements AuthRepository {}

class _FakeSettingsRepository extends Fake implements AppSettingsRepository {}
