enum AuthMode { password, privateKey, agent }

enum FilePreviewKind { dir, code, markdown, image, download }

enum TerminalAttentionState { none, running, completed, actionRequired }

const defaultTmuxHistoryLimit = 2000;
const recommendedTmuxHistoryLimit = 20000;

TerminalAttentionState terminalAttentionFromTmux({
  String? terminalTitle,
  String? windowName,
  String? terminalScreen,
  String? paneCurrentCommand,
  String? windowFlags,
  String? windowActivityFlag,
  String? windowBellFlag,
  bool allowTitleRunning = true,
}) {
  final eventState = terminalAttentionFromTmuxDirectEvent(
    terminalTitle: terminalTitle,
    windowName: windowName,
    windowFlags: windowFlags,
    windowBellFlag: windowBellFlag,
  );
  if (eventState != TerminalAttentionState.none) {
    return eventState;
  }
  return terminalAttentionFromTmuxCurrentState(
    terminalTitle: terminalTitle,
    windowName: windowName,
    terminalScreen: terminalScreen,
    paneCurrentCommand: paneCurrentCommand,
    allowTitleRunning: allowTitleRunning,
  );
}

TerminalAttentionState terminalAttentionFromTmuxDirectEvent({
  String? terminalTitle,
  String? windowName,
  String? windowFlags,
  String? windowBellFlag,
}) {
  final text = [
    terminalTitle,
    windowName,
  ].whereType<String>().join(' ').toLowerCase();
  if (_containsActionRequiredText(text)) {
    return TerminalAttentionState.actionRequired;
  }
  if (windowBellFlag?.trim() == '1' || (windowFlags?.contains('!') ?? false)) {
    return TerminalAttentionState.completed;
  }
  return TerminalAttentionState.none;
}

TerminalAttentionState terminalAttentionFromTmuxCurrentState({
  String? terminalTitle,
  String? windowName,
  String? terminalScreen,
  String? paneCurrentCommand,
  bool allowTitleRunning = true,
}) {
  final text = [
    terminalTitle,
    windowName,
  ].whereType<String>().join(' ').toLowerCase();
  final screen = (terminalScreen ?? '').toLowerCase();
  if (_containsRunningScreen(screen)) {
    return TerminalAttentionState.running;
  }
  if (allowTitleRunning && _containsRunningTitle(text)) {
    return TerminalAttentionState.running;
  }
  if (_isForegroundJobRunning(paneCurrentCommand)) {
    return TerminalAttentionState.running;
  }
  return TerminalAttentionState.none;
}

TerminalAttentionState terminalAttentionFromTerminalOutput(String output) {
  final notificationText = _terminalNotificationText(output);
  if (notificationText.isNotEmpty) {
    return _containsActionRequiredText(notificationText.toLowerCase())
        ? TerminalAttentionState.actionRequired
        : TerminalAttentionState.completed;
  }

  final titleText = _terminalTitleText(output);
  if (titleText.isNotEmpty) {
    final normalizedTitle = titleText.toLowerCase();
    if (_containsActionRequiredText(normalizedTitle)) {
      return TerminalAttentionState.actionRequired;
    }
    if (_containsRunningTitle(normalizedTitle)) {
      return TerminalAttentionState.running;
    }
  }

  final outputWithoutOsc = output.replaceAll(_terminalOscPattern, '');
  if (outputWithoutOsc.contains('\x07')) {
    return TerminalAttentionState.completed;
  }
  return TerminalAttentionState.none;
}

bool terminalOutputHasAttentionCue(String output) {
  if (_terminalNotificationText(output).isNotEmpty ||
      _terminalTitleText(output).isNotEmpty) {
    return true;
  }
  final outputWithoutOsc = output.replaceAll(_terminalOscPattern, '');
  return outputWithoutOsc.contains('\x07');
}

bool _containsActionRequiredText(String text) {
  return text.contains('action required') ||
      text.contains('approval requested') ||
      text.contains('permission requested') ||
      text.contains('requires approval') ||
      text.contains('needs approval') ||
      text.contains('do you want to proceed') ||
      text.contains('allow this') ||
      text.contains('waiting for approval');
}

