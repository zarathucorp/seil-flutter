import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureVault {
  const SecureVault();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  String connectionSecretKey(String connectionId) => 'seil.connection.$connectionId.secret';
  String connectionPrivateKeyKey(String connectionId) => 'seil.connection.$connectionId.private_key';

  Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }

  Future<void> writeConnectionSecret(String connectionId, String secret) {
    return write(connectionSecretKey(connectionId), secret);
  }

  Future<String?> readConnectionSecret(String connectionId) {
    return read(connectionSecretKey(connectionId));
  }

  Future<void> deleteConnectionSecrets(String connectionId) async {
    await delete(connectionSecretKey(connectionId));
    await delete(connectionPrivateKeyKey(connectionId));
  }
}

