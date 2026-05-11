import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../shared/models.dart';
import '../files/file_meta.dart';

const maxPreviewBytes = 64 * 1024;
const maxEditBytes = 256 * 1024;
const _tmuxDelimiter = '|||';
const _tmuxCaptureMarker = '__SEIL_TMUX_CAPTURE_META__';
const _tmuxPanePathMarker = '__SEIL_TMUX_PANE_PATHS__';
const _sshClosedMessage = '재연결 중..';
const _sshConnectTimeout = Duration(seconds: 10);

abstract class SshSessionService {
  Future<LiveSshSession> connect({
    required SavedConnection connection,
    required String secret,
  });
}

class DartSshSessionService implements SshSessionService {
  @override
  Future<LiveSshSession> connect({
    required SavedConnection connection,
    required String secret,
  }) async {
    if (connection.authMode == AuthMode.agent) {
      throw StateError('모바일 앱에서는 SSH Agent 인증을 지원하지 않습니다.');
    }

    final socket = await SSHSocket.connect(
      connection.host,
      connection.port,
      timeout: _sshConnectTimeout,
    );
    final client = SSHClient(
      socket,
      username: connection.username,
      keepAliveInterval: const Duration(seconds: 10),
      onPasswordRequest:
          connection.authMode == AuthMode.password ? () => secret : null,
      identities: connection.authMode == AuthMode.privateKey
          ? SSHKeyPair.fromPem(secret)
          : null,
    );
    final session = LiveSshSession._(
      client: client,
      connection: connection,
      commandQueue: _SshCommandQueue(),
    );
    try {
      await session.initialize().timeout(_sshConnectTimeout);
    } catch (_) {
      session.close();
      rethrow;
    }
    return session;
  }
}

class LiveSshSession {
  LiveSshSession._({
    required this.client,
    required this.connection,
    required _SshCommandQueue commandQueue,
  })  : id = const Uuid().v4(),
        _commandQueue = commandQueue;

  final String id;
  final SSHClient client;
  final SavedConnection connection;
  final _SshCommandQueue _commandQueue;
  late final String hostName;
  late final String homePath;
  late final bool tmuxAvailable;
  late final String shellFallbackPath;
  String currentPath = '/';
  List<RemoteTmuxSession> tmuxSessions = [];
  String? selectedTmuxSessionName;
  String? activeTmuxPaneId;
  bool tmuxSelectionReady = false;
  bool _tmuxPrepared = false;
  SftpClient? _sftp;
  _PersistentShell? _persistentShell;
  final Map<String, Set<String>> _temporaryUploadPathsByTmux = {};

  String get displayName => connection.displayName;

  String get username => connection.username;

  bool get isClosed => client.isClosed;

  bool get terminalClosed => isClosed;

  RemoteTmuxSession? get selectedTmuxSession {
    final name = selectedTmuxSessionName;
    if (name == null) {
      return null;
    }
    for (final session in tmuxSessions) {
      if (session.name == name) {
        return session;
      }
    }
    return null;
  }

  RemoteSession get snapshot {
    return RemoteSession(
      id: id,
      connection: connection,
      hostName: hostName,
      homePath: homePath,
      currentPath: currentPath,
      createdAt: DateTime.now().toUtc(),
    );
  }

  Future<void> initialize() async {
    final result = await runCommand(
      [
        'printf "__SEIL_HOST__%s\\n" "\$(hostname 2>/dev/null || uname -n)"',
        'printf "__SEIL_HOME__%s\\n" "\$HOME"',
        'if command -v tmux >/dev/null 2>&1; then printf "__SEIL_TMUX__1\\n"; else printf "__SEIL_TMUX__0\\n"; fi',
        'printf "__SEIL_SH__%s\\n" "\$(command -v sh 2>/dev/null || printf /bin/sh)"',
      ].join('; '),
    );
    hostName = _extractMarker(result, '__SEIL_HOST__') ?? connection.host;
    homePath = _extractMarker(result, '__SEIL_HOME__') ?? '.';
    tmuxAvailable = _extractMarker(result, '__SEIL_TMUX__') == '1';
    shellFallbackPath = _extractMarker(result, '__SEIL_SH__') ?? '/bin/sh';
    currentPath = homePath;
    tmuxSessions = const [];
    tmuxSelectionReady = !tmuxAvailable;
  }

  Future<String> runCommand(String command) async {
    return _commandQueue.run(() async {
      return _executeCommand(command);
    });
  }

