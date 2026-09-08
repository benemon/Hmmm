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
    final rows = await _database.query(
      'settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?)',
      whereArgs: ['require_unlock', 'theme_mode'],
    );
    final values = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    if (!values.containsKey('require_unlock')) {
      await _database.insert('settings', {
        'key': 'require_unlock',
        'value': 'false',
      });
      _requireUnlock = false;
    } else {
      _requireUnlock = values['require_unlock'] == 'true';
    }
    if (!values.containsKey('theme_mode')) {
      await _database.insert('settings', {
        'key': 'theme_mode',
        'value': AppThemeMode.system.name,
      });
      _themeMode = AppThemeMode.system;
    } else {
      _themeMode = AppThemeMode.values.firstWhere(
        (mode) => mode.name == values['theme_mode'],
        orElse: () => AppThemeMode.system,
      );
    }
  }

  Future<void> setRequireUnlock(bool value) async {
    await _database.insert('settings', {
      'key': 'require_unlock',
      'value': value.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _requireUnlock = value;
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode value) async {
    await _database.insert('settings', {
      'key': 'theme_mode',
      'value': value.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _themeMode = value;
    notifyListeners();
  }

  Future<void> refresh() async {
    await load();
    notifyListeners();
  }
}
