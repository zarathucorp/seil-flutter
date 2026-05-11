import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/models.dart';
import 'secure_vault.dart';

class LocalDatabase {
  LocalDatabase(this.vault);

  final SecureVault vault;
  Database? _db;

  Database get db {
    final value = _db;
    if (value == null) {
      throw StateError('Database is not open.');
    }
    return value;
  }

  Future<void> open() async {
    final documents = await getApplicationDocumentsDirectory();
    final path = p.join(documents.path, 'seil_mobile.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    await _ensureSettingsTable(db);
    await _ensureConnectionHistoryLimitColumn(db);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        protected_account INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        password_changed_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE connections (
        id TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL,
        auth_mode TEXT NOT NULL,
        tmux_history_limit INTEGER NOT NULL DEFAULT $defaultTmuxHistoryLimit,
        fingerprint TEXT NOT NULL UNIQUE,
        has_stored_secret INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE trusted_host_keys (
        id TEXT PRIMARY KEY,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        key_type TEXT NOT NULL,
        fingerprint_sha256 TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_verified_at TEXT,
        UNIQUE(host, port, fingerprint_sha256)
      )
    ''');

    await db.execute('''
      CREATE TABLE session_history (
        id TEXT PRIMARY KEY,
        connection_id TEXT,
        host TEXT NOT NULL,
        username TEXT NOT NULL,
        last_path TEXT,
        last_view TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await _ensureSettingsTable(db);
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _ensureConnectionHistoryLimitColumn(db);
    }
  }

  Future<void> _ensureConnectionHistoryLimitColumn(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(connections)');
    final hasColumn =
        columns.any((column) => column['name'] == 'tmux_history_limit');
    if (!hasColumn) {
      await db.execute(
        'ALTER TABLE connections ADD COLUMN tmux_history_limit INTEGER NOT NULL DEFAULT $defaultTmuxHistoryLimit',
      );
    }
  }

  Future<void> _ensureSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }
}

String authModeToDb(AuthMode mode) {
  return switch (mode) {
    AuthMode.password => 'Password',
    AuthMode.privateKey => 'Private Key',
    AuthMode.agent => 'Agent',
  };
}

AuthMode authModeFromDb(String value) {
  return switch (value) {
    'Private Key' => AuthMode.privateKey,
    'Agent' => AuthMode.agent,
    _ => AuthMode.password,
  };
}

String roleToDb(UserRole role) {
  return role == UserRole.admin ? 'admin' : 'user';
}

UserRole roleFromDb(String value) {
  return value == 'admin' ? UserRole.admin : UserRole.user;
}

DateTime parseIso(String value) => DateTime.parse(value);