  Future<String> runPersistentCommand(
    String command, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    return _commandQueue.run(() async {
      if (client.isClosed) {
        throw StateError(_sshClosedMessage);
      }
      try {
        final shell = await _ensurePersistentShell();
        return await shell.exec(command, timeout: timeout);
      } catch (error) {
        await _disposePersistentShell();
        if (error is SSHStateError &&
            (client.isClosed || _isClosedSshState(error))) {
          throw StateError(_sshClosedMessage);
        }
        return _executeCommand(command);
      }
    });
  }

  Future<String> _executeCommand(String command) async {
    if (client.isClosed) {
      throw StateError(_sshClosedMessage);
    }
    try {
      final session = await client.execute(command);
      final chunks = <int>[];
      await for (final chunk in session.stdout) {
        chunks.addAll(chunk);
      }
      final stderr = <int>[];
      await for (final chunk in session.stderr) {
        stderr.addAll(chunk);
      }
      await session.done;
      if (stderr.isNotEmpty) {
        final message = utf8.decode(stderr).trim();
        if (message.isNotEmpty) {
          throw StateError(message);
        }
      }
      return utf8.decode(chunks, allowMalformed: true);
    } on SSHStateError catch (error) {
      if (client.isClosed || _isClosedSshState(error)) {
        throw StateError(_sshClosedMessage);
      }
      rethrow;
    }
  }

  Future<_PersistentShell> _ensurePersistentShell() async {
    final existing = _persistentShell;
    if (existing != null && existing.isStarted) {
      return existing;
    }
    final shell = _PersistentShell(client);
    _persistentShell = shell;
    await shell.start();
    return shell;
  }

  Future<void> _disposePersistentShell() async {
    final shell = _persistentShell;
    _persistentShell = null;
    await shell?.dispose();
  }

  String get tmuxTargetName =>
      selectedTmuxSessionName ?? _nextTmuxSessionName();

  String get nextTmuxSessionName => _nextTmuxSessionName();

  String nextAvailableTmuxSessionName({
    Set<String> reservedNames = const {},
    String? basePath,
  }) {
    return _nextTmuxSessionName(
      reservedNames: reservedNames,
      basePath: basePath,
    );
  }

  String get _tmuxTargetPane => activeTmuxPaneId ?? '$tmuxTargetName:';

  Future<void> prepareTmuxSession() async {
    if (!tmuxAvailable) {
      return;
    }
    if (_tmuxPrepared && activeTmuxPaneId != null) {
      return;
    }

    final targetName = tmuxTargetName;
    final target = _quoteShellToken(targetName);
    final exactTarget = _quoteShellToken('=$targetName');
    final output = await runCommand(
      [
        'tmux set-option -g default-terminal tmux-256color 2>/dev/null || true',
        'tmux set-option -g history-limit ${connection.tmuxHistoryLimit} 2>/dev/null || true',
        'tmux show-options -gqv terminal-features 2>/dev/null | grep -q "RGB" || tmux set-option -ag terminal-features ",*:RGB" 2>/dev/null || true',
        'tmux show-options -gqv terminal-overrides 2>/dev/null | grep -q "Tc" || tmux set-option -ag terminal-overrides ",*:Tc" 2>/dev/null || true',
        'tmux set-environment -g COLORTERM truecolor 2>/dev/null || true',
        'tmux set-environment -g TERM_PROGRAM Seil 2>/dev/null || true',
        'tmux has-session -t $exactTarget 2>/dev/null || tmux new-session -d -s $target -c ${_quoteShellToken(currentPath)} 2>/dev/null || true',
        'tmux set-option -t $exactTarget status off 2>/dev/null || true',
        'tmux set-option -t $exactTarget mouse on 2>/dev/null || true',
        'tmux set-option -t $exactTarget default-terminal tmux-256color 2>/dev/null || true',
        'tmux set-environment -t $exactTarget COLORTERM truecolor 2>/dev/null || true',
        'tmux set-environment -t $exactTarget TERM_PROGRAM Seil 2>/dev/null || true',
        'tmux set-window-option -t $exactTarget pane-border-status off 2>/dev/null || true',
        'tmux set-option -s escape-time 10 2>/dev/null || true',
        'tmux set-option -s focus-events on 2>/dev/null || true',
        'tmux display-message -p -t ${_quoteShellToken('$targetName:')} "#{pane_id}$_tmuxDelimiter#{cursor_x}$_tmuxDelimiter#{cursor_y}$_tmuxDelimiter#{pane_width}$_tmuxDelimiter#{pane_height}$_tmuxDelimiter#{pane_mode}$_tmuxDelimiter#{history_size}" 2>/dev/null || true',
      ].join('; '),
    );
    final frame = _parseCaptureFrame('$_tmuxCaptureMarker$output');
    activeTmuxPaneId = frame.paneId ?? activeTmuxPaneId;
    _tmuxPrepared = true;
  }

