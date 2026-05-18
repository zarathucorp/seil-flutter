import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/localization/seil_error_codes.dart';
import '../core/localization/seil_localizations.dart';
import '../core/platform/session_retention_service.dart';
import '../core/platform/terminal_notification_service.dart';
import '../core/settings/app_settings_repository.dart';
import '../features/auth/auth_repository.dart';
import '../features/connections/connection_repository.dart';
import '../features/connections/host_key_repository.dart';
import '../features/sessions/ssh_session_service.dart';
import 'models.dart';
import 'reconnect_policy.dart';

class AppState extends ChangeNotifier {
  AppState({
    required this.authRepository,
    required this.connectionRepository,
    required this.hostKeyRepository,
    required this.settingsRepository,
    required this.sshSessionService,
    this.sessionRetentionService = const SessionRetentionService(),
    this.terminalNotificationService = const TerminalNotificationService(),
    ReconnectPolicy? reconnectPolicy,
  }) : reconnectPolicy = reconnectPolicy ?? ReconnectPolicy();

  final AuthRepository authRepository;
  final ConnectionRepository connectionRepository;
  final HostKeyRepository hostKeyRepository;
  final AppSettingsRepository settingsRepository;
  final SshSessionService sshSessionService;
  final SessionRetentionService sessionRetentionService;
  final TerminalNotificationService terminalNotificationService;
  final ReconnectPolicy reconnectPolicy;

  SeilUser? currentUser;
  List<SavedConnection> connections = [];
  List<TrustedHostKey> trustedHostKeys = [];
  List<LiveSshSession> liveSessions = [];
  final Map<String, RemoteDirectory> sessionDirectories = {};
  final Map<String, int> sessionPaneIndexes = {};
  final Map<String, String> _sessionNames = {};
  final Map<String, SessionTag> _tmuxTags = {};
  final Map<String, TmuxCaptureFrame> _terminalFrames = {};
  final Map<Object, StreamSubscription<TmuxAttentionSignal>>
      _tmuxAttentionSubscriptions = {};
  final Map<Object, Timer> _tmuxAttentionRefreshTimers = {};
  final Map<int, int> _terminalAttentionNotificationSerials = {};
  final Map<int, String> _terminalAttentionNotificationBodies = {};
  final Map<String, _CachedDirectory> _directoryCache = {};
  final Map<String, List<String>> _directoryBackStacks = {};
  final Map<String, String> _reconnectSecrets = {};
  LiveSshSession? activeSession;
  RemoteDirectory? activeDirectory;
  bool needsBootstrap = false;
  bool busy = false;
  bool reconnecting = false;
  bool loginPasswordEnabled = false;
  bool lowEndModeEnabled = false;
  bool terminalAttentionNotificationsEnabled = false;
  bool terminalAttentionNotificationTailEnabled = true;
  String appLanguageCode = AppSettingsRepository.systemLanguageCode;
  List<String> keyboardMacros = List<String>.filled(
    AppSettingsRepository.keyboardMacroCount,
    '',
  );
  String? connectingConnectionId;
  String? errorMessage;
  bool errorShowsPopup = true;
  int errorSerial = 0;
  int _busyDepth = 0;
  int _terminalAttentionNotificationSerial = 0;
  Future<void> _sessionStartTail = Future.value();
  DateTime? _backgroundedAt;
  DateTime? _lastResumedAt;
  Timer? _backgroundKeepAliveTimer;
  Timer? _backgroundRetentionTimer;
  Timer? _reconnectRetryTimer;
  bool isInForeground = true;
  TerminalNotificationLaunchTarget? _pendingTerminalNotificationTarget;

  static const _directoryCacheTtl = Duration(seconds: 20);
  static const _reconnectErrorDelay = Duration(seconds: 5);
  static const _terminalAttentionPreviewLines = 10;
  static const _terminalAttentionNotificationSettleDelay =
      Duration(milliseconds: 700);
  static const _terminalAttentionNotificationRetryDelays = [
    Duration(milliseconds: 900),
    Duration(milliseconds: 1400),
  ];
  static const backgroundRetentionDuration = Duration(minutes: 10);
  static const _backgroundKeepAliveInterval = Duration(seconds: 25);
  static const hotResumeWindow = backgroundRetentionDuration;
  static const resumeReconnectNoticeGrace = Duration(seconds: 1);

  int get activePaneIndex {
    final session = activeSession;
    if (session == null) {
      return 0;
    }
    return sessionPaneIndexes[terminalFrameKey(session)] ?? 0;
  }

  Future<void> initialize() async {
    terminalNotificationService.setLaunchTargetHandler(
      (target) => unawaited(focusTerminalNotificationTarget(target)),
    );
    loginPasswordEnabled = await settingsRepository.isLoginPasswordEnabled();
    lowEndModeEnabled = await settingsRepository.isLowEndModeEnabled();
    terminalAttentionNotificationsEnabled =
        await settingsRepository.areTerminalAttentionNotificationsEnabled();
    terminalAttentionNotificationTailEnabled =
        await settingsRepository.isTerminalAttentionNotificationTailEnabled();
    appLanguageCode = await settingsRepository.loadAppLanguageCode();
    keyboardMacros = await settingsRepository.loadKeyboardMacros();
    needsBootstrap = !(await authRepository.hasUsers());
    if (!needsBootstrap) {
      connections = await connectionRepository.listConnections();
      trustedHostKeys = await hostKeyRepository.listTrustedHostKeys();
    }
    final launchTarget =
        await terminalNotificationService.consumeLaunchTarget();
    if (launchTarget != null) {
      unawaited(focusTerminalNotificationTarget(launchTarget));
    }
  }

  void enterBackground() {
    isInForeground = false;
    _backgroundedAt ??= DateTime.now();
    _startBackgroundRetention();
  }

  void resumeFromBackground() {
    isInForeground = true;
    _stopBackgroundRetention();
    final now = DateTime.now();
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    _lastResumedAt = now;
    final hotResume = backgroundedAt != null &&
        now.difference(backgroundedAt) <= hotResumeWindow;
    unawaited(_verifySessionsAfterResume(hotResume: hotResume));
  }

  bool get shouldDeferReconnectNotice {
    final resumedAt = _lastResumedAt;
    if (resumedAt == null) {
      return false;
    }
    return DateTime.now().difference(resumedAt) < resumeReconnectNoticeGrace;
  }

