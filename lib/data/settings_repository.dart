import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/colours.dart';

enum AppThemeMode { system, light, dark }

class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._database);

  final Database _database;
  bool _requireUnlock = false;
  AppThemeMode _themeMode = AppThemeMode.system;
  String _periodColourId = 'red';
  final Map<int, String> _medicationColourIds = {};

  bool get requireUnlock => _requireUnlock;
  AppThemeMode get themeMode => _themeMode;
  String get periodColourId => _periodColourId;
  Map<int, String> get medicationColourIds =>
      Map.unmodifiable(_medicationColourIds);

  String medicationColourId(int medicationId, int laneIndex) =>
      _medicationColourIds[medicationId] ??
      medicationLaneColourIds[laneIndex >= 0 &&
              laneIndex < medicationLaneColourIds.length - 1
          ? laneIndex
          : medicationLaneColourIds.length - 1];

  Future<void> load() async {
    final rows = await _database.rawQuery(
      '''
      SELECT key, value FROM settings
      WHERE key IN (?, ?, ?) OR key GLOB 'colour_medication_[0-9]*'
      ''',
      ['require_unlock', 'theme_mode', 'colour_period'],
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
    _periodColourId = _knownColour(values['colour_period']) ?? 'red';
    _medicationColourIds.clear();
    for (final entry in values.entries) {
      final match = _medicationColourKey.firstMatch(entry.key);
      final id = match == null ? null : int.tryParse(match.group(1)!);
      final colour = _knownColour(entry.value);
      if (id != null && colour != null) _medicationColourIds[id] = colour;
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

  Future<void> setPeriodColour(String swatchId) async {
    await _write('colour_period', swatchId);
    _periodColourId = swatchId;
    notifyListeners();
  }

  Future<void> setMedicationColour(int medicationId, String swatchId) async {
    await _write('colour_medication_$medicationId', swatchId);
    _medicationColourIds[medicationId] = swatchId;
    notifyListeners();
  }

  Future<void> clearMedicationColour(int medicationId) async {
    await _database.rawDelete('DELETE FROM settings WHERE key = ?', [
      'colour_medication_$medicationId',
    ]);
    _medicationColourIds.remove(medicationId);
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

final _medicationColourKey = RegExp(r'^colour_medication_(\d+)$');

String? _knownColour(String? value) =>
    value != null && bandColourIds.contains(value) ? value : null;
