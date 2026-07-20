import 'dart:async';

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
  test('keeps a user-defined tmux tab order after the server list refreshes',
      () async {
    final settingsRepository = _FakeSettingsRepository();
    final state = AppState(
      authRepository: _FakeAuthRepository(),
      connectionRepository: _FakeConnectionRepository(),
      hostKeyRepository: _FakeHostKeyRepository(),
      settingsRepository: settingsRepository,
      sshSessionService: _FakeSshSessionService(),
    );
    final liveSession = _liveSession();
    final original = [
      _tmuxSession('one'),
      _tmuxSession('two'),
      _tmuxSession('three'),
    ];

    await state.reorderTmuxSessions(liveSession, original, 2, 1);

    expect(
      state.orderedTmuxSessions(
        liveSession,
        [
          _tmuxSession('one'),
          _tmuxSession('two'),
          _tmuxSession('three'),
        ],
      ).map((session) => session.name),
      ['one', 'three', 'two'],
    );
    expect(
      settingsRepository.savedOrders[liveSession.connection.fingerprint],
      ['one', 'three', 'two'],
    );
  });

  test('appends newly discovered tmux sessions after the saved order',
      () async {
    final settingsRepository = _FakeSettingsRepository();
    final state = AppState(
      authRepository: _FakeAuthRepository(),
      connectionRepository: _FakeConnectionRepository(),
      hostKeyRepository: _FakeHostKeyRepository(),
      settingsRepository: settingsRepository,
      sshSessionService: _FakeSshSessionService(),
    );
    final liveSession = _liveSession();
    final original = [
      _tmuxSession('one'),
      _tmuxSession('two'),
      _tmuxSession('three'),
    ];
    await state.reorderTmuxSessions(liveSession, original, 2, 1);

    final ordered = state.orderedTmuxSessions(
      liveSession,
      [...original, _tmuxSession('four')],
    );

    expect(
      ordered.map((session) => session.name),
      ['one', 'three', 'two', 'four'],
    );
  });

  test('moves a tmux tab to a later adjusted index', () async {
    final state = AppState(
      authRepository: _FakeAuthRepository(),
      connectionRepository: _FakeConnectionRepository(),
      hostKeyRepository: _FakeHostKeyRepository(),
      settingsRepository: _FakeSettingsRepository(),
      sshSessionService: _FakeSshSessionService(),
    );
    final liveSession = _liveSession();
    final original = [
      _tmuxSession('one'),
      _tmuxSession('two'),
      _tmuxSession('three'),
    ];

    await state.reorderTmuxSessions(liveSession, original, 0, 2);

    expect(
      state
          .orderedTmuxSessions(liveSession, original)
          .map((session) => session.name),
      ['two', 'three', 'one'],
    );
  });

  test('stores and removes a custom tmux tab name', () async {
    final settingsRepository = _FakeSettingsRepository();
    final state = AppState(
      authRepository: _FakeAuthRepository(),
      connectionRepository: _FakeConnectionRepository(),
      hostKeyRepository: _FakeHostKeyRepository(),
      settingsRepository: settingsRepository,
      sshSessionService: _FakeSshSessionService(),
    );
    final liveSession = _liveSession();

    await state.setTmuxTabName(liveSession, 'one', '  Deploy  ');

    expect(state.tmuxTabName(liveSession, 'one'), 'Deploy');
    expect(
      settingsRepository.savedTabNames[liveSession.connection.fingerprint]
          ?['one'],
      'Deploy',
    );

    await state.setTmuxTabName(liveSession, 'one', '   ');

    expect(state.tmuxTabName(liveSession, 'one'), isNull);
    expect(settingsRepository.savedTabNames, isEmpty);
  });

  test('restoring the default tmux tab label removes the custom name',
      () async {
    final settingsRepository = _FakeSettingsRepository();
    final state = AppState(
      authRepository: _FakeAuthRepository(),
      connectionRepository: _FakeConnectionRepository(),
      hostKeyRepository: _FakeHostKeyRepository(),
      settingsRepository: settingsRepository,
      sshSessionService: _FakeSshSessionService(),
    );
    final liveSession = _liveSession();

    await state.setTmuxTabName(
      liveSession,
      'one',
      '이규배',
      defaultName: '57',
    );
    await state.setTmuxTabName(
      liveSession,
      'one',
      '57',
      defaultName: '57',
    );

    expect(state.tmuxTabName(liveSession, 'one'), isNull);
    expect(settingsRepository.savedTabNames, isEmpty);
  });

  test('renaming one custom tab preserves every other custom name', () async {
    final settingsRepository = _FakeSettingsRepository();
    final state = AppState(
      authRepository: _FakeAuthRepository(),
      connectionRepository: _FakeConnectionRepository(),
      hostKeyRepository: _FakeHostKeyRepository(),
      settingsRepository: settingsRepository,
      sshSessionService: _FakeSshSessionService(),
    );
    final liveSession = _liveSession();

    await state.setTmuxTabName(liveSession, 'one', 'Deploy');
    await state.setTmuxTabName(liveSession, 'two', 'Logs');
    await state.setTmuxTabName(liveSession, 'one', 'Release');

    expect(state.tmuxTabName(liveSession, 'one'), 'Release');
    expect(state.tmuxTabName(liveSession, 'two'), 'Logs');
    expect(
      settingsRepository.savedTabNames[liveSession.connection.fingerprint],
      {
        'one': 'Release',
        'two': 'Logs',
      },
    );
  });

  test('overlapping custom-name saves cannot overwrite a newer name', () async {
    final settingsRepository = _BlockingSettingsRepository();
    final state = AppState(
      authRepository: _FakeAuthRepository(),
      connectionRepository: _FakeConnectionRepository(),
      hostKeyRepository: _FakeHostKeyRepository(),
      settingsRepository: settingsRepository,
      sshSessionService: _FakeSshSessionService(),
    );
    final liveSession = _liveSession();

    final firstSave = state.setTmuxTabName(liveSession, 'one', 'Deploy');
    await settingsRepository.firstSaveStarted.future;

    final secondSave = state.setTmuxTabName(liveSession, 'two', 'Logs');
    await pumpEventQueue();

    expect(settingsRepository.saveCount, 1);

    settingsRepository.releaseFirstSave.complete();
    await Future.wait([firstSave, secondSave]);

    expect(state.tmuxTabName(liveSession, 'one'), 'Deploy');
    expect(state.tmuxTabName(liveSession, 'two'), 'Logs');
    expect(
      settingsRepository.savedTabNames[liveSession.connection.fingerprint],
      {
        'one': 'Deploy',
        'two': 'Logs',
      },
    );
  });
}