  Future<TmuxCaptureFrame> captureActiveTmuxPane(
      {int scrollbackLines = 1000}) async {
    if (!tmuxAvailable) {
      return const TmuxCaptureFrame(
        content: '[seil] tmux is not available on this server.',
        paneId: null,
        cursorX: 0,
        cursorY: 0,
        paneWidth: 80,
        paneHeight: 24,
        paneMode: '',
        currentPath: null,
        historySize: null,
      );
    }

    await prepareTmuxSession();
    final target = _quoteShellToken(_tmuxTargetPane);
    final startLine = -scrollbackLines.abs();
    final output = await runPersistentCommand(
      [
        'tmux capture-pane -t $target -p -e -S $startLine 2>/dev/null || true',
        'printf "\\n$_tmuxCaptureMarker"',
        'tmux display-message -p -t $target "#{pane_id}$_tmuxDelimiter#{cursor_x}$_tmuxDelimiter#{cursor_y}$_tmuxDelimiter#{pane_width}$_tmuxDelimiter#{pane_height}$_tmuxDelimiter#{pane_mode}$_tmuxDelimiter#{history_size}$_tmuxDelimiter#{pane_current_path}" 2>/dev/null || true',
      ].join('; '),
    );
    return _parseCaptureFrame(output);
  }

  Future<void> refreshActiveTmuxPane() async {
    if (!tmuxAvailable) {
      activeTmuxPaneId = null;
      return;
    }
    final output = await runCommand(
      'tmux display-message -p -t ${_quoteShellToken('$tmuxTargetName:')} "#{pane_id}$_tmuxDelimiter#{cursor_x}$_tmuxDelimiter#{cursor_y}$_tmuxDelimiter#{pane_width}$_tmuxDelimiter#{pane_height}$_tmuxDelimiter#{pane_mode}$_tmuxDelimiter#{history_size}" 2>/dev/null || true',
    );
    final frame = _parseCaptureFrame('$_tmuxCaptureMarker$output');
    activeTmuxPaneId = frame.paneId ?? activeTmuxPaneId;
  }

  Future<void> sendTmuxLiteral(String data) async {
    if (!tmuxAvailable || data.isEmpty) {
      return;
    }
    await prepareTmuxSession();
    final normalized = data.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final commands = <String>[];
    for (var i = 0; i < lines.length; i += 1) {
      final line = lines[i];
      if (line.isNotEmpty) {
        commands.add(
          'send-keys -t ${_quoteShellToken(_tmuxTargetPane)} -l ${_quoteShellToken(line)}',
        );
      }
      if (i < lines.length - 1) {
        commands.add(
          'send-keys -t ${_quoteShellToken(_tmuxTargetPane)} Enter',
        );
      }
    }
    if (commands.isNotEmpty) {
      await _runTmuxCommand(commands.join(' \\; '), refreshPane: false);
    }
  }

  Future<void> sendTmuxKey(String key) async {
    if (!tmuxAvailable || key.trim().isEmpty) {
      return;
    }
    await prepareTmuxSession();
    await _runTmuxCommand(
      'send-keys -t ${_quoteShellToken(_tmuxTargetPane)} ${_quoteShellToken(key)}',
      refreshPane: false,
    );
  }

  Future<void> changeTmuxDirectory(String path) async {
    if (!tmuxAvailable || path.trim().isEmpty) {
      return;
    }
    currentPath = path.trim();
    await sendTmuxLiteral('cd -- ${_quoteShellToken(currentPath)}');
    await sendTmuxKey('Enter');
  }

  Future<void> tmuxScrollUp() {
    return _runTmuxCommand(
      'copy-mode -u -t ${_quoteShellToken(_tmuxTargetPane)} \\; send-keys -X -t ${_quoteShellToken(_tmuxTargetPane)} page-up',
    );
  }

  Future<void> tmuxScrollDown() {
    return _runTmuxCommand(
      'copy-mode -u -t ${_quoteShellToken(_tmuxTargetPane)} \\; send-keys -X -t ${_quoteShellToken(_tmuxTargetPane)} page-down',
    );
  }

