import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../storage/local_database.dart';

class AppSettingsRepository {
  AppSettingsRepository(this.database);

  final LocalDatabase database;

  static const _loginPasswordEnabled = 'login_password_enabled';
  static const _keyboardMacros = 'keyboard_macros_v1';
  static const _lowEndModeEnabled = 'low_end_mode_enabled';
  static const _appLanguageCode = 'app_language_code';
  static const _terminalAttentionNotificationsEnabled =
      'terminal_attention_notifications_enabled';
  static const _terminalAttentionNotificationTailEnabled =
      'terminal_attention_notification_tail_enabled';
  static const _tmuxSessionOrders = 'tmux_session_orders_v1';
  static const _tmuxTabNames = 'tmux_tab_names_v1';
  static const keyboardMacroCount = 9;
  static const systemLanguageCode = 'system';
  static const supportedLanguageCodes = [
    systemLanguageCode,
    'en',
    'ja',
    'ko',
    'zh',
  ];

  Future<bool> isLoginPasswordEnabled() async {
    final rows = await database.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_loginPasswordEnabled],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    return rows.first['value'] == '1';
  }

  Future<void> setLoginPasswordEnabled(bool enabled) {
    return database.db.insert(
      'app_settings',
      {
        'key': _loginPasswordEnabled,
        'value': enabled ? '1' : '0',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isLowEndModeEnabled() async {
    final rows = await database.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_lowEndModeEnabled],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    return rows.first['value'] == '1';
  }

  Future<void> setLowEndModeEnabled(bool enabled) {
    return database.db.insert(
      'app_settings',
      {
        'key': _lowEndModeEnabled,
        'value': enabled ? '1' : '0',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> areTerminalAttentionNotificationsEnabled() async {
    final rows = await database.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_terminalAttentionNotificationsEnabled],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    return rows.first['value'] == '1';
  }

  Future<void> setTerminalAttentionNotificationsEnabled(bool enabled) {
    return database.db.insert(
      'app_settings',
      {
        'key': _terminalAttentionNotificationsEnabled,
        'value': enabled ? '1' : '0',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isTerminalAttentionNotificationTailEnabled() async {
    final rows = await database.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_terminalAttentionNotificationTailEnabled],
      limit: 1,
    );
    if (rows.isEmpty) {
      return true;
    }
    return rows.first['value'] == '1';
  }

  Future<void> setTerminalAttentionNotificationTailEnabled(bool enabled) {
    return database.db.insert(
      'app_settings',
      {
        'key': _terminalAttentionNotificationTailEnabled,
        'value': enabled ? '1' : '0',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> loadAppLanguageCode() async {
    final rows = await database.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_appLanguageCode],
      limit: 1,
    );
    if (rows.isEmpty) {
      return systemLanguageCode;
    }
    final value = rows.first['value'] as String? ?? systemLanguageCode;
    return supportedLanguageCodes.contains(value) ? value : systemLanguageCode;
  }

  Future<void> saveAppLanguageCode(String languageCode) {
    final normalized = supportedLanguageCodes.contains(languageCode)
        ? languageCode
        : systemLanguageCode;
    return database.db.insert(
      'app_settings',
      {
        'key': _appLanguageCode,
        'value': normalized,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> loadKeyboardMacros() async {
    final rows = await database.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_keyboardMacros],
      limit: 1,
    );
    if (rows.isEmpty) {
      return List<String>.filled(keyboardMacroCount, '');
    }
    try {
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! List) {
        return List<String>.filled(keyboardMacroCount, '');
      }
      return List<String>.generate(
        keyboardMacroCount,
        (index) => index < decoded.length ? decoded[index].toString() : '',
      );
    } catch (_) {
      return List<String>.filled(keyboardMacroCount, '');
    }
  }

  Future<void> saveKeyboardMacros(List<String> macros) {
    final normalized = List<String>.generate(
      keyboardMacroCount,
      (index) => index < macros.length ? macros[index] : '',
    );
    return database.db.insert(
      'app_settings',
      {
        'key': _keyboardMacros,
        'value': jsonEncode(normalized),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, List<String>>> loadTmuxSessionOrders() async {
    final rows = await database.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_tmuxSessionOrders],
      limit: 1,
    );
    if (rows.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) {
        return {};
      }
      final orders = <String, List<String>>{};
      for (final entry in decoded.entries) {
        final serverKey = entry.key.toString().trim();
        final value = entry.value;
        if (serverKey.isEmpty || value is! List) {
          continue;
        }
        final names = <String>[];
        for (final item in value) {
          final name = item.toString().trim();
          if (name.isNotEmpty && !names.contains(name)) {
            names.add(name);
          }
        }
        if (names.isNotEmpty) {
          orders[serverKey] = names;
        }
      }
      return orders;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveTmuxSessionOrders(
    Map<String, List<String>> orders,
  ) {
    final normalized = <String, List<String>>{};
    for (final entry in orders.entries) {
      final serverKey = entry.key.trim();
      if (serverKey.isEmpty) {
        continue;
      }
      final names = <String>[];
      for (final item in entry.value) {
        final name = item.trim();
        if (name.isNotEmpty && !names.contains(name)) {
          names.add(name);
        }
      }
      if (names.isNotEmpty) {
        normalized[serverKey] = names;
      }
    }
    return database.db.insert(
      'app_settings',
      {
        'key': _tmuxSessionOrders,
        'value': jsonEncode(normalized),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Map<String, String>>> loadTmuxTabNames() async {
    final rows = await database.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_tmuxTabNames],
      limit: 1,
    );
    if (rows.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(rows.first['value'] as String);
      if (decoded is! Map) {
        return {};
      }
      final names = <String, Map<String, String>>{};
      for (final serverEntry in decoded.entries) {
        final serverKey = serverEntry.key.toString().trim();
        final value = serverEntry.value;
        if (serverKey.isEmpty || value is! Map) {
          continue;
        }
        final serverNames = <String, String>{};
        for (final tabEntry in value.entries) {
          final tmuxName = tabEntry.key.toString().trim();
          final label = tabEntry.value.toString().trim();
          if (tmuxName.isNotEmpty && label.isNotEmpty) {
            serverNames[tmuxName] = label;
          }
        }
        if (serverNames.isNotEmpty) {
          names[serverKey] = serverNames;
        }
      }
      return names;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveTmuxTabNames(
    Map<String, Map<String, String>> names,
  ) {
    final normalized = <String, Map<String, String>>{};
    for (final serverEntry in names.entries) {
      final serverKey = serverEntry.key.trim();
      if (serverKey.isEmpty) {
        continue;
      }
      final serverNames = <String, String>{};
      for (final tabEntry in serverEntry.value.entries) {
        final tmuxName = tabEntry.key.trim();
        final label = tabEntry.value.trim();
        if (tmuxName.isNotEmpty && label.isNotEmpty) {
          serverNames[tmuxName] = label;
        }
      }
      if (serverNames.isNotEmpty) {
        normalized[serverKey] = serverNames;
      }
    }
    return database.db.insert(
      'app_settings',
      {
        'key': _tmuxTabNames,
        'value': jsonEncode(normalized),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