bool _containsRunningTitle(String text) {
  const spinnerFrames = [
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏',
    '⠂',
    '⠐',
  ];
  if (spinnerFrames.any(text.contains)) {
    return true;
  }
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('✳ ') && !trimmed.contains('claude code')) {
    return true;
  }
  final looksLikeCodexTitle = text.contains('codex') ||
      text.contains('agent') ||
      text.contains('claude');
  return looksLikeCodexTitle &&
      (text.contains('working') ||
          text.contains('thinking') ||
          text.contains('running'));
}

bool _containsRunningScreen(String text) {
  return text.contains('esc to interrupt') ||
      text.contains('ctrl+c to interrupt') ||
      text.contains('canoodling') ||
      text.contains('swooping');
}

bool _isForegroundJobRunning(String? paneCurrentCommand) {
  final command = paneCurrentCommand?.trim().toLowerCase();
  if (command == null || command.isEmpty) {
    return false;
  }
  final basename = command.split('/').last;
  if (_idlePaneCommands.contains(basename) ||
      _interactivePaneCommands.contains(basename)) {
    return false;
  }
  return true;
}

const _idlePaneCommands = {
  'sh',
  'bash',
  'zsh',
  'fish',
  'dash',
  'ksh',
  'csh',
  'tcsh',
  'login',
  'tmux',
};

const _interactivePaneCommands = {
  'claude',
  'codex',
  'node',
  'python',
  'python3',
  'ruby',
  'irb',
  'ipython',
  'ptpython',
  'php',
  'psql',
  'mysql',
  'sqlite3',
  'redis-cli',
  'vi',
  'vim',
  'nvim',
  'nano',
  'emacs',
  'less',
  'more',
  'man',
  'top',
  'htop',
  'btop',
  'watch',
  'ssh',
  'mosh',
};

final _terminalOscPattern = RegExp(
  '\x1b\\]([^;\x07]+);(.*?)(?:\x07|\x1b\\\\)',
  dotAll: true,
);

String _terminalTitleText(String output) {
  final titles = <String>[];
  for (final match in _terminalOscPattern.allMatches(output)) {
    final code = match.group(1)?.trim();
    if (code == '0' || code == '1' || code == '2') {
      titles.add(match.group(2) ?? '');
    }
  }
  return titles.join(' ');
}

String _terminalNotificationText(String output) {
  final notifications = <String>[];
  for (final match in _terminalOscPattern.allMatches(output)) {
    final code = match.group(1)?.trim();
    final body = match.group(2) ?? '';
    if (code == '9' || code == '99') {
      notifications.add(body);
    } else if (code == '777') {
      notifications.add(body.replaceAll(';', ' '));
    } else if (code == '1337' && body.toLowerCase().contains('notify')) {
      notifications.add(
          body.replaceAll(RegExp(r'notify[=;]?', caseSensitive: false), ''));
    }
  }
  return notifications.join(' ');
}

TerminalAttentionState maxTerminalAttentionState(
  TerminalAttentionState left,
  TerminalAttentionState right,
) {
  return _terminalAttentionPriority(left) >= _terminalAttentionPriority(right)
      ? left
      : right;
}

TerminalAttentionState terminalAttentionFromFallbackTransition({
  required TerminalAttentionState previous,
  required TerminalAttentionState current,
}) {
  if (current != TerminalAttentionState.none) {
    return current;
  }
  if (previous == TerminalAttentionState.actionRequired ||
      previous == TerminalAttentionState.completed) {
    return previous;
  }
  if (previous == TerminalAttentionState.running) {
    return TerminalAttentionState.completed;
  }
  return TerminalAttentionState.none;
}

TerminalAttentionState terminalAttentionFromTransition({
  required TerminalAttentionState previous,
  required TerminalAttentionState current,
}) {
  return terminalAttentionFromFallbackTransition(
    previous: previous,
    current: current,
  );
}