  Future<void> tmuxSplitHorizontal() {
    return _runTmuxCommand(
        'split-window -v -t ${_quoteShellToken(_tmuxTargetPane)}');
  }

  Future<void> tmuxSplitVertical() {
    return _runTmuxCommand(
        'split-window -h -t ${_quoteShellToken(_tmuxTargetPane)}');
  }

  Future<void> tmuxNewWindow() {
    return _runTmuxCommand('new-window -t ${_quoteShellToken(tmuxTargetName)}');
  }

  Future<void> tmuxNextWindow() {
    return _runTmuxCommand(
        'next-window -t ${_quoteShellToken(tmuxTargetName)}');
  }

  Future<void> tmuxPreviousWindow() {
    return _runTmuxCommand(
        'previous-window -t ${_quoteShellToken(tmuxTargetName)}');
  }

  Future<void> tmuxPasteBuffer() {
    return _runTmuxCommand(
        'paste-buffer -t ${_quoteShellToken(tmuxTargetName)}');
  }

  Future<void> tmuxDetachClients() {
    return _runTmuxCommand(
        'detach-client -s ${_quoteShellToken(tmuxTargetName)}');
  }

  Future<List<RemoteTmuxSession>> killTmuxSession(String name) async {
    if (!tmuxAvailable || name.trim().isEmpty) {
      return tmuxSessions;
    }
    await runCommand(
      'tmux kill-session -t ${_quoteShellToken('=$name')} 2>/dev/null || true',
    );
    final sessions = await listTmuxSessions();
    if (selectedTmuxSessionName == name) {
      resetTmuxSelection(sessions: sessions);
    }
    return sessions;
  }

  void resetTmuxSelection({List<RemoteTmuxSession>? sessions}) {
    if (sessions != null) {
      tmuxSessions = List<RemoteTmuxSession>.from(sessions);
    }
    selectedTmuxSessionName = null;
    activeTmuxPaneId = null;
    _tmuxPrepared = false;
    tmuxSelectionReady = !tmuxAvailable;
  }

  Future<void> tmuxCommandPrompt() {
    return _runTmuxCommand(
        'command-prompt -t ${_quoteShellToken(tmuxTargetName)}');
  }

  Future<void> _runTmuxCommand(
    String arguments, {
    bool refreshPane = true,
  }) async {
    if (!tmuxAvailable) {
      return;
    }
    await runCommand('tmux $arguments');
    if (refreshPane) {
      await refreshActiveTmuxPane();
    }
  }

  Future<List<RemoteTmuxSession>> listTmuxSessions() async {
    if (!tmuxAvailable) {
      return const [];
    }

    final output = await runCommand(
      [
        'tmux list-sessions -F "S$_tmuxDelimiter#{session_name}$_tmuxDelimiter#{session_windows}$_tmuxDelimiter#{session_attached}$_tmuxDelimiter#{session_created}$_tmuxDelimiter#{session_activity}" 2>/dev/null || true',
        'printf "\\n$_tmuxPanePathMarker\\n"',
        'tmux list-panes -a -F "P$_tmuxDelimiter#{session_name}$_tmuxDelimiter#{pane_active}$_tmuxDelimiter#{pane_current_path}" 2>/dev/null || true',
      ].join('; '),
    );
    final panePaths = <String, String>{};
    final sessionLines = <String>[];
    var parsingPanePaths = false;
    for (final line in const LineSplitter().convert(output)) {
      if (line == _tmuxPanePathMarker) {
        parsingPanePaths = true;
        continue;
      }
      if (parsingPanePaths) {
        final parts = line.split(_tmuxDelimiter);
        if (parts.length < 4 || parts.first != 'P') {
          continue;
        }
        final sessionName = parts[1];
        final panePath = parts.sublist(3).join(_tmuxDelimiter).trim();
        if (panePath.isEmpty) {
          continue;
        }
        if (parts[2] == '1' || !panePaths.containsKey(sessionName)) {
          panePaths[sessionName] = panePath;
        }
      } else {
        sessionLines.add(line);
      }
    }

    final sessions = <RemoteTmuxSession>[];
    for (final line in sessionLines) {
      final parts = line.split(_tmuxDelimiter);
      if (parts.length < 6 || parts.first != 'S' || parts[1].trim().isEmpty) {
        continue;
      }
      final name = parts[1];
      sessions.add(
        RemoteTmuxSession(
          name: name,
          windows: int.tryParse(parts[2]) ?? 0,
          attachedClients: int.tryParse(parts[3]) ?? 0,
          createdAt: _unixSecondsStringToDate(parts[4]),
          lastActivityAt: _unixSecondsStringToDate(parts[5]),
          currentPath: panePaths[name],
        ),
      );
    }
    final selectedName = selectedTmuxSessionName;
    if (selectedName != null &&
        selectedName.isNotEmpty &&
        !sessions.any((session) => session.name == selectedName)) {
      sessions.add(
        RemoteTmuxSession(
          name: selectedName,
          windows: 1,
          attachedClients: 0,
          createdAt: DateTime.now().toUtc(),
          lastActivityAt: DateTime.now().toUtc(),
          currentPath: currentPath,
        ),
      );
    }
    sessions.sort((left, right) {
      final leftActivity =
          left.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightActivity =
          right.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightActivity.compareTo(leftActivity);
    });
    tmuxSessions = sessions;
    return sessions;
  }

