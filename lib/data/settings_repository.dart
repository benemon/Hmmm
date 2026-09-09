import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

enum AppThemeMode { system, light, dark }

class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._database);

  final Database _database;
  bool _requireUnlock = false;
  AppThemeMode _themeMode = AppThemeMode.system;

  bool get requireUnlock => _requireUnlock;
  AppThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    final rows = await _database.rawQuery(
      'SELECT key, value FROM settings WHERE key IN (?, ?)',
      ['require_unlock', 'theme_mode'],
    );
    final values = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    if (!values.containsKey('require_unlock')) {
      await _write('require_unlock', 'false');
      _requireUnlock = false;
    } else {
      _requireUnlock = values['require_unlock'] == 'true';
    }
    if (!values.containsKey('theme_mode')) {
      await _write('theme_mode', AppThemeMode.system.name);
      _themeMode = AppThemeMode.system;
    } else {
      _themeMode = AppThemeMode.values.firstWhere(
        (mode) => mode.name == values['theme_mode'],
        orElse: () => AppThemeMode.system,
      );
    }
  }

  Future<void> setRequireUnlock(bool value) async {
    await _write('require_unlock', value.toString());
    _requireUnlock = value;
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode value) async {
    await _write('theme_mode', value.name);
    _themeMode = value;
    notifyListeners();
  }

  Future<void> refresh() async {
    await load();
    notifyListeners();
  }

  Future<void> _write(String key, String value) async {
    await _database.rawInsert(
      '''
      INSERT INTO settings(key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      [key, value],
    );
  }
}