int _terminalAttentionPriority(TerminalAttentionState state) {
  switch (state) {
    case TerminalAttentionState.actionRequired:
      return 3;
    case TerminalAttentionState.running:
      return 2;
    case TerminalAttentionState.completed:
      return 1;
    case TerminalAttentionState.none:
      return 0;
  }
}

class RemoteTmuxSession {
  const RemoteTmuxSession({
    required this.name,
    required this.windows,
    required this.attachedClients,
    required this.createdAt,
    required this.lastActivityAt,
    required this.currentPath,
    this.attentionState = TerminalAttentionState.none,
    this.attentionPaneId,
    this.terminalTitle,
    this.windowFlags,
  });

  final String name;
  final int windows;
  final int attachedClients;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;
  final String? currentPath;
  final TerminalAttentionState attentionState;
  final String? attentionPaneId;
  final String? terminalTitle;
  final String? windowFlags;

  bool get attached => attachedClients > 0;
}

class SessionTag {
  const SessionTag({
    required this.label,
    required this.colorValue,
  });

  final String label;
  final int colorValue;
}

class SeilUser {
  const SeilUser({
    required this.id,
    required this.username,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.passwordChangedAt,
  });

  final String id;
  final String username;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime passwordChangedAt;
}

class SavedConnection {
  const SavedConnection({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.username,
    required this.authMode,
    required this.tmuxHistoryLimit,
    required this.fingerprint,
    required this.hasStoredSecret,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String username;
  final AuthMode authMode;
  final int tmuxHistoryLimit;
  final String fingerprint;
  final bool hasStoredSecret;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayName => label.trim().isEmpty ? host : label;
}

class SshConnectionInput {
  const SshConnectionInput({
    required this.label,
    required this.host,
    required this.port,
    required this.username,
    required this.authMode,
    required this.tmuxHistoryLimit,
    required this.secret,
    required this.saveSecret,
  });

  final String label;
  final String host;
  final int port;
  final String username;
  final AuthMode authMode;
  final int tmuxHistoryLimit;
  final String secret;
  final bool saveSecret;
}

class RemoteSession {
  const RemoteSession({
    required this.id,
    required this.connection,
    required this.hostName,
    required this.homePath,
    required this.currentPath,
    required this.createdAt,
  });

  final String id;
  final SavedConnection connection;
  final String hostName;
  final String homePath;
  final String currentPath;
  final DateTime createdAt;
}

class RemoteFileEntry {
  const RemoteFileEntry({
    required this.kind,
    required this.name,
    required this.path,
    required this.size,
    required this.modifiedAt,
    required this.createdAt,
    required this.previewKind,
    required this.typeLabel,
    required this.language,
    required this.iconName,
  });

  final String kind;
  final String name;
  final String path;
  final int? size;
  final DateTime? modifiedAt;
  final DateTime? createdAt;
  final FilePreviewKind previewKind;
  final String typeLabel;
  final String? language;
  final String iconName;

  bool get isDirectory => kind == 'dir';
}

class RemoteDirectory {
  const RemoteDirectory({
    required this.currentPath,
    required this.parentPath,
    required this.entries,
  });

  final String currentPath;
  final String? parentPath;
  final List<RemoteFileEntry> entries;
}

class RemoteTextFile {
  const RemoteTextFile({
    required this.path,
    required this.name,
    required this.content,
    required this.truncated,
    required this.size,
    required this.modifiedAt,
    required this.createdAt,
    required this.previewKind,
    required this.typeLabel,
    required this.language,
  });

  final String path;
  final String name;
  final String content;
  final bool truncated;
  final int size;
  final DateTime? modifiedAt;
  final DateTime? createdAt;
  final FilePreviewKind previewKind;
  final String typeLabel;
  final String? language;
}

class TrustedHostKey {
  const TrustedHostKey({
    required this.id,
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprintSha256,
    required this.createdAt,
    required this.updatedAt,
    required this.lastVerifiedAt,
  });

  final String id;
  final String host;
  final int port;
  final String keyType;
  final String fingerprintSha256;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastVerifiedAt;
}
