enum AuthMode { password, privateKey, agent }

enum FilePreviewKind { dir, code, markdown, image, download }

enum TerminalAttentionState { none, running, completed, actionRequired }

const defaultTmuxHistoryLimit = 2000;
const recommendedTmuxHistoryLimit = 20000;

TerminalAttentionState terminalAttentionFromTmux({
  String? terminalTitle,
  String? windowName,
  String? terminalScreen,
  String? windowFlags,
  String? windowActivityFlag,
  String? windowBellFlag,
}) {
  final text = [
    terminalTitle,
    windowName,
  ].whereType<String>().join(' ').toLowerCase();
  final screen = (terminalScreen ?? '').toLowerCase();
  if (_containsActionRequiredText(text) ||
      _containsActionRequiredText(screen)) {
    return TerminalAttentionState.actionRequired;
  }
  if (_containsRunningScreen(screen)) {
    return TerminalAttentionState.running;
  }
  if (_containsCompletedScreen(screen)) {
    return TerminalAttentionState.completed;
  }
  if (_containsRunningTitle(text)) {
    return TerminalAttentionState.running;
  }
  if (windowBellFlag?.trim() == '1' || (windowFlags?.contains('!') ?? false)) {
    return TerminalAttentionState.completed;
  }
  return TerminalAttentionState.none;
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

bool _containsCompletedScreen(String text) {
  return RegExp(r'\b(cooked|worked) for \d+s\b').hasMatch(text);
}

TerminalAttentionState maxTerminalAttentionState(
  TerminalAttentionState left,
  TerminalAttentionState right,
) {
  return _terminalAttentionPriority(left) >= _terminalAttentionPriority(right)
      ? left
      : right;
}

TerminalAttentionState terminalAttentionFromTransition({
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