  void selectTmuxSession(RemoteTmuxSession? session) {
    selectedTmuxSessionName = session?.name;
    activeTmuxPaneId = null;
    _tmuxPrepared = false;
    tmuxSelectionReady = true;
  }

  void selectNewTmuxSession({
    Set<String> reservedNames = const {},
    String? basePath,
  }) {
    final startPath = basePath?.trim();
    if (startPath != null && startPath.isNotEmpty) {
      currentPath = startPath;
    }
    final name = _nextTmuxSessionName(
      reservedNames: reservedNames,
      basePath: startPath,
    );
    selectedTmuxSessionName = name;
    activeTmuxPaneId = null;
    _tmuxPrepared = false;
    tmuxSelectionReady = true;
  }

  String _nextTmuxSessionName({
    Set<String> reservedNames = const {},
    String? basePath,
  }) {
    final names = {
      ...tmuxSessions.map((session) => session.name),
      ...reservedNames,
    };
    while (true) {
      final suffix = const Uuid().v4().replaceAll('-', '').substring(0, 12);
      final name = 'seil-$suffix';
      if (!names.contains(name)) {
        return name;
      }
    }
  }

  LiveSshSession createTerminalSession({String? initialPath}) {
    final session = LiveSshSession._(
      client: client,
      connection: connection,
      commandQueue: _commandQueue,
    );
    session.hostName = hostName;
    session.homePath = homePath;
    session.tmuxAvailable = tmuxAvailable;
    session.shellFallbackPath = shellFallbackPath;
    session.currentPath = initialPath?.trim().isNotEmpty == true
        ? initialPath!.trim()
        : currentPath;
    session.tmuxSessions = List<RemoteTmuxSession>.from(tmuxSessions);
    session.selectedTmuxSessionName = null;
    session.activeTmuxPaneId = null;
    session._tmuxPrepared = false;
    session.tmuxSelectionReady = !tmuxAvailable;
    return session;
  }

  void trackTemporaryUpload(String remotePath) {
    final trimmed = remotePath.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final owner = selectedTmuxSessionName ?? '';
    _temporaryUploadPathsByTmux.putIfAbsent(owner, () => <String>{}).add(
          trimmed,
        );
  }

  void adoptTemporaryUploadsFrom(LiveSshSession other) {
    for (final entry in other._temporaryUploadPathsByTmux.entries) {
      _temporaryUploadPathsByTmux
          .putIfAbsent(entry.key, () => <String>{})
          .addAll(entry.value);
    }
  }

  Future<void> cleanupTemporaryUploads({String? tmuxSessionName}) async {
    final keys = tmuxSessionName == null
        ? _temporaryUploadPathsByTmux.keys.toList()
        : [tmuxSessionName];
    for (final key in keys) {
      final paths = _temporaryUploadPathsByTmux.remove(key);
      if (paths == null || paths.isEmpty) {
        continue;
      }
      for (final path in paths) {
        try {
          await deleteRemoteFile(path);
        } catch (_) {
          // Best-effort cleanup: do not block session shutdown on stale files.
        }
      }
    }
  }

  Future<SftpClient> sftp() async {
    return _sftp ??= await client.sftp();
  }

  Future<void> ping() {
    return client.ping();
  }

