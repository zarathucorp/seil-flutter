import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/localization/seil_error_codes.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models.dart';

class HostKeyRepository {
  HostKeyRepository(this.database);

  final LocalDatabase database;
  final _uuid = const Uuid();
  static final _fingerprintPattern = RegExp(
    r'^(SHA256:[A-Za-z0-9+/=]+|MD5:([0-9a-f]{2}:){15}[0-9a-f]{2})$',
  );

  Future<List<TrustedHostKey>> listTrustedHostKeys() async {
    final rows = await database.db.query(
      'trusted_host_keys',
      orderBy: 'host ASC, port ASC, updated_at DESC',
    );
    return rows.map(_mapHostKey).toList();
  }

  Future<List<TrustedHostKey>> listTrustedHostKeysForHost({
    required String host,
    required int port,
  }) async {
    final rows = await database.db.query(
      'trusted_host_keys',
      where: 'host = ? AND port = ?',
      whereArgs: [host.trim().toLowerCase(), port],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapHostKey).toList();
  }

  Future<TrustedHostKey> trustHostKey({
    required String host,
    required int port,
    required String keyType,
    required String fingerprintSha256,
  }) async {
    final normalizedHost = host.trim().toLowerCase();
    final normalizedFingerprint =
        _normalizeHostKeyFingerprint(fingerprintSha256);
    if (normalizedHost.isEmpty || port <= 0 || port > 65535) {
      throw ArgumentError(SeilErrorCodes.hostKeyInvalid);
    }
    if (!_fingerprintPattern.hasMatch(normalizedFingerprint)) {
      throw ArgumentError(SeilErrorCodes.hostKeyFingerprintInvalid);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await database.db.query(
      'trusted_host_keys',
      where: 'host = ? AND port = ? AND fingerprint_sha256 = ?',
      whereArgs: [normalizedHost, port, normalizedFingerprint],
      limit: 1,
    );
    final id = rows.isEmpty ? _uuid.v4() : rows.first['id'] as String;
    await database.db.insert(
      'trusted_host_keys',
      {
        'id': id,
        'host': normalizedHost,
        'port': port,
        'key_type': keyType.trim().isEmpty ? 'unknown' : keyType.trim(),
        'fingerprint_sha256': normalizedFingerprint,
        'created_at': rows.isEmpty ? now : rows.first['created_at'] as String,
        'updated_at': now,
        'last_verified_at':
            rows.isEmpty ? null : rows.first['last_verified_at'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return getTrustedHostKey(id);
  }

  Future<TrustedHostKey> getTrustedHostKey(String id) async {
    final rows = await database.db
        .query('trusted_host_keys', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      throw StateError(SeilErrorCodes.hostKeyNotFound);
    }
    return _mapHostKey(rows.first);
  }

  Future<void> deleteTrustedHostKey(String id) async {
    await database.db
        .delete('trusted_host_keys', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> isTrusted({
    required String host,
    required int port,
    required String fingerprintSha256,
  }) async {
    final normalizedFingerprint =
        _normalizeHostKeyFingerprint(fingerprintSha256);
    final rows = await database.db.query(
      'trusted_host_keys',
      where: 'host = ? AND port = ? AND fingerprint_sha256 = ?',
      whereArgs: [host.trim().toLowerCase(), port, normalizedFingerprint],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    await database.db.update(
      'trusted_host_keys',
      {'last_verified_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    return true;
  }

  String _normalizeHostKeyFingerprint(String value) {
    final trimmed = value.trim();
    if (trimmed.toUpperCase().startsWith('MD5:')) {
      return 'MD5:${trimmed.substring(4).toLowerCase()}';
    }
    return trimmed;
  }

  TrustedHostKey _mapHostKey(Map<String, Object?> row) {
    return TrustedHostKey(
      id: row['id'] as String,
      host: row['host'] as String,
      port: row['port'] as int,
      keyType: row['key_type'] as String,
      fingerprintSha256: row['fingerprint_sha256'] as String,
      createdAt: parseIso(row['created_at'] as String),
      updatedAt: parseIso(row['updated_at'] as String),
      lastVerifiedAt: row['last_verified_at'] == null
          ? null
          : parseIso(row['last_verified_at'] as String),
    );
  }
}
