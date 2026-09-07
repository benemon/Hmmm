import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._database);

  final Database _database;
  bool _requireUnlock = false;

  bool get requireUnlock => _requireUnlock;

  Future<void> load() async {
    final rows = await _database.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['require_unlock'],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _database.insert('settings', {
        'key': 'require_unlock',
        'value': 'false',
      });
      _requireUnlock = false;
    } else {
      _requireUnlock = rows.single['value'] == 'true';
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

  Future<void> refresh() async {
    await load();
    notifyListeners();
  }
}