LiveSshSession _liveSession() {
  final session = LiveSshSession.testing(
    id: 'live-session',
    client: _FakeSshClient(),
    connection: _connection(),
  );
  session
    ..hostName = 'server.example'
    ..homePath = '/home/seil'
    ..tmuxAvailable = true
    ..shellFallbackPath = '/bin/sh'
    ..tmuxSelectionReady = true;
  return session;
}

SavedConnection _connection() {
  final now = DateTime.utc(2026, 7, 14);
  return SavedConnection(
    id: 'connection-a',
    label: 'Server A',
    host: 'server.example',
    port: 22,
    username: 'seil',
    authMode: AuthMode.password,
    tmuxHistoryLimit: defaultTmuxHistoryLimit,
    fingerprint: 'fingerprint-a',
    hasStoredSecret: true,
    createdAt: now,
    updatedAt: now,
  );
}

RemoteTmuxSession _tmuxSession(String name) {
  return RemoteTmuxSession(
    name: name,
    windows: 1,
    attachedClients: 0,
    createdAt: null,
    lastActivityAt: null,
    currentPath: '/work/$name',
  );
}

class _FakeSettingsRepository extends Fake implements AppSettingsRepository {
  Map<String, List<String>> savedOrders = {};
  Map<String, Map<String, String>> savedTabNames = {};

  @override
  Future<void> saveTmuxSessionOrders(
    Map<String, List<String>> orders,
  ) async {
    savedOrders = {
      for (final entry in orders.entries)
        entry.key: List<String>.from(entry.value),
    };
  }

  @override
  Future<void> saveTmuxTabNames(
    Map<String, Map<String, String>> names,
  ) async {
    savedTabNames = {
      for (final entry in names.entries)
        entry.key: Map<String, String>.from(entry.value),
    };
  }
}

class _BlockingSettingsRepository extends _FakeSettingsRepository {
  final firstSaveStarted = Completer<void>();
  final releaseFirstSave = Completer<void>();
  int saveCount = 0;

  @override
  Future<void> saveTmuxTabNames(
    Map<String, Map<String, String>> names,
  ) async {
    saveCount += 1;
    if (saveCount == 1) {
      firstSaveStarted.complete();
      await releaseFirstSave.future;
    }
    await super.saveTmuxTabNames(names);
  }
}

class _FakeSshClient extends Fake implements SSHClient {
  @override
  bool get isClosed => false;
}

class _FakeAuthRepository extends Fake implements AuthRepository {}

class _FakeConnectionRepository extends Fake implements ConnectionRepository {}

class _FakeHostKeyRepository extends Fake implements HostKeyRepository {}

class _FakeSshSessionService extends Fake implements SshSessionService {}