  Duration get reconnectNoticeDelay {
    final resumedAt = _lastResumedAt;
    if (resumedAt == null) {
      return Duration.zero;
    }
    final elapsed = DateTime.now().difference(resumedAt);
    final remaining = resumeReconnectNoticeGrace - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> _verifySessionsAfterResume({required bool hotResume}) async {
    await pingLiveSessions();
    await reconnectClosedSessions(force: !hotResume);
  }

  void _startBackgroundRetention() {
    if (currentUser == null || liveSessions.isEmpty) {
      return;
    }
    unawaited(sessionRetentionService.start(
      duration: backgroundRetentionDuration,
      activeSessions: liveSessions.length,
    ));
    _backgroundKeepAliveTimer?.cancel();
    _backgroundKeepAliveTimer = Timer.periodic(
      _backgroundKeepAliveInterval,
      (_) => unawaited(_backgroundSessionTick()),
    );
    _backgroundRetentionTimer?.cancel();
    _backgroundRetentionTimer = Timer(
      backgroundRetentionDuration,
      _stopBackgroundRetention,
    );
    unawaited(_backgroundSessionTick());
  }

  void _stopBackgroundRetention() {
    _backgroundKeepAliveTimer?.cancel();
    _backgroundKeepAliveTimer = null;
    _backgroundRetentionTimer?.cancel();
    _backgroundRetentionTimer = null;
    unawaited(sessionRetentionService.stop());
  }

  Future<void> _backgroundSessionTick() async {
    await pingLiveSessions();
    if (terminalAttentionNotificationsEnabled) {
      await refreshActiveTmuxSessions(silent: true);
    }
  }

  @override
  void dispose() {
    _stopBackgroundRetention();
    _reconnectRetryTimer?.cancel();
    _cancelTmuxAttentionObservers();
    terminalNotificationService.setLaunchTargetHandler(null);
    super.dispose();
  }

  Future<void> bootstrapAndLogin({
    required String username,
    required String name,
    required String password,
  }) async {
    await _run(() async {
      currentUser = await authRepository.bootstrapAdmin(
          username: username, name: name, password: password);
      needsBootstrap = false;
      connections = await connectionRepository.listConnections();
      trustedHostKeys = await hostKeyRepository.listTrustedHostKeys();
    });
  }

  Future<void> loginWithPassword(String password) async {
    await _run(() async {
      final user = await authRepository.authenticateDefault(password);
      if (user == null) {
        throw StateError(SeilErrorCodes.incorrectPassword);
      }
      currentUser = user;
      connections = await connectionRepository.listConnections();
      trustedHostKeys = await hostKeyRepository.listTrustedHostKeys();
    });
  }

  Future<void> loginWithoutPassword() async {
    await _run(() async {
      if (needsBootstrap) {
        currentUser = await authRepository.bootstrapLocalAdmin();
        needsBootstrap = false;
      } else {
        currentUser = await authRepository.defaultUser();
      }
      if (currentUser == null) {
        throw StateError(SeilErrorCodes.userNotFound);
      }
      connections = await connectionRepository.listConnections();
      trustedHostKeys = await hostKeyRepository.listTrustedHostKeys();
    });
  }

  Future<void> logout() async {
    await _closeAllSessions();
    _reconnectSecrets.clear();
    reconnectPolicy.clearAll();
    _stopBackgroundRetention();
    _reconnectRetryTimer?.cancel();
    _reconnectRetryTimer = null;
    _cancelTmuxAttentionObservers();
    activeSession = null;
    activeDirectory = null;
    currentUser = null;
    notifyListeners();
  }

  Future<void> refreshConnections() async {
    connections = await connectionRepository.listConnections();
    notifyListeners();
  }

  Future<void> deleteConnection(SavedConnection connection) async {
    await _run(() async {
      await connectionRepository.deleteConnection(connection.id);
      _reconnectSecrets.remove(connection.fingerprint);
      final sessionsToClose = liveSessions
          .where((session) =>
              session.connection.fingerprint == connection.fingerprint)
          .toList();
      for (final session in sessionsToClose) {
        await session.cleanupTemporaryUploads();
        _removeSession(session);
      }
      connections = await connectionRepository.listConnections();
    });
  }

  Future<void> trustHostKey({
    required String host,
    required int port,
    required String keyType,
    required String fingerprintSha256,
  }) async {
    await _run(() async {
      await hostKeyRepository.trustHostKey(
        host: host,
        port: port,
        keyType: keyType,
        fingerprintSha256: fingerprintSha256,
      );
      trustedHostKeys = await hostKeyRepository.listTrustedHostKeys();
    });
  }

  Future<void> deleteTrustedHostKey(TrustedHostKey hostKey) async {
    await _run(() async {
      await hostKeyRepository.deleteTrustedHostKey(hostKey.id);
      trustedHostKeys = await hostKeyRepository.listTrustedHostKeys();
    });
  }

  Future<void> setLoginPasswordEnabled(bool enabled,
      {String? newPassword}) async {
    await _run(() async {
      final user = currentUser;
      if (enabled) {
        if (user == null) {
          throw StateError(SeilErrorCodes.noLoggedInUser);
        }
        final password = newPassword ?? '';
        await authRepository.setPassword(
            userId: user.id, newPassword: password);
        currentUser = await authRepository.getUserById(user.id);
      }
      await settingsRepository.setLoginPasswordEnabled(enabled);
      loginPasswordEnabled = enabled;
    });
  }

  Future<void> setLowEndModeEnabled(bool enabled) async {
    if (lowEndModeEnabled == enabled) {
      return;
    }
    final previous = lowEndModeEnabled;
    lowEndModeEnabled = enabled;
    notifyListeners();
    try {
      await settingsRepository.setLowEndModeEnabled(enabled);
    } catch (error) {
      lowEndModeEnabled = previous;
      _setError(seilLocalizedErrorMessage(appLanguageCode, error),
          showPopup: false);
      notifyListeners();
    }
  }

  Future<void> setTerminalAttentionNotificationsEnabled(bool enabled) async {
    if (terminalAttentionNotificationsEnabled == enabled) {
      return;
    }
    var nextEnabled = enabled;
    if (enabled) {
      nextEnabled = await terminalNotificationService.requestPermission();
    }
    final previous = terminalAttentionNotificationsEnabled;
    terminalAttentionNotificationsEnabled = nextEnabled;
    notifyListeners();
    try {
      await settingsRepository
          .setTerminalAttentionNotificationsEnabled(nextEnabled);
    } catch (error) {
      terminalAttentionNotificationsEnabled = previous;
      _setError(seilLocalizedErrorMessage(appLanguageCode, error),
          showPopup: false);
      notifyListeners();
    }
  }

  Future<void> setTerminalAttentionNotificationTailEnabled(
    bool enabled,
  ) async {
    if (terminalAttentionNotificationTailEnabled == enabled) {
      return;
    }
    final previous = terminalAttentionNotificationTailEnabled;
    terminalAttentionNotificationTailEnabled = enabled;
    notifyListeners();
    try {
      await settingsRepository.setTerminalAttentionNotificationTailEnabled(
        enabled,
      );
    } catch (error) {
      terminalAttentionNotificationTailEnabled = previous;
      _setError(seilLocalizedErrorMessage(appLanguageCode, error),
          showPopup: false);
      notifyListeners();
    }
  }

  Future<void> setAppLanguageCode(String languageCode) async {
    final normalized =
        AppSettingsRepository.supportedLanguageCodes.contains(languageCode)
            ? languageCode
            : AppSettingsRepository.systemLanguageCode;
    if (appLanguageCode == normalized) {
      return;
    }
    final previous = appLanguageCode;
    appLanguageCode = normalized;
    notifyListeners();
    try {
      await settingsRepository.saveAppLanguageCode(normalized);
    } catch (error) {
      appLanguageCode = previous;
      _setError(seilLocalizedErrorMessage(appLanguageCode, error),
          showPopup: false);
      notifyListeners();
    }
  }

  String keyboardMacro(int index) {
    if (index < 0 || index >= keyboardMacros.length) {
      return '';
    }
    return keyboardMacros[index];
  }

  Future<void> saveKeyboardMacros(List<String> macros) async {
    await _run(() async {
      keyboardMacros = List<String>.generate(
        AppSettingsRepository.keyboardMacroCount,
        (index) => index < macros.length ? macros[index] : '',
      );
      await settingsRepository.saveKeyboardMacros(keyboardMacros);
    });
  }

  Future<void> connectNew(SshConnectionInput input,
      {int initialPaneIndex = 0}) async {
    final fingerprint = connectionRepository.createConnectionFingerprint(input);
    final existed = connections.any(
      (connection) => connection.fingerprint == fingerprint,
    );
    await _run(() async {
      final connection = await connectionRepository.upsertConnection(input);
      connections = await connectionRepository.listConnections();
      try {
        await _connect(
          connection,
          transientSecret: input.secret,
          initialPaneIndex: initialPaneIndex,
        );
      } catch (error) {
        if (!existed) {
          await connectionRepository.deleteConnection(connection.id);
          connections = await connectionRepository.listConnections();
        }
        throw StateError(seilConnectionFailureMessage(appLanguageCode, error));
      }
    });
  }

  Future<void> connectSaved(SavedConnection connection,
      {String? transientSecret,
      int initialPaneIndex = 0,
      bool reuseExisting = true}) async {
    connectingConnectionId = connection.id;
    notifyListeners();
    try {
      await _run(() async {
        try {
          await _connect(connection,
              transientSecret: transientSecret,
              initialPaneIndex: initialPaneIndex,
              reuseExisting: reuseExisting);
        } catch (error) {
          throw StateError(
              seilConnectionFailureMessage(appLanguageCode, error));
        }
      });
    } finally {
      if (connectingConnectionId == connection.id) {
        connectingConnectionId = null;
        notifyListeners();
      }
    }
  }

  Future<void> _connect(SavedConnection connection,
      {String? transientSecret,
      int initialPaneIndex = 0,
      bool reuseExisting = true}) async {
    final existing = _findOpenSessionForConnection(connection);
    if (existing != null) {
      if (!reuseExisting) {
        await _serializeSessionStart(() async {
          await _startTerminalSessionFrom(
            existing,
            path: sessionDirectories[terminalFrameKey(existing)]?.currentPath ??
                existing.currentPath,
            initialPaneIndex: initialPaneIndex,
            selectNewTmux: true,
          );
        });
        return;
      }
      activeSession = existing;
      activeDirectory = sessionDirectories[terminalFrameKey(existing)];
      sessionPaneIndexes.putIfAbsent(
          terminalFrameKey(existing), () => initialPaneIndex);
      return;
    }

    final secret =
        await connectionRepository.resolveSecret(connection, transientSecret);
    if (connection.authMode != AuthMode.agent &&
        (secret == null || secret.isEmpty)) {
      throw StateError(SeilErrorCodes.missingSshSecret);
    }
    final session = await sshSessionService.connect(
        connection: connection, secret: secret ?? '');
    final directory = await session.listDirectory(session.homePath);
    if (secret != null && secret.isNotEmpty) {
      _reconnectSecrets[connection.fingerprint] = secret;
    }
    reconnectPolicy.recordSuccess(connection.fingerprint);
    liveSessions.add(session);
    sessionDirectories[terminalFrameKey(session)] = directory;
    _cacheDirectory(session, directory);
    sessionPaneIndexes[terminalFrameKey(session)] = initialPaneIndex;
    activeSession = session;
    activeDirectory = directory;
    _ensureTmuxAttentionObserver(session);
    unawaited(_applyPendingTerminalNotificationTarget());
  }

  void selectSession(LiveSshSession session) {
    activeSession = session;
    activeDirectory = sessionDirectories[terminalFrameKey(session)];
    notifyListeners();
  }

  Future<void> focusTerminalNotificationTarget(
    TerminalNotificationLaunchTarget target,
  ) async {
    final connectionFingerprint = target.connectionFingerprint.trim();
    final tmuxSessionName = target.tmuxSessionName.trim();
    if (connectionFingerprint.isEmpty || tmuxSessionName.isEmpty) {
      return;
    }
    final session = _liveSessionForConnectionFingerprint(connectionFingerprint);
    if (session == null) {
      _pendingTerminalNotificationTarget = target;
      return;
    }
    activeSession = session;
    activeDirectory = sessionDirectories[terminalFrameKey(session)];
    notifyListeners();
    var tmuxSession = _tmuxSessionByName(session, tmuxSessionName);
    if (tmuxSession == null && session.tmuxAvailable) {
      try {
        final previous = List<RemoteTmuxSession>.from(session.tmuxSessions);
        final sessions = _resolveTmuxAttentionTransitions(
          source: session,
          previous: previous,
          current: await session.listTmuxSessions(),
        );
        _syncTmuxSessionsForClient(session, sessions);
        tmuxSession = _tmuxSessionByName(session, tmuxSessionName);
      } catch (_) {
        return;
      }
    }
    if (tmuxSession == null) {
      return;
    }
    _pendingTerminalNotificationTarget = null;
    await selectTmuxSession(tmuxSession);
    await _sendTerminalNotificationAction(session, target);
  }

  String terminalFrameKey(LiveSshSession session) {
    return '${session.id}:${session.selectedTmuxSessionName ?? 'new'}';
  }

  TmuxCaptureFrame? cachedTerminalFrame(LiveSshSession? session) {
    if (session == null) {
      return null;
    }
    return _terminalFrames[terminalFrameKey(session)];
  }

  void cacheTerminalFrame(LiveSshSession session, TmuxCaptureFrame frame) {
    _terminalFrames[terminalFrameKey(session)] = frame;
  }

  int sessionNumber(LiveSshSession session) {
    final index = liveSessions.indexWhere((item) => item.id == session.id);
    return index < 0 ? 0 : index + 1;
  }

  String? sessionCustomName(LiveSshSession session) {
    final name = _sessionNames[session.id]?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  String sessionLabel(LiveSshSession session) {
    final path = session.currentPath.trim();
    return path.isEmpty ? session.displayName : path;
  }

  String nextTmuxSessionName(LiveSshSession session) {
    return session.nextAvailableTmuxSessionName(
      reservedNames: _reservedTmuxNamesForClient(session),
      basePath: _sessionDirectoryPath(session),
    );
  }

  void renameSession(LiveSshSession session, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _sessionNames.remove(session.id);
    } else {
      _sessionNames[session.id] = trimmed;
    }
    notifyListeners();
  }

  void selectActivePane(int index) {
    final session = activeSession;
    if (session == null) {
      return;
    }
    sessionPaneIndexes[terminalFrameKey(session)] = index;
    notifyListeners();
  }

  Future<void> refreshActiveTmuxSessions({bool silent = false}) async {
    final session = activeSession;
    if (session == null || !session.tmuxAvailable) {
      return;
    }
    if (silent) {
      try {
        final previous = List<RemoteTmuxSession>.from(session.tmuxSessions);
        final sessions = _resolveTmuxAttentionTransitions(
          source: session,
          previous: previous,
          current: await session.listTmuxSessions(),
        );
        if (_tmuxSessionListsEqual(previous, sessions)) {
          _syncTmuxSessionsForClient(session, sessions);
          return;
        }
        _syncTmuxSessionsForClient(session, sessions);
        unawaited(_notifyTerminalAttentionTransitions(
          source: session,
          previous: previous,
          current: sessions,
        ));
        notifyListeners();
      } catch (_) {
        return;
      }
      return;
    }
    await _run(() async {
      final previous = List<RemoteTmuxSession>.from(session.tmuxSessions);
      final sessions = _resolveTmuxAttentionTransitions(
        source: session,
        previous: previous,
        current: await session.listTmuxSessions(),
      );
      _syncTmuxSessionsForClient(session, sessions);
      unawaited(_notifyTerminalAttentionTransitions(
        source: session,
        previous: previous,
        current: sessions,
      ));
    });
  }

  Future<void> selectTmuxSession(RemoteTmuxSession tmuxSession) async {
    final session = activeSession;
    if (session == null) {
      return;
    }
    final previousPaneIndex = activePaneIndex;
    session.selectTmuxSession(tmuxSession);
    if (tmuxSession.currentPath?.trim().isNotEmpty == true) {
      session.currentPath = tmuxSession.currentPath!.trim();
    }
    final workspaceKey = terminalFrameKey(session);
    sessionPaneIndexes.putIfAbsent(workspaceKey, () => previousPaneIndex);
    activeDirectory = sessionDirectories[workspaceKey];
    notifyListeners();
    if (activeDirectory == null) {
      final path = tmuxSession.currentPath?.trim().isNotEmpty == true
          ? tmuxSession.currentPath!.trim()
          : session.currentPath;
      await loadDirectory(path, addToHistory: false);
    }
  }

  void acknowledgeCompletedTmuxSession(RemoteTmuxSession tmuxSession) {
    if (tmuxSession.attentionState != TerminalAttentionState.completed) {
      return;
    }
    final session = activeSession;
    if (session == null) {
      return;
    }
    var changed = false;
    for (final liveSession in liveSessions) {
      if (liveSession.client != session.client) {
        continue;
      }
      final nextSessions = [
        for (final item in liveSession.tmuxSessions)
          item.name == tmuxSession.name
              ? _copyTmuxSessionWithAttention(
                  item,
                  TerminalAttentionState.none,
                )
              : item,
      ];
      if (!_tmuxSessionListsEqual(liveSession.tmuxSessions, nextSessions)) {
        liveSession.tmuxSessions = nextSessions;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> selectNewTmuxSession({String? basePath}) async {
    final session = activeSession;
    if (session == null) {
      return;
    }
    var selectedPath = basePath ?? session.homePath;
    await _serializeSessionStart(() async {
      await _run(() async {
        if (session.tmuxAvailable) {
          _syncTmuxSessionsForClient(session, await session.listTmuxSessions());
        }
        selectedPath = basePath ?? session.homePath;
        session.selectNewTmuxSession(
          reservedNames: _reservedTmuxNamesForClient(session),
          basePath: selectedPath,
        );
        _appendSelectedTmuxSessionForClient(session);
        final workspaceKey = terminalFrameKey(session);
        sessionPaneIndexes.putIfAbsent(workspaceKey, () => activePaneIndex);
        activeDirectory = sessionDirectories[workspaceKey];
      }, showErrorPopup: false);
    });
    if (activeSession?.id == session.id && activeDirectory == null) {
      await loadDirectory(selectedPath, addToHistory: false);
    }
  }

  SessionTag? tmuxSessionTag(LiveSshSession session, String tmuxName) {
    return _tmuxTags[_tmuxTagKey(session.connection, tmuxName)];
  }

  void setTmuxSessionTag(
    LiveSshSession session,
    String tmuxName, {
    required String label,
    required int colorValue,
  }) {
    final trimmed = label.trim();
    final key = _tmuxTagKey(session.connection, tmuxName);
    if (trimmed.isEmpty) {
      _tmuxTags.remove(key);
    } else {
      _tmuxTags[key] = SessionTag(label: trimmed, colorValue: colorValue);
    }
    notifyListeners();
  }

  void updateSessionCurrentPath(LiveSshSession session, String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty || session.currentPath == trimmed) {
      return;
    }
    session.currentPath = trimmed;
    final selectedName = session.selectedTmuxSessionName;
    if (selectedName != null) {
      session.tmuxSessions = [
        for (final tmuxSession in session.tmuxSessions)
          tmuxSession.name == selectedName
              ? RemoteTmuxSession(
                  name: tmuxSession.name,
                  windows: tmuxSession.windows,
                  attachedClients: tmuxSession.attachedClients,
                  createdAt: tmuxSession.createdAt,
                  lastActivityAt: tmuxSession.lastActivityAt,
                  currentPath: trimmed,
                  attentionState: tmuxSession.attentionState,
                  attentionPaneId: tmuxSession.attentionPaneId,
                  terminalTitle: tmuxSession.terminalTitle,
                  windowFlags: tmuxSession.windowFlags,
                )
              : tmuxSession,
      ];
    }
    notifyListeners();
  }

  Future<void> detachActiveSession() async {
    activeSession = null;
    activeDirectory = null;
    notifyListeners();
  }

  Future<void> closeActiveSession() async {
    final session = activeSession;
    if (session == null) {
      return;
    }
    await closeSession(session);
  }

  Future<void> disconnect() => closeActiveSession();

  Future<void> deleteActiveTmuxSession() async {
    final session = activeSession;
    final tmuxName = session?.selectedTmuxSessionName?.trim();
    if (session == null || !session.tmuxAvailable || tmuxName == null) {
      return;
    }
    if (tmuxName.isEmpty) {
      return;
    }

    await deleteTmuxSession(session, tmuxName);
  }

  Future<void> deleteTmuxSession(
    LiveSshSession session,
    String tmuxName,
  ) async {
    final trimmed = tmuxName.trim();
    if (!session.tmuxAvailable || trimmed.isEmpty) {
      return;
    }

    await _run(() async {
      for (final liveSession in liveSessions) {
        if (liveSession.client == session.client) {
          await liveSession.cleanupTemporaryUploads(tmuxSessionName: trimmed);
        }
      }
      final previousSessions = List<RemoteTmuxSession>.from(
        session.tmuxSessions,
      );
      final selectedNames = {
        for (final liveSession in liveSessions)
          if (liveSession.client == session.client)
            liveSession.id: liveSession.selectedTmuxSessionName,
      };
      final sessions = await session.killTmuxSession(trimmed);
      _tmuxTags.remove(_tmuxTagKey(session.connection, trimmed));
      if (sessions.isEmpty) {
        await _closeSessionsForClient(session);
        return;
      }
      final fallbackSession = _tmuxSessionBeforeDeleted(
        previousSessions: previousSessions,
        sessions: sessions,
        deletedName: trimmed,
      );
      var nextSessions = List<RemoteTmuxSession>.from(sessions);
      for (final liveSession in liveSessions) {
        if (liveSession.client == session.client &&
            selectedNames[liveSession.id] != trimmed) {
          nextSessions = _appendSelectedTmuxSession(nextSessions, liveSession);
        }
      }
      for (final liveSession in liveSessions) {
        if (liveSession.client != session.client) {
          continue;
        }
        liveSession.tmuxSessions = List<RemoteTmuxSession>.from(nextSessions);
        if (selectedNames[liveSession.id] == trimmed) {
          if (fallbackSession == null) {
            liveSession.resetTmuxSelection(sessions: nextSessions);
          } else {
            _selectTmuxSession(liveSession, fallbackSession);
          }
        }
      }
    });
    final active = activeSession;
    if (active?.client == session.client &&
        active?.selectedTmuxSession != null &&
        activeDirectory == null) {
      final selected = active!.selectedTmuxSession!;
      final path = selected.currentPath?.trim().isNotEmpty == true
          ? selected.currentPath!.trim()
          : active.currentPath;
      await loadDirectory(path, addToHistory: false);
    }
  }

  Future<void> closeSession(LiveSshSession session) async {
    await session.cleanupTemporaryUploads();
    _removeSession(session);
    notifyListeners();
  }

  void _removeSession(LiveSshSession session) {
    final index = liveSessions.indexWhere((item) => item.id == session.id);
    if (index < 0) {
      return;
    }

    liveSessions.removeAt(index);
    sessionDirectories
        .removeWhere((key, _) => key.startsWith('${session.id}:'));
    sessionPaneIndexes
        .removeWhere((key, _) => key.startsWith('${session.id}:'));
    _directoryBackStacks
        .removeWhere((key, _) => key.startsWith('${session.id}:'));
    _sessionNames.remove(session.id);
    _terminalFrames.removeWhere((key, _) => key.startsWith('${session.id}:'));
    _directoryCache.removeWhere((key, _) => key.startsWith('${session.id}:'));
    final closeClient = !_hasOtherSessionsOnClient(session);
    if (closeClient) {
      _cancelTmuxAttentionObserver(session.client);
    }
    session.close(closeClient: closeClient);
    if (!_hasOtherSessionsForConnection(session.connection)) {
      _reconnectSecrets.remove(session.connection.fingerprint);
      reconnectPolicy.clear(session.connection.fingerprint);
    }
    if (liveSessions.isEmpty) {
      _stopBackgroundRetention();
    }

    if (activeSession?.id == session.id) {
      final previousIndex = index <= 0 ? 0 : index - 1;
      activeSession = liveSessions.isEmpty
          ? null
          : liveSessions[previousIndex.clamp(0, liveSessions.length - 1)];
      activeDirectory = activeSession == null
          ? null
          : sessionDirectories[terminalFrameKey(activeSession!)];
    }
  }

  Future<void> _closeSessionsForClient(LiveSshSession source) async {
    final sessions = liveSessions
        .where((session) => session.client == source.client)
        .toList();
    for (final session in sessions) {
      await session.cleanupTemporaryUploads();
    }
    for (final session in sessions) {
      _removeSession(session);
    }
  }

  Future<void> reconnectClosedSessions({bool force = false}) async {
    if (reconnecting || currentUser == null || liveSessions.isEmpty) {
      return;
    }

    final allClosedSessions =
        liveSessions.where((session) => session.isClosed).toList();
    final closedSessions = allClosedSessions
        .where((session) => reconnectPolicy.canAttempt(
              session.connection.fingerprint,
              force: force,
            ))
        .toList();
    if (closedSessions.isEmpty) {
      _scheduleReconnectRetry();
      return;
    }

    _reconnectRetryTimer?.cancel();
    _reconnectRetryTimer = null;
    reconnecting = true;
    errorMessage = null;
    final reconnectStartedAt = DateTime.now();
    notifyListeners();

    final replacements = <String, LiveSshSession>{};
    final reconnectedByClient = <Object, LiveSshSession>{};
    final newDirectories = <String, RemoteDirectory>{};
    final newPaneIndexes = <String, int>{};
    final newSessionNames = <String, String>{};
    final newTerminalFrames = <String, TmuxCaptureFrame>{};
    final newDirectoryBackStacks = <String, List<String>>{};
    final oldActiveId = activeSession?.id;
    final attemptedFingerprints = {
      for (final session in closedSessions) session.connection.fingerprint,
    };

    try {
      for (final oldSession in closedSessions) {
        final baseSession = reconnectedByClient[oldSession.client];
        final replacement = baseSession == null
            ? await _reconnectRootSession(oldSession)
            : baseSession.createTerminalSession(
                initialPath: _sessionDirectoryPath(oldSession),
              );

        reconnectedByClient[oldSession.client] = baseSession ?? replacement;
        _restoreSessionSelection(oldSession, replacement);

        final directory = await _loadReconnectDirectory(
          replacement,
          _sessionDirectoryPath(oldSession),
        );
        final oldWorkspaceKey = terminalFrameKey(oldSession);
        final replacementWorkspaceKey = terminalFrameKey(replacement);
        replacements[oldSession.id] = replacement;
        newDirectories[replacementWorkspaceKey] = directory;
        _cacheDirectory(replacement, directory);
        newPaneIndexes[replacementWorkspaceKey] =
            sessionPaneIndexes[oldWorkspaceKey] ?? 0;
        final oldName = _sessionNames[oldSession.id];
        if (oldName != null) {
          newSessionNames[replacement.id] = oldName;
        }
        final oldFrame = _terminalFrames[terminalFrameKey(oldSession)];
        if (oldFrame != null) {
          newTerminalFrames[terminalFrameKey(replacement)] = oldFrame;
        }
        final oldBackStack = _directoryBackStacks[oldWorkspaceKey];
        if (oldBackStack != null) {
          newDirectoryBackStacks[replacementWorkspaceKey] =
              List<String>.from(oldBackStack);
        }
      }

      liveSessions = [
        for (final session in liveSessions) replacements[session.id] ?? session,
      ];
      for (final oldSession in closedSessions) {
        sessionDirectories
            .removeWhere((key, _) => key.startsWith('${oldSession.id}:'));
        sessionPaneIndexes
            .removeWhere((key, _) => key.startsWith('${oldSession.id}:'));
        _directoryBackStacks
            .removeWhere((key, _) => key.startsWith('${oldSession.id}:'));
        _sessionNames.remove(oldSession.id);
        _terminalFrames.removeWhere(
          (key, _) => key.startsWith('${oldSession.id}:'),
        );
        _directoryCache.removeWhere(
          (key, _) => key.startsWith('${oldSession.id}:'),
        );
      }
      sessionDirectories.addAll(newDirectories);
      sessionPaneIndexes.addAll(newPaneIndexes);
      _directoryBackStacks.addAll(newDirectoryBackStacks);
      _sessionNames.addAll(newSessionNames);
      _terminalFrames.addAll(newTerminalFrames);

      if (oldActiveId != null && replacements.containsKey(oldActiveId)) {
        activeSession = replacements[oldActiveId];
        activeDirectory = sessionDirectories[terminalFrameKey(activeSession!)];
      }
      for (final fingerprint in attemptedFingerprints) {
        reconnectPolicy.recordSuccess(fingerprint);
      }
    } catch (error) {
      for (final fingerprint in attemptedFingerprints) {
        reconnectPolicy.recordFailure(
          fingerprint,
          error,
          requiresManualRetry: _isReconnectUserActionRequired(error),
        );
      }
      _scheduleReconnectRetry();
      if (DateTime.now().difference(reconnectStartedAt) >=
              _reconnectErrorDelay ||
          force ||
          _isReconnectUserActionRequired(error)) {
        _setError(
          seilLocalizedErrorMessage(
            appLanguageCode,
            SeilErrorCodes.sshReconnectFailed(error),
          ),
          showPopup: false,
        );
      }
    } finally {
      reconnecting = false;
      notifyListeners();
    }
  }

  Future<void> createTerminalSessionFromActive({
    String? path,
    int initialPaneIndex = 0,
    bool selectNewTmux = false,
  }) async {
    final source = activeSession;
    if (source == null) {
      return;
    }

    await _serializeSessionStart(() async {
      await _run(() async {
        await _startTerminalSessionFrom(
          source,
          path: path ?? activeDirectory?.currentPath ?? source.currentPath,
          initialPaneIndex: initialPaneIndex,
          selectNewTmux: selectNewTmux,
        );
      });
    });
  }

  Future<void> loadDirectory(
    String path, {
    bool force = false,
    bool addToHistory = true,
  }) async {
    final session = activeSession;
    if (session == null) {
      return;
    }
    final workspaceKey = terminalFrameKey(session);
    final fromPath = sessionDirectories[workspaceKey]?.currentPath;
    final cached = force ? null : _cachedDirectory(session, path);
    if (cached != null) {
      _recordDirectoryHistory(session, fromPath, cached.currentPath,
          addToHistory: addToHistory);
      activeDirectory = cached;
      sessionDirectories[workspaceKey] = cached;
      notifyListeners();
      return;
    }
    await _run(() async {
      final directory = await session.listDirectory(path);
      _recordDirectoryHistory(session, fromPath, directory.currentPath,
          addToHistory: addToHistory);
      sessionDirectories[workspaceKey] = directory;
      _cacheDirectory(session, directory);
      if (activeSession?.id == session.id &&
          terminalFrameKey(activeSession!) == workspaceKey) {
        activeDirectory = directory;
      }
    });
  }

  Future<void> createFolder(String name) async {
    final session = activeSession;
    final directory = activeDirectory;
    if (session == null || directory == null) {
      return;
    }
    final workspaceKey = terminalFrameKey(session);
    await _run(() async {
      await session.createDirectory(directory.currentPath, name);
      _invalidateDirectory(session, directory.currentPath);
      final refreshed = await session.listDirectory(directory.currentPath);
      sessionDirectories[workspaceKey] = refreshed;
      _cacheDirectory(session, refreshed);
      if (activeSession?.id == session.id &&
          terminalFrameKey(activeSession!) == workspaceKey) {
        activeDirectory = refreshed;
      }
    });
  }

  Future<void> renameEntry(RemoteFileEntry entry, String newName) async {
    final session = activeSession;
    final directory = activeDirectory;
    if (session == null || directory == null) {
      return;
    }
    final workspaceKey = terminalFrameKey(session);
    await _run(() async {
      await session.rename(entry.path, newName);
      _invalidateDirectory(session, directory.currentPath);
      final refreshed = await session.listDirectory(directory.currentPath);
      sessionDirectories[workspaceKey] = refreshed;
      _cacheDirectory(session, refreshed);
      if (activeSession?.id == session.id &&
          terminalFrameKey(activeSession!) == workspaceKey) {
        activeDirectory = refreshed;
      }
    });
  }

  Future<void> deleteFileEntries(List<RemoteFileEntry> entries) async {
    final session = activeSession;
    final directory = activeDirectory;
    final files = entries.where((entry) => !entry.isDirectory).toList();
    if (session == null || directory == null || files.isEmpty) {
      return;
    }
    final workspaceKey = terminalFrameKey(session);
    await _run(() async {
      for (final entry in files) {
        await session.deleteRemoteFile(entry.path);
      }
      _invalidateDirectory(session, directory.currentPath);
      final refreshed = await session.listDirectory(directory.currentPath);
      sessionDirectories[workspaceKey] = refreshed;
      _cacheDirectory(session, refreshed);
      if (activeSession?.id == session.id &&
          terminalFrameKey(activeSession!) == workspaceKey) {
        activeDirectory = refreshed;
      }
    });
  }

  Future<void> uploadFileStream({
    required String directoryPath,
    required String name,
    required Stream<List<int>> stream,
    bool temporary = false,
  }) async {
    final session = activeSession;
    if (session == null) {
      return;
    }
    final workspaceKey = terminalFrameKey(session);
    await _run(() async {
      await session.uploadStream(directoryPath, name, stream);
      if (temporary) {
        session.trackTemporaryUpload(_joinRemotePath(directoryPath, name));
      }
      _invalidateDirectory(session, directoryPath);
      final refreshed = await session.listDirectory(directoryPath);
      sessionDirectories[workspaceKey] = refreshed;
      _cacheDirectory(session, refreshed);
      if (activeSession?.id == session.id &&
          terminalFrameKey(activeSession!) == workspaceKey) {
        activeDirectory = refreshed;
      }
    });
  }

  Future<void> refreshActiveDirectory() async {
    final directory = activeDirectory;
    if (directory == null) {
      return;
    }
    await loadDirectory(directory.currentPath, force: true);
  }

  bool get canGoBackDirectory {
    final session = activeSession;
    return session != null &&
        (_directoryBackStacks[terminalFrameKey(session)]?.isNotEmpty ?? false);
  }

  Future<void> goBackDirectory() async {
    final session = activeSession;
    if (session == null) {
      return;
    }
    final stack = _directoryBackStacks[terminalFrameKey(session)];
    if (stack == null || stack.isEmpty) {
      return;
    }
    final previousPath = stack.removeLast();
    await loadDirectory(previousPath, addToHistory: false);
  }

  Future<void> pingLiveSessions() async {
    final uniqueSessions = <Object, LiveSshSession>{};
    for (final session in liveSessions) {
      uniqueSessions.putIfAbsent(session.client, () => session);
    }
    await Future.wait(
      uniqueSessions.values
          .where((session) => !session.isClosed)
          .map((session) => session.ping().catchError((Object _) {})),
    );
  }

  void _scheduleReconnectRetry() {
    _reconnectRetryTimer?.cancel();
    _reconnectRetryTimer = null;
    if (currentUser == null || liveSessions.isEmpty) {
      return;
    }
    final closedFingerprints = {
      for (final session in liveSessions)
        if (session.isClosed) session.connection.fingerprint,
    };
    final delay = reconnectPolicy.delayUntilNextAttempt(closedFingerprints);
    if (delay == null) {
      return;
    }
    _reconnectRetryTimer = Timer(delay, () {
      _reconnectRetryTimer = null;
      unawaited(reconnectClosedSessions());
    });
  }

  String _directoryCacheKey(LiveSshSession session, String path) {
    return '${terminalFrameKey(session)}:$path';
  }

  RemoteDirectory? _cachedDirectory(LiveSshSession session, String path) {
    final cached = _directoryCache[_directoryCacheKey(session, path)];
    if (cached == null) {
      return null;
    }
    final age = DateTime.now().difference(cached.fetchedAt);
    return age <= _directoryCacheTtl ? cached.directory : null;
  }

  void _cacheDirectory(LiveSshSession session, RemoteDirectory directory) {
    _directoryCache[_directoryCacheKey(session, directory.currentPath)] =
        _CachedDirectory(directory, DateTime.now());
  }

  void _recordDirectoryHistory(
    LiveSshSession session,
    String? fromPath,
    String toPath, {
    required bool addToHistory,
  }) {
    if (!addToHistory || fromPath == null || fromPath == toPath) {
      return;
    }
    final stack =
        _directoryBackStacks.putIfAbsent(terminalFrameKey(session), () => []);
    if (stack.isEmpty || stack.last != fromPath) {
      stack.add(fromPath);
    }
    if (stack.length > 80) {
      stack.removeRange(0, stack.length - 80);
    }
  }

  void _invalidateDirectory(LiveSshSession session, String path) {
    _directoryCache.remove(_directoryCacheKey(session, path));
  }

  bool _hasOtherSessionsOnClient(LiveSshSession session) {
    return liveSessions
        .any((item) => item.id != session.id && item.client == session.client);
  }

  bool _hasOtherSessionsForConnection(SavedConnection connection) {
    return liveSessions.any(
      (session) => session.connection.fingerprint == connection.fingerprint,
    );
  }

  Set<String> _reservedTmuxNamesForClient(LiveSshSession session) {
    return {
      for (final liveSession in liveSessions)
        if (liveSession.client == session.client) ...[
          if (liveSession.selectedTmuxSessionName?.trim().isNotEmpty == true)
            liveSession.selectedTmuxSessionName!.trim(),
          ...liveSession.tmuxSessions.map((tmuxSession) => tmuxSession.name),
        ],
    };
  }

  Future<void> _startTerminalSessionFrom(
    LiveSshSession source, {
    required String path,
    required int initialPaneIndex,
    required bool selectNewTmux,
  }) async {
    final targetPath = path.trim().isEmpty ? source.currentPath : path.trim();
    if (source.tmuxAvailable) {
      _syncTmuxSessionsForClient(source, await source.listTmuxSessions());
    }
    final reservedNames = _reservedTmuxNamesForClient(source);
    final session = source.createTerminalSession(initialPath: targetPath);
    if (selectNewTmux && session.tmuxAvailable) {
      session.selectNewTmuxSession(
        reservedNames: reservedNames,
        basePath: targetPath,
      );
    }
    final sourceDirectory = sessionDirectories[terminalFrameKey(source)];
    final directory = sourceDirectory?.currentPath == targetPath
        ? sourceDirectory!
        : await session.listDirectory(targetPath);
    liveSessions.add(session);
    if (selectNewTmux && session.tmuxAvailable) {
      _appendSelectedTmuxSessionForClient(session);
    }
    sessionDirectories[terminalFrameKey(session)] = directory;
    _cacheDirectory(session, directory);
    sessionPaneIndexes[terminalFrameKey(session)] = initialPaneIndex;
    activeSession = session;
    activeDirectory = directory;
    _ensureTmuxAttentionObserver(session);
    unawaited(_applyPendingTerminalNotificationTarget());
  }

  void _syncTmuxSessionsForClient(
    LiveSshSession source,
    List<RemoteTmuxSession> sessions,
  ) {
    var nextSessions = List<RemoteTmuxSession>.from(sessions);
    for (final liveSession in liveSessions) {
      if (liveSession.client == source.client) {
        nextSessions = _appendSelectedTmuxSession(nextSessions, liveSession);
      }
    }
    nextSessions = _appendSelectedTmuxSession(nextSessions, source);
    for (final liveSession in liveSessions) {
      if (liveSession.client == source.client) {
        liveSession.tmuxSessions = List<RemoteTmuxSession>.from(nextSessions);
      }
    }
    source.tmuxSessions = List<RemoteTmuxSession>.from(nextSessions);
    _ensureTmuxAttentionObserver(source);
  }

  void _ensureTmuxAttentionObserver(LiveSshSession source) {
    if (!source.tmuxAvailable ||
        _tmuxAttentionSubscriptions.containsKey(source.client)) {
      return;
    }
    final stream = source.startTmuxControlModeObserver();
    if (stream == null) {
      return;
    }
    _tmuxAttentionSubscriptions[source.client] = stream.listen(
      (signal) => _handleTmuxAttentionSignal(source, signal),
      onDone: () => _tmuxAttentionSubscriptions.remove(source.client),
      onError: (_) => _tmuxAttentionSubscriptions.remove(source.client),
    );
  }

  void _handleTmuxAttentionSignal(
    LiveSshSession source,
    TmuxAttentionSignal signal,
  ) {
    if (!liveSessions.any((session) => session.client == source.client)) {
      return;
    }
    if (signal.state != TerminalAttentionState.none &&
        signal.paneId?.trim().isNotEmpty == true) {
      unawaited(_applyTmuxAttentionSignal(source, signal));
    }
    _scheduleTmuxAttentionRefresh(source);
  }

  Future<void> _applyTmuxAttentionSignal(
    LiveSshSession source,
    TmuxAttentionSignal signal,
  ) async {
    final paneId = signal.paneId?.trim();
    if (paneId == null || paneId.isEmpty) {
      return;
    }
    try {
      final tmuxName = await source.tmuxSessionNameForPane(paneId);
      if (tmuxName == null || tmuxName.isEmpty) {
        return;
      }
      final baseSessions = source.tmuxSessions;
      if (!baseSessions.any((session) => session.name == tmuxName)) {
        return;
      }
      final previous = List<RemoteTmuxSession>.from(baseSessions);
      final next = [
        for (final session in baseSessions)
          session.name == tmuxName
              ? _copyTmuxSessionWithAttention(
                  session,
                  _visibleTerminalAttentionState(
                    source: source,
                    tmuxSession: session,
                    state: signal.state,
                  ),
                  attentionPaneId: paneId,
                )
              : session,
      ];
      if (_tmuxSessionListsEqual(previous, next)) {
        return;
      }
      _syncTmuxSessionsForClient(source, next);
      unawaited(_notifyTerminalAttentionTransitions(
        source: source,
        previous: previous,
        current: next,
      ));
      notifyListeners();
    } catch (_) {
      return;
    }
  }

  void _scheduleTmuxAttentionRefresh(LiveSshSession source) {
    _tmuxAttentionRefreshTimers[source.client]?.cancel();
    _tmuxAttentionRefreshTimers[source.client] = Timer(
      const Duration(milliseconds: 250),
      () async {
        _tmuxAttentionRefreshTimers.remove(source.client);
        try {
          final previous = List<RemoteTmuxSession>.from(source.tmuxSessions);
          final sessions = _resolveTmuxAttentionTransitions(
            source: source,
            previous: previous,
            current: await source.listTmuxSessions(),
          );
          if (_tmuxSessionListsEqual(previous, sessions)) {
            _syncTmuxSessionsForClient(source, sessions);
            return;
          }
          _syncTmuxSessionsForClient(source, sessions);
          unawaited(_notifyTerminalAttentionTransitions(
            source: source,
            previous: previous,
            current: sessions,
          ));
          notifyListeners();
        } catch (_) {
          return;
        }
      },
    );
  }

  List<RemoteTmuxSession> _resolveTmuxAttentionTransitions({
    required LiveSshSession source,
    required List<RemoteTmuxSession> previous,
    required List<RemoteTmuxSession> current,
  }) {
    final previousByName = {
      for (final session in previous) session.name: session,
    };
    return [
      for (final session in current)
        _copyTmuxSessionWithAttention(
          session,
          _visibleTerminalAttentionState(
            source: source,
            tmuxSession: session,
            state: terminalAttentionFromFallbackTransition(
              previous: previousByName[session.name]?.attentionState ??
                  TerminalAttentionState.none,
              current: session.attentionState,
            ),
          ),
        ),
    ];
  }

  TerminalAttentionState _visibleTerminalAttentionState({
    required LiveSshSession source,
    required RemoteTmuxSession tmuxSession,
    required TerminalAttentionState state,
  }) {
    if (state == TerminalAttentionState.completed &&
        isInForeground &&
        source.selectedTmuxSessionName == tmuxSession.name) {
      return TerminalAttentionState.none;
    }
    return state;
  }

  Future<void> _notifyTerminalAttentionTransitions({
    required LiveSshSession source,
    required List<RemoteTmuxSession> previous,
    required List<RemoteTmuxSession> current,
  }) async {
    if (!terminalAttentionNotificationsEnabled || isInForeground) {
      return;
    }
    final previousByName = {
      for (final session in previous) session.name: session,
    };
    for (var index = 0; index < current.length; index += 1) {
      final session = current[index];
      final previousState = previousByName[session.name]?.attentionState ??
          TerminalAttentionState.none;
      final nextState = session.attentionState;
      final notificationId = _terminalAttentionNotificationId(
        source.connection.fingerprint,
        session.name,
      );
      if (previousState == nextState ||
          (nextState != TerminalAttentionState.completed &&
              nextState != TerminalAttentionState.actionRequired)) {
        if (previousState != nextState) {
          _invalidateTerminalAttentionNotification(notificationId);
        }
        continue;
      }
      final tabNumber = index + 1;
      final message = _terminalAttentionNotificationTitle(
        tabNumber: tabNumber,
        state: nextState,
      );
      final serial = _nextTerminalAttentionNotificationSerial(notificationId);
      await Future<void>.delayed(_terminalAttentionNotificationSettleDelay);
      if (!_isTerminalAttentionNotificationCurrent(notificationId, serial) ||
          !terminalAttentionNotificationsEnabled ||
          isInForeground ||
          !liveSessions.any((session) => session.client == source.client) ||
          !_tmuxSessionStillHasAttention(
            source: source,
            tmuxSessionName: session.name,
            state: nextState,
          )) {
        continue;
      }
      final tail = terminalAttentionNotificationTailEnabled
          ? await _captureFreshTerminalAttentionTail(
              source: source,
              session: session,
              notificationId: notificationId,
              serial: serial,
              state: nextState,
            )
          : '';
      if (!_isTerminalAttentionNotificationCurrent(notificationId, serial)) {
        continue;
      }
      final trimmedTail = tail.trim();
      final previousBody = _terminalAttentionNotificationBodies[notificationId];
      final body = trimmedTail.isEmpty || trimmedTail == previousBody
          ? message
          : trimmedTail;
      await terminalNotificationService.show(
        notificationId: notificationId,
        title: message,
        body: body,
        connectionFingerprint: source.connection.fingerprint,
        tmuxSessionName: session.name,
      );
      _terminalAttentionNotificationBodies[notificationId] = body;
    }
  }

  Future<String> _captureFreshTerminalAttentionTail({
    required LiveSshSession source,
    required RemoteTmuxSession session,
    required int notificationId,
    required int serial,
    required TerminalAttentionState state,
  }) async {
    final previousBody = _terminalAttentionNotificationBodies[notificationId];
    var tail = await source.captureTmuxSessionTail(
      session.name,
      paneId: session.attentionPaneId,
      lines: _terminalAttentionPreviewLines,
    );
    for (final delay in _terminalAttentionNotificationRetryDelays) {
      if (!_isTerminalAttentionNotificationCurrent(notificationId, serial) ||
          !_tmuxSessionStillHasAttention(
            source: source,
            tmuxSessionName: session.name,
            state: state,
          ) ||
          tail.trim().isEmpty ||
          tail.trim() != previousBody) {
        return tail;
      }
      await Future<void>.delayed(delay);
      if (!_isTerminalAttentionNotificationCurrent(notificationId, serial)) {
        return tail;
      }
      tail = await source.captureTmuxSessionTail(
        session.name,
        paneId: session.attentionPaneId,
        lines: _terminalAttentionPreviewLines,
      );
    }
    return tail;
  }

  int _nextTerminalAttentionNotificationSerial(int notificationId) {
    final serial = _terminalAttentionNotificationSerial + 1;
    _terminalAttentionNotificationSerial = serial;
    _terminalAttentionNotificationSerials[notificationId] = serial;
    return serial;
  }

  void _invalidateTerminalAttentionNotification(int notificationId) {
    final serial = _terminalAttentionNotificationSerial + 1;
    _terminalAttentionNotificationSerial = serial;
    _terminalAttentionNotificationSerials[notificationId] = serial;
  }

  bool _isTerminalAttentionNotificationCurrent(
    int notificationId,
    int serial,
  ) {
    return _terminalAttentionNotificationSerials[notificationId] == serial;
  }

  bool _tmuxSessionStillHasAttention({
    required LiveSshSession source,
    required String tmuxSessionName,
    required TerminalAttentionState state,
  }) {
    for (final session in source.tmuxSessions) {
      if (session.name == tmuxSessionName) {
        return session.attentionState == state;
      }
    }
    return false;
  }

  Future<void> _applyPendingTerminalNotificationTarget() async {
    final target = _pendingTerminalNotificationTarget;
    if (target == null) {
      return;
    }
    await focusTerminalNotificationTarget(target);
  }

  LiveSshSession? _liveSessionForConnectionFingerprint(String fingerprint) {
    final trimmed = fingerprint.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    for (final session in liveSessions) {
      if (session.connection.fingerprint == trimmed) {
        return session;
      }
    }
    return null;
  }

  RemoteTmuxSession? _tmuxSessionByName(
    LiveSshSession session,
    String tmuxSessionName,
  ) {
    final trimmed = tmuxSessionName.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    for (final tmuxSession in session.tmuxSessions) {
      if (tmuxSession.name == trimmed) {
        return tmuxSession;
      }
    }
    return null;
  }

  Future<void> _sendTerminalNotificationAction(
    LiveSshSession session,
    TerminalNotificationLaunchTarget target,
  ) async {
    final action = target.action?.trim();
    if (action == null || action.isEmpty) {
      return;
    }
    try {
      await session.sendTmuxNotificationAction(
        tmuxSessionName: target.tmuxSessionName,
        action: action,
      );
    } catch (_) {
      return;
    }
  }

  String _terminalAttentionNotificationTitle({
    required int tabNumber,
    required TerminalAttentionState state,
  }) {
    final languageCode =
        appLanguageCode == AppSettingsRepository.systemLanguageCode
            ? 'en'
            : appLanguageCode;
    final l10n = SeilLocalizations(Locale(languageCode));
    return switch (state) {
      TerminalAttentionState.actionRequired =>
        l10n.terminalActionRequiredNotification(tabNumber),
      TerminalAttentionState.completed =>
        l10n.terminalWorkCompleteNotification(tabNumber),
      TerminalAttentionState.running ||
      TerminalAttentionState.none =>
        l10n.terminalStateChangedNotification(tabNumber),
    };
  }

  int _terminalAttentionNotificationId(
    String connectionFingerprint,
    String tmuxSessionName,
  ) {
    return Object.hash(connectionFingerprint, tmuxSessionName) & 0x7fffffff;
  }

  RemoteTmuxSession _copyTmuxSessionWithAttention(
    RemoteTmuxSession session,
    TerminalAttentionState attentionState, {
    String? attentionPaneId,
  }) {
    final nextAttentionPaneId = attentionState == TerminalAttentionState.none
        ? null
        : attentionPaneId ?? session.attentionPaneId;
    if (session.attentionState == attentionState &&
        session.attentionPaneId == nextAttentionPaneId) {
      return session;
    }
    return RemoteTmuxSession(
      name: session.name,
      windows: session.windows,
      attachedClients: session.attachedClients,
      createdAt: session.createdAt,
      lastActivityAt: session.lastActivityAt,
      currentPath: session.currentPath,
      attentionState: attentionState,
      attentionPaneId: nextAttentionPaneId,
      terminalTitle: session.terminalTitle,
      windowFlags: session.windowFlags,
    );
  }

  void _appendSelectedTmuxSessionForClient(LiveSshSession source) {
    final entry = _selectedTmuxSessionEntry(source);
    if (entry == null) {
      return;
    }
    for (final liveSession in liveSessions) {
      if (liveSession.client == source.client) {
        liveSession.tmuxSessions = _appendTmuxSession(
          liveSession.tmuxSessions,
          entry,
        );
      }
    }
    source.tmuxSessions = _appendTmuxSession(source.tmuxSessions, entry);
  }

  RemoteTmuxSession? _tmuxSessionBeforeDeleted({
    required List<RemoteTmuxSession> previousSessions,
    required List<RemoteTmuxSession> sessions,
    required String deletedName,
  }) {
    if (sessions.isEmpty) {
      return null;
    }
    final deletedIndex = previousSessions.indexWhere(
      (session) => session.name == deletedName,
    );
    final sessionsByName = {
      for (final session in sessions) session.name: session,
    };
    if (deletedIndex > 0) {
      for (var index = deletedIndex - 1; index >= 0; index -= 1) {
        final fallback = sessionsByName[previousSessions[index].name];
        if (fallback != null) {
          return fallback;
        }
      }
    }
    if (deletedIndex >= 0) {
      for (var index = deletedIndex + 1;
          index < previousSessions.length;
          index += 1) {
        final fallback = sessionsByName[previousSessions[index].name];
        if (fallback != null) {
          return fallback;
        }
      }
    }
    return sessions.first;
  }

  void _selectTmuxSession(
    LiveSshSession session,
    RemoteTmuxSession tmuxSession,
  ) {
    final previousPaneIndex = sessionPaneIndexes[terminalFrameKey(session)] ??
        (activeSession?.id == session.id ? activePaneIndex : 0);
    session.selectTmuxSession(tmuxSession);
    if (tmuxSession.currentPath?.trim().isNotEmpty == true) {
      session.currentPath = tmuxSession.currentPath!.trim();
    }
    final workspaceKey = terminalFrameKey(session);
    sessionPaneIndexes.putIfAbsent(workspaceKey, () => previousPaneIndex);
    if (activeSession?.id == session.id) {
      activeDirectory = sessionDirectories[workspaceKey];
    }
  }

  List<RemoteTmuxSession> _appendSelectedTmuxSession(
    List<RemoteTmuxSession> sessions,
    LiveSshSession source,
  ) {
    final entry = _selectedTmuxSessionEntry(source);
    if (entry == null) {
      return List<RemoteTmuxSession>.from(sessions);
    }
    return _appendTmuxSession(sessions, entry);
  }

  RemoteTmuxSession? _selectedTmuxSessionEntry(LiveSshSession source) {
    final selectedName = source.selectedTmuxSessionName?.trim();
    if (selectedName == null || selectedName.isEmpty) {
      return null;
    }
    return RemoteTmuxSession(
      name: selectedName,
      windows: 1,
      attachedClients: 0,
      createdAt: null,
      lastActivityAt: null,
      currentPath: source.currentPath,
    );
  }

  List<RemoteTmuxSession> _appendTmuxSession(
    List<RemoteTmuxSession> sessions,
    RemoteTmuxSession entry,
  ) {
    if (sessions.any((session) => session.name == entry.name)) {
      return List<RemoteTmuxSession>.from(sessions);
    }
    return [...sessions, entry];
  }

  bool _tmuxSessionListsEqual(
    List<RemoteTmuxSession> left,
    List<RemoteTmuxSession> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      final a = left[index];
      final b = right[index];
      if (a.name != b.name ||
          a.windows != b.windows ||
          a.attachedClients != b.attachedClients ||
          a.createdAt != b.createdAt ||
          a.lastActivityAt != b.lastActivityAt ||
          a.currentPath != b.currentPath ||
          a.attentionState != b.attentionState ||
          a.attentionPaneId != b.attentionPaneId ||
          a.terminalTitle != b.terminalTitle ||
          a.windowFlags != b.windowFlags) {
        return false;
      }
    }
    return true;
  }

  Future<T> _serializeSessionStart<T>(Future<T> Function() action) {
    final previous = _sessionStartTail.catchError((Object _) {});
    final completer = Completer<void>();
    _sessionStartTail = completer.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
  }

  Future<LiveSshSession> _reconnectRootSession(
    LiveSshSession oldSession,
  ) async {
    final secret = await connectionRepository.resolveSecret(
      oldSession.connection,
      _reconnectSecrets[oldSession.connection.fingerprint],
    );
    if (oldSession.connection.authMode != AuthMode.agent &&
        (secret == null || secret.isEmpty)) {
      throw StateError(SeilErrorCodes.missingSshSecret);
    }

    final session = await sshSessionService.connect(
      connection: oldSession.connection,
      secret: secret ?? '',
    );
    if (secret != null && secret.isNotEmpty) {
      _reconnectSecrets[oldSession.connection.fingerprint] = secret;
    }
    return session;
  }

  Future<RemoteDirectory> _loadReconnectDirectory(
    LiveSshSession session,
    String path,
  ) async {
    try {
      return await session.listDirectory(path);
    } catch (_) {
      return session.listDirectory(session.homePath);
    }
  }

  String _sessionDirectoryPath(LiveSshSession session) {
    return sessionDirectories[terminalFrameKey(session)]?.currentPath ??
        session.currentPath;
  }

  void _restoreSessionSelection(
    LiveSshSession oldSession,
    LiveSshSession replacement,
  ) {
    replacement.selectedTmuxSessionName = oldSession.selectedTmuxSessionName;
    replacement.activeTmuxPaneId = null;
    replacement.tmuxSelectionReady = oldSession.tmuxSelectionReady;
    replacement.adoptTemporaryUploadsFrom(oldSession);
  }

  LiveSshSession? _findOpenSessionForConnection(SavedConnection connection) {
    for (final session in liveSessions) {
      if (!session.isClosed &&
          session.connection.fingerprint == connection.fingerprint) {
        return session;
      }
    }
    return null;
  }

  Future<void> _closeAllSessions() async {
    _stopBackgroundRetention();
    _reconnectRetryTimer?.cancel();
    _reconnectRetryTimer = null;
    _cancelTmuxAttentionObservers();
    final sessions = List<LiveSshSession>.from(liveSessions);
    liveSessions.clear();
    sessionDirectories.clear();
    sessionPaneIndexes.clear();
    _directoryBackStacks.clear();
    _sessionNames.clear();
    _terminalFrames.clear();
    _directoryCache.clear();
    _reconnectSecrets.clear();
    reconnectPolicy.clearAll();
    final closedClients = <Object>[];
    for (final session in sessions) {
      await session.cleanupTemporaryUploads();
      final closeClient = !closedClients.contains(session.client);
      session.close(closeClient: closeClient);
      if (closeClient) {
        closedClients.add(session.client);
      }
    }
  }

  void _cancelTmuxAttentionObserver(Object client) {
    _tmuxAttentionRefreshTimers.remove(client)?.cancel();
    unawaited(_tmuxAttentionSubscriptions.remove(client)?.cancel());
  }

  void _cancelTmuxAttentionObservers() {
    for (final timer in _tmuxAttentionRefreshTimers.values) {
      timer.cancel();
    }
    _tmuxAttentionRefreshTimers.clear();
    for (final subscription in _tmuxAttentionSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _tmuxAttentionSubscriptions.clear();
  }

  Future<T?> _run<T>(
    Future<T> Function() action, {
    bool showErrorPopup = true,
  }) async {
    final wasIdle = _busyDepth == 0;
    _busyDepth += 1;
    if (wasIdle) {
      busy = true;
    }
    errorMessage = null;
    errorShowsPopup = true;
    if (wasIdle) {
      notifyListeners();
    }
    try {
      return await action();
    } catch (error) {
      _setError(seilLocalizedErrorMessage(appLanguageCode, error),
          showPopup: showErrorPopup);
      return null;
    } finally {
      _busyDepth -= 1;
      if (_busyDepth < 0) {
        _busyDepth = 0;
      }
      if (_busyDepth == 0) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void _setError(String message, {bool showPopup = true}) {
    errorMessage = message;
    errorShowsPopup = showPopup;
    errorSerial += 1;
  }

  String _tmuxTagKey(SavedConnection connection, String tmuxName) {
    return '${connection.fingerprint}:$tmuxName';
  }
}

String _joinRemotePath(String directoryPath, String name) {
  final base = directoryPath.trim().isEmpty ? '/' : directoryPath.trim();
  return base == '/' ? '/$name' : '$base/$name';
}

class _CachedDirectory {
  const _CachedDirectory(this.directory, this.fetchedAt);

  final RemoteDirectory directory;
  final DateTime fetchedAt;
}

bool _isReconnectUserActionRequired(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains(SeilErrorCodes.missingSshSecret.toLowerCase()) ||
      message.contains('auth fail') ||
      message.contains('authentication failed') ||
      message.contains('permission denied') ||
      message.contains('publickey');
}
