import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/localization/seil_error_codes.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/secure_vault.dart';
import '../../shared/models.dart';

class ConnectionRepository {
  ConnectionRepository(this.database, this.vault);

  final LocalDatabase database;
  final SecureVault vault;
  final _uuid = const Uuid();

  Future<List<SavedConnection>> listConnections() async {
    final rows =
        await database.db.query('connections', orderBy: 'updated_at DESC');
    return rows.map(_mapConnection).toList();
  }

  Future<SavedConnection> upsertConnection(SshConnectionInput input) async {
    _assertConnectionInput(input);
    final fingerprint = createConnectionFingerprint(input);
    final existing = await database.db.query(
      'connections',
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    final now = DateTime.now().toUtc();
    final id = existing.isEmpty ? _uuid.v4() : existing.first['id'] as String;
    final hasStoredSecret = input.saveSecret && input.secret.trim().isNotEmpty;

    final row = {
      'id': id,
      'label': input.label.trim(),
      'host': input.host.trim(),
      'port': input.port,
      'username': input.username.trim(),
      'auth_mode': authModeToDb(input.authMode),
      'tmux_history_limit': input.tmuxHistoryLimit,
      'fingerprint': fingerprint,
      'has_stored_secret': hasStoredSecret ? 1 : 0,
      'created_at': existing.isEmpty
          ? now.toIso8601String()
          : existing.first['created_at'] as String,
      'updated_at': now.toIso8601String(),
    };

    await database.db.insert('connections', row,
        conflictAlgorithm: ConflictAlgorithm.replace);

    if (hasStoredSecret) {
      await vault.writeConnectionSecret(id, input.secret);
      if (input.authMode == AuthMode.privateKey &&
          input.passphrase.isNotEmpty) {
        await vault.writeConnectionPassphrase(id, input.passphrase);
      } else {
        await vault.deleteConnectionPassphrase(id);
      }
    } else {
      await vault.deleteConnectionSecrets(id);
    }

    return getConnection(id);
  }

  Future<SavedConnection> getConnection(String id) async {
    final rows = await database.db
        .query('connections', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      throw StateError(SeilErrorCodes.savedConnectionNotFound);
    }
    return _mapConnection(rows.first);
  }

  Future<String?> resolveSecret(SavedConnection connection,
      [String? transientSecret]) async {
    final value = transientSecret?.trim();
    if (value != null && value.isNotEmpty) {
      return transientSecret;
    }
    return vault.readConnectionSecret(connection.id);
  }

  Future<String?> resolvePassphrase(
    SavedConnection connection, [
    String? transientPassphrase,
  ]) async {
    if (transientPassphrase != null) {
      return transientPassphrase;
    }
    return vault.readConnectionPassphrase(connection.id);
  }

  Future<bool> storedPrivateKeyNeedsPassphrase(
    SavedConnection connection,
  ) async {
    if (connection.authMode != AuthMode.privateKey ||
        !connection.hasStoredSecret) {
      return false;
    }
    final privateKey = await vault.readConnectionSecret(connection.id);
    if (privateKey == null || privateKey.isEmpty) {
      return false;
    }
    try {
      if (!SSHKeyPair.isEncryptedPem(privateKey)) {
        return false;
      }
    } catch (_) {
      return false;
    }
    final passphrase = await vault.readConnectionPassphrase(connection.id);
    return passphrase == null || passphrase.isEmpty;
  }

  Future<void> deleteConnection(String id) async {
    await database.db.delete('connections', where: 'id = ?', whereArgs: [id]);
    await vault.deleteConnectionSecrets(id);
  }

  String createConnectionFingerprint(SshConnectionInput input) {
    final payload = [
      input.host.trim(),
      input.port.toString(),
      input.username.trim(),
      authModeToDb(input.authMode)
    ].join('\u0000');
    return sha256.convert(utf8.encode(payload)).toString();
  }

  void _assertConnectionInput(SshConnectionInput input) {
    if (input.host.trim().isEmpty ||
        input.username.trim().isEmpty ||
        input.port <= 0 ||
        input.port > 65535) {
      throw ArgumentError(SeilErrorCodes.connectionFieldsRequired);
    }
    if (input.authMode == AuthMode.agent) {
      throw ArgumentError(SeilErrorCodes.sshAgentUnsupported);
    }
    if (input.tmuxHistoryLimit <= 0) {
      throw ArgumentError(SeilErrorCodes.tmuxHistoryLimitInvalid);
    }
  }

  SavedConnection _mapConnection(Map<String, Object?> row) {
    return SavedConnection(
      id: row['id'] as String,
      label: row['label'] as String,
      host: row['host'] as String,
      port: row['port'] as int,
      username: row['username'] as String,
      authMode: authModeFromDb(row['auth_mode'] as String),
      tmuxHistoryLimit:
          (row['tmux_history_limit'] as int?) ?? defaultTmuxHistoryLimit,
      fingerprint: row['fingerprint'] as String,
      hasStoredSecret: (row['has_stored_secret'] as int) == 1,
      createdAt: parseIso(row['created_at'] as String),
      updatedAt: parseIso(row['updated_at'] as String),
    );
  }
}