  Future<RemoteDirectory> listDirectory(String remotePath) async {
    final sftpClient = await sftp();
    final normalized = _normalizeRemoteDirectory(remotePath);
    final stats = await sftpClient.stat(normalized);
    if (!stats.isDirectory) {
      throw StateError('디렉토리 경로가 필요합니다.');
    }

    final items = await sftpClient.listdir(normalized);
    final entries = items
        .where((item) => item.filename != '.' && item.filename != '..')
        .map((item) {
      final fullPath = p.posix.join(normalized, item.filename);
      final kind = item.attr.isDirectory ? 'dir' : 'file';
      final meta = inferFileMeta(fullPath, kind);
      return RemoteFileEntry(
        kind: kind,
        name: item.filename,
        path: fullPath,
        size: item.attr.size,
        modifiedAt: _unixSecondsToDate(item.attr.modifyTime),
        createdAt: _unixSecondsToDate(item.attr.accessTime),
        previewKind: meta.previewKind,
        typeLabel: meta.typeLabel,
        language: meta.language,
        iconName: meta.iconName,
      );
    }).toList()
      ..sort((left, right) {
        if (left.isDirectory != right.isDirectory) {
          return left.isDirectory ? -1 : 1;
        }
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });

    currentPath = normalized;
    return RemoteDirectory(
      currentPath: normalized,
      parentPath: normalized == '/' ? null : p.posix.dirname(normalized),
      entries: entries,
    );
  }

  Future<void> createDirectory(String parentPath, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.contains('/')) {
      throw ArgumentError('폴더 이름을 올바르게 입력해야 합니다.');
    }
    final sftpClient = await sftp();
    await sftpClient.mkdir(p.posix.join(parentPath, trimmed));
  }

  Future<void> rename(String sourcePath, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed.contains('/')) {
      throw ArgumentError('새 이름을 올바르게 입력해야 합니다.');
    }
    final sftpClient = await sftp();
    await sftpClient.rename(
        sourcePath, p.posix.join(p.posix.dirname(sourcePath), trimmed));
  }

  Future<RemoteTextFile> readTextFile(String remotePath,
      {int maxBytes = maxPreviewBytes}) async {
    final sftpClient = await sftp();
    final stat = await sftpClient.stat(remotePath);
    if ((stat.size ?? 0) > maxBytes) {
      final bytes = await _readFileBytes(sftpClient, remotePath, maxBytes);
      return _mapTextFile(remotePath, bytes, stat, truncated: true);
    }
    final bytes = await _readFileBytes(sftpClient, remotePath, maxBytes);
    return _mapTextFile(remotePath, bytes, stat, truncated: false);
  }

  Future<void> writeTextFile(String remotePath, String content) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    if (bytes.length > maxEditBytes) {
      throw StateError('저장 가능 최대 크기 $maxEditBytes bytes를 초과했습니다.');
    }
    final sftpClient = await sftp();
    final file = await sftpClient.open(remotePath,
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate);
    await file.writeBytes(bytes);
    await file.close();
  }

  Future<Uint8List> downloadBytes(String remotePath) async {
    final sftpClient = await sftp();
    return _readFileBytes(sftpClient, remotePath, null);
  }

  Future<void> uploadBytes(
      String parentPath, String name, Uint8List bytes) async {
    if (name.trim().isEmpty || name.contains('/')) {
      throw ArgumentError('업로드 파일 이름이 올바르지 않습니다.');
    }
    final sftpClient = await sftp();
    final file = await sftpClient.open(p.posix.join(parentPath, name),
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate);
    await file.writeBytes(bytes);
    await file.close();
  }

  Future<void> uploadStream(
    String parentPath,
    String name,
    Stream<List<int>> stream,
  ) async {
    if (name.trim().isEmpty || name.contains('/')) {
      throw ArgumentError('업로드 파일 이름이 올바르지 않습니다.');
    }
    final sftpClient = await sftp();
    final file = await sftpClient.open(p.posix.join(parentPath, name),
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate);
    try {
      final writer = file.write(stream.map(_toUint8List));
      await writer.done;
    } finally {
      await file.close();
    }
  }

  Future<void> deleteRemoteFile(String remotePath) async {
    final trimmed = remotePath.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final sftpClient = await sftp();
    await sftpClient.remove(trimmed);
  }

  void close({bool closeClient = true}) {
    unawaited(_disposePersistentShell());
    _sftp?.close();
    _sftp = null;
    if (closeClient) {
      client.close();
    }
  }

  Future<Uint8List> _readFileBytes(
      SftpClient sftpClient, String remotePath, int? limit) async {
    final file = await sftpClient.open(remotePath);
    final chunks = <int>[];
    var offset = 0;
    while (true) {
      final remaining =
          limit == null ? 32768 : (limit - chunks.length).clamp(0, 32768);
      if (remaining == 0) {
        break;
      }
      final chunk = await file.readBytes(offset: offset, length: remaining);
      if (chunk.isEmpty) {
        break;
      }
      chunks.addAll(chunk);
      offset += chunk.length;
    }
    await file.close();
    return Uint8List.fromList(chunks);
  }

  RemoteTextFile _mapTextFile(
      String remotePath, Uint8List bytes, SftpFileAttrs stat,
      {required bool truncated}) {
    final meta = inferFileMeta(remotePath, 'file');
    return RemoteTextFile(
      path: remotePath,
      name: p.posix.basename(remotePath),
      content: utf8.decode(bytes, allowMalformed: true),
      truncated: truncated,
      size: stat.size ?? bytes.length,
      modifiedAt: _unixSecondsToDate(stat.modifyTime),
      createdAt: _unixSecondsToDate(stat.accessTime),
      previewKind: meta.previewKind,
      typeLabel: meta.typeLabel,
      language: meta.language,
    );
  }

  TmuxCaptureFrame _parseCaptureFrame(String output) {
    final markerIndex = output.lastIndexOf(_tmuxCaptureMarker);
    if (markerIndex < 0) {
      return TmuxCaptureFrame(
        content: output.trimRight(),
        paneId: activeTmuxPaneId,
        cursorX: 0,
        cursorY: 0,
        paneWidth: 80,
        paneHeight: 24,
        paneMode: '',
        currentPath: null,
        historySize: null,
      );
    }

    final content = output.substring(0, markerIndex).trimRight();
    final meta =
        output.substring(markerIndex + _tmuxCaptureMarker.length).trim();
    final parts = meta.split(_tmuxDelimiter);
    final paneId = parts.isNotEmpty && parts.first.trim().isNotEmpty
        ? parts.first.trim()
        : activeTmuxPaneId;
    if (paneId != null) {
      activeTmuxPaneId = paneId;
    }
    final historySize = parts.length > 6 ? int.tryParse(parts[6]) : null;
    final panePath =
        parts.length > 7 ? parts.sublist(7).join(_tmuxDelimiter).trim() : '';
    if (panePath.isNotEmpty) {
      currentPath = panePath;
    }
    return TmuxCaptureFrame(
      content: content,
      paneId: paneId,
      cursorX: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      cursorY: parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
      paneWidth: parts.length > 3 ? int.tryParse(parts[3]) ?? 80 : 80,
      paneHeight: parts.length > 4 ? int.tryParse(parts[4]) ?? 24 : 24,
      paneMode: parts.length > 5 ? parts[5] : '',
      currentPath: panePath.isEmpty ? null : panePath,
      historySize: historySize,
    );
  }
}

