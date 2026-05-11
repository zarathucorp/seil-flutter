import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/local_database.dart';
import '../../shared/models.dart';

class HostKeyRepository {
  HostKeyRepository(this.database);

  final LocalDatabase database;
  final _uuid = const Uuid();

  Future<List<TrustedHostKey>> listTrustedHostKeys() async {
    final rows = await database.db.query(
      'trusted_host_keys',
      orderBy: 'host ASC, port ASC, updated_at DESC',
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
    if (normalizedHost.isEmpty || port <= 0 || port > 65535) {
      throw ArgumentError('host와 port를 올바르게 입력해야 합니다.');
    }
    if (!RegExp(r'^SHA256:[A-Za-z0-9+/]+$').hasMatch(fingerprintSha256.trim())) {
      throw ArgumentError('SHA256 fingerprint 형식이 올바르지 않습니다.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await database.db.query(
      'trusted_host_keys',
      where: 'host = ? AND port = ? AND fingerprint_sha256 = ?',
      whereArgs: [normalizedHost, port, fingerprintSha256.trim()],
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
        'fingerprint_sha256': fingerprintSha256.trim(),
        'created_at': rows.isEmpty ? now : rows.first['created_at'] as String,
        'updated_at': now,
        'last_verified_at': rows.isEmpty ? null : rows.first['last_verified_at'],
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return getTrustedHostKey(id);
  }

  Future<TrustedHostKey> getTrustedHostKey(String id) async {
    final rows = await database.db.query('trusted_host_keys', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      throw StateError('호스트 키를 찾을 수 없습니다.');
    }
    return _mapHostKey(rows.first);
  }

  Future<void> deleteTrustedHostKey(String id) async {
    await database.db.delete('trusted_host_keys', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> isTrusted({
    required String host,
    required int port,
    required String fingerprintSha256,
  }) async {
    final rows = await database.db.query(
      'trusted_host_keys',
      where: 'host = ? AND port = ? AND fingerprint_sha256 = ?',
      whereArgs: [host.trim().toLowerCase(), port, fingerprintSha256.trim()],
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

  TrustedHostKey _mapHostKey(Map<String, Object?> row) {
    return TrustedHostKey(
      id: row['id'] as String,
      host: row['host'] as String,
      port: row['port'] as int,
      keyType: row['key_type'] as String,
      fingerprintSha256: row['fingerprint_sha256'] as String,
      createdAt: parseIso(row['created_at'] as String),
      updatedAt: parseIso(row['updated_at'] as String),
      lastVerifiedAt: row['last_verified_at'] == null ? null : parseIso(row['last_verified_at'] as String),
    );
  }
}

