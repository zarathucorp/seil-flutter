abstract final class SeilErrorCodes {
  static const invalidUsernameOrPassword =
      'seil.error.invalidUsernameOrPassword';
  static const incorrectPassword = 'seil.error.incorrectPassword';
  static const userNotFound = 'seil.error.userNotFound';
  static const noLoggedInUser = 'seil.error.noLoggedInUser';
  static const initialUserExists = 'seil.error.initialUserExists';
  static const savedConnectionNotFound = 'seil.error.savedConnectionNotFound';
  static const connectionFieldsRequired = 'seil.error.connectionFieldsRequired';
  static const tmuxHistoryLimitInvalid = 'seil.error.tmuxHistoryLimitInvalid';
  static const hostKeyInvalid = 'seil.error.hostKeyInvalid';
  static const hostKeyFingerprintInvalid =
      'seil.error.hostKeyFingerprintInvalid';
  static const hostKeyNotFound = 'seil.error.hostKeyNotFound';
  static const missingSshSecret = 'seil.error.missingSshSecret';
  static const privateKeyPassphraseRequired =
      'seil.error.privateKeyPassphraseRequired';
  static const sshSocketTimeout = 'seil.error.sshSocketTimeout';
  static const sshInitializationTimeout = 'seil.error.sshInitializationTimeout';
  static const sshPasswordAuthenticationRejected =
      'seil.error.sshPasswordAuthenticationRejected';
  static const sshPrivateKeyAuthenticationRejected =
      'seil.error.sshPrivateKeyAuthenticationRejected';
  static const sftpOperationTimeout = 'seil.error.sftpOperationTimeout';
  static const sshAgentUnsupported = 'seil.error.sshAgentUnsupported';
  static const directoryPathRequired = 'seil.error.directoryPathRequired';
  static const invalidFolderName = 'seil.error.invalidFolderName';
  static const invalidNewName = 'seil.error.invalidNewName';
  static const invalidUploadFileName = 'seil.error.invalidUploadFileName';
  static const reconnecting = 'seil.error.reconnecting';
  static const invalidUsername = 'seil.error.invalidUsername';
  static const invalidDisplayName = 'seil.error.invalidDisplayName';

  static const invalidPasswordLengthPrefix =
      'seil.error.invalidPasswordLength:';
  static const fileTooLargePrefix = 'seil.error.fileTooLarge:';
  static const sshReconnectFailedPrefix = 'seil.error.sshReconnectFailed:';

  static String invalidPasswordLength(int minLength, int maxLength) {
    return '$invalidPasswordLengthPrefix$minLength:$maxLength';
  }

  static String fileTooLarge(int maxBytes) {
    return '$fileTooLargePrefix$maxBytes';
  }

  static String sshReconnectFailed(Object error) {
    return '$sshReconnectFailedPrefix$error';
  }
}