Uint8List _toUint8List(List<int> chunk) {
  return chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
}

class TmuxCaptureFrame {
  const TmuxCaptureFrame({
    required this.content,
    required this.paneId,
    required this.cursorX,
    required this.cursorY,
    required this.paneWidth,
    required this.paneHeight,
    required this.paneMode,
    required this.currentPath,
    required this.historySize,
    this.latencyMs = 0,
  });

  final String content;
  final String? paneId;
  final int cursorX;
  final int cursorY;
  final int paneWidth;
  final int paneHeight;
  final String paneMode;
  final String? currentPath;
  final int? historySize;
  final int latencyMs;

  TmuxCaptureFrame copyWith({int? latencyMs}) {
    return TmuxCaptureFrame(
      content: content,
      paneId: paneId,
      cursorX: cursorX,
      cursorY: cursorY,
      paneWidth: paneWidth,
      paneHeight: paneHeight,
      paneMode: paneMode,
      currentPath: currentPath,
      historySize: historySize,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }
}

class _SshCommandQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail.catchError((Object _) {});
    final completer = Completer<void>();
    _tail = completer.future;

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
}

class _PersistentShell {
  _PersistentShell(this._client);

  static const _markerId = 'seil_persistent_shell_v1';
  static const _startMarker = '\x01__SEIL_SHELL_START_${_markerId}__\x01';
  static const _endMarker = '\x01__SEIL_SHELL_END_${_markerId}__\x01';
  static const _printfStartMarker =
      r'\x01__SEIL_SHELL_START_seil_persistent_shell_v1__\x01';
  static const _printfEndMarker =
      r'\x01__SEIL_SHELL_END_seil_persistent_shell_v1__\x01';

