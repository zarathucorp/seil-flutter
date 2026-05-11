enum UserRole { admin, user }

enum AuthMode { password, privateKey, agent }

enum FilePreviewKind { dir, code, markdown, image, download }

const defaultTmuxHistoryLimit = 2000;
const recommendedTmuxHistoryLimit = 20000;

class RemoteTmuxSession {
  const RemoteTmuxSession({
    required this.name,
    required this.windows,
    required this.attachedClients,
    required this.createdAt,
    required this.lastActivityAt,
    required this.currentPath,
  });

  final String name;
  final int windows;
  final int attachedClients;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;
  final String? currentPath;

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
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    required this.passwordChangedAt,
    required this.protectedAccount,
  });

  final String id;
  final String username;
  final String name;
  final UserRole role;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime passwordChangedAt;
  final bool protectedAccount;
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
