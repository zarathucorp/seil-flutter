import 'package:uuid/uuid.dart';

import '../../core/crypto/password_hash.dart';
import '../../core/storage/local_database.dart';
import '../../shared/models.dart';

class AuthRepository {
  AuthRepository(this.database);

  final LocalDatabase database;
  final _uuid = const Uuid();

  Future<bool> hasUsers() async {
    final rows = await database.db.rawQuery('SELECT COUNT(*) AS c FROM users');
    return (rows.first['c'] as int) > 0;
  }

  Future<SeilUser> bootstrapAdmin({
    required String username,
    required String name,
    required String password,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    assertUsername(normalizedUsername);
    assertDisplayName(name);
    assertPassword(password);

    if (await hasUsers()) {
      throw StateError('이미 초기 사용자가 존재합니다.');
    }

    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final passwordHash = await hashPassword(password);
    await database.db.insert('users', {
      'id': id,
      'username': normalizedUsername,
      'name': name.trim(),
      'role': 'admin',
      'password_hash': passwordHash,
      'protected_account': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'password_changed_at': now.toIso8601String(),
    });
    return getUserById(id);
  }

  Future<SeilUser> bootstrapLocalAdmin() {
    return bootstrapAdmin(
      username: 'admin',
      name: 'Seil Admin',
      password: _uuid.v4(),
    );
  }

  Future<SeilUser?> authenticate(String username, String password) async {
    final rows = await database.db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final matched =
        await verifyPassword(password, rows.first['password_hash'] as String);
    return matched ? _mapUser(rows.first) : null;
  }

  Future<SeilUser?> authenticateDefault(String password) async {
    final rows = await database.db.query(
      'users',
      orderBy: 'protected_account DESC, created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final matched =
        await verifyPassword(password, rows.first['password_hash'] as String);
    return matched ? _mapUser(rows.first) : null;
  }

  Future<SeilUser?> defaultUser() async {
    final rows = await database.db.query(
      'users',
      orderBy: 'protected_account DESC, created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapUser(rows.first);
  }

  Future<List<SeilUser>> listUsers() async {
    final rows = await database.db.query('users', orderBy: 'username ASC');
    return rows.map(_mapUser).toList();
  }

  Future<SeilUser> getUserById(String id) async {
    final rows = await database.db
        .query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      throw StateError('사용자를 찾을 수 없습니다.');
    }
    return _mapUser(rows.first);
  }

  Future<SeilUser> createUser({
    required String username,
    required String name,
    required String password,
    UserRole role = UserRole.user,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    assertUsername(normalizedUsername);
    assertDisplayName(name);
    assertPassword(password);

    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await database.db.insert('users', {
      'id': id,
      'username': normalizedUsername,
      'name': name.trim(),
      'role': roleToDb(role),
      'password_hash': await hashPassword(password),
      'protected_account': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'password_changed_at': now.toIso8601String(),
    });
    return getUserById(id);
  }

  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    assertPassword(newPassword);
    final rows = await database.db
        .query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) {
      throw StateError('사용자를 찾을 수 없습니다.');
    }

    final matched = await verifyPassword(
        currentPassword, rows.first['password_hash'] as String);
    if (!matched) {
      throw StateError('현재 비밀번호가 올바르지 않습니다.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await database.db.update(
      'users',
      {
        'password_hash': await hashPassword(newPassword),
        'updated_at': now,
        'password_changed_at': now,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> setPassword({
    required String userId,
    required String newPassword,
  }) async {
    assertPassword(newPassword);
    final now = DateTime.now().toUtc().toIso8601String();
    await database.db.update(
      'users',
      {
        'password_hash': await hashPassword(newPassword),
        'updated_at': now,
        'password_changed_at': now,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<void> deleteUser(String userId) async {
    final user = await getUserById(userId);
    if (user.protectedAccount) {
      throw StateError('보호 계정은 삭제할 수 없습니다.');
    }
    await database.db.delete('users', where: 'id = ?', whereArgs: [userId]);
  }

  SeilUser _mapUser(Map<String, Object?> row) {
    return SeilUser(
      id: row['id'] as String,
      username: row['username'] as String,
      name: row['name'] as String,
      role: roleFromDb(row['role'] as String),
      createdAt: parseIso(row['created_at'] as String),
      updatedAt: parseIso(row['updated_at'] as String),
      passwordChangedAt: parseIso(row['password_changed_at'] as String),
      protectedAccount: (row['protected_account'] as int) == 1,
    );
  }
}