  final SSHClient _client;
  final List<int> _rawBuffer = [];
  SSHSession? _session;
  StreamSubscription<Uint8List>? _stdoutSubscription;
  Completer<String>? _pendingCommand;
  bool _closed = false;

  bool get isStarted => _session != null && !_closed;

  Future<void> start() async {
    if (_session != null && !_closed) {
      return;
    }
    _session = await _client.shell(
      pty: const SSHPtyConfig(
        type: 'dumb',
        width: 200,
        height: 50,
      ),
    );
    _closed = false;
    _stdoutSubscription = _session!.stdout.listen(
      _onData,
      onDone: _onDone,
      onError: _onError,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _session!.write(utf8.encode(
      'export HISTFILE=/dev/null HISTSIZE=0 HISTFILESIZE=0 SAVEHIST=0 2>/dev/null;'
      ' set fish_history "" 2>/dev/null; true;'
      ' export PS1="" PS2="" 2>/dev/null; stty -echo 2>/dev/null\n',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _rawBuffer.clear();
  }

  Future<String> exec(String command, {required Duration timeout}) async {
    final session = _session;
    if (session == null || _closed) {
      throw const _PersistentShellError('Shell session is closed');
    }
    if (_pendingCommand != null && !_pendingCommand!.isCompleted) {
      throw const _PersistentShellError('Another command is already running');
    }

    final completer = Completer<String>();
    _pendingCommand = completer;
    _rawBuffer.clear();
    session.write(utf8.encode(
      "printf '$_printfStartMarker\\n'; $command; printf '$_printfEndMarker\\n'\n",
    ));

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pendingCommand = null;
      throw const _PersistentShellError('Command execution timed out');
    }
  }

  Future<void> dispose() async {
    _closed = true;
    final pending = _pendingCommand;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const _PersistentShellError('Shell disposed'));
    }
    _pendingCommand = null;
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    _session?.close();
    _session = null;
    _rawBuffer.clear();
  }

  void _onData(Uint8List data) {
    final pending = _pendingCommand;
    if (pending == null || pending.isCompleted) {
      return;
    }
    _rawBuffer.addAll(data);
    final content = utf8.decode(_rawBuffer, allowMalformed: true);
    final startIndex = content.indexOf(_startMarker);
    final endIndex = content.indexOf(_endMarker);
    if (startIndex < 0 || endIndex < 0 || endIndex <= startIndex) {
      return;
    }

    var result = content.substring(startIndex + _startMarker.length, endIndex);
    result = result.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (result.startsWith('\n')) {
      result = result.substring(1);
    }
    if (result.endsWith('\n')) {
      result = result.substring(0, result.length - 1);
    }

    _pendingCommand = null;
    _rawBuffer.clear();
    pending.complete(result);
  }

  void _onDone() {
    _closed = true;
    final pending = _pendingCommand;
    if (pending != null && !pending.isCompleted) {
      pending
          .completeError(const _PersistentShellError('Shell session closed'));
    }
  }

  void _onError(Object error) {
    _closed = true;
    final pending = _pendingCommand;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(_PersistentShellError('Shell error: $error'));
    }
  }
}

class _PersistentShellError implements Exception {
  const _PersistentShellError(this.message);

  final String message;

  @override
  String toString() => '_PersistentShellError: $message';
}

bool _isClosedSshState(SSHStateError error) {
  final message = error.message.toLowerCase();
  return message.contains('transport is closed') ||
      message.contains('connection closed');
}

String? _extractMarker(String output, String marker) {
  for (final line in const LineSplitter().convert(output)) {
    if (line.startsWith(marker)) {
      return line.replaceFirst(marker, '').trim();
    }
  }
  return null;
}

String _normalizeRemoteDirectory(String remotePath) {
  final trimmed = remotePath.trim();
  if (trimmed.isEmpty) {
    return '/';
  }
  final normalized = p.posix.normalize(trimmed);
  return normalized.startsWith('/') ? normalized : '/$normalized';
}

String _quoteShellToken(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

DateTime? _unixSecondsToDate(int? value) {
  if (value == null || value <= 0) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
}

DateTime? _unixSecondsStringToDate(String value) {
  return _unixSecondsToDate(int.tryParse(value.trim()));
}
