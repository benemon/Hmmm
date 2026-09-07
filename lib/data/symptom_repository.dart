import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/validation.dart';

class SymptomRepository extends ChangeNotifier {
  SymptomRepository(this._database);

  final Database _database;

  Future<List<SymptomType>> listTypes() async {
    final rows = await _database.rawQuery('''
      SELECT id, name, builtin
      FROM symptom_types
      ORDER BY id ASC
    ''');
    return rows.map(_symptomTypeFromRow).toList();
  }

  Future<SymptomType> insertType(SymptomType type) async {
    validateSymptomType(type);
    final row = _symptomTypeToRow(type);
    final id = await _database.rawInsert(
      'INSERT INTO symptom_types(name, builtin) VALUES (?, ?)',
      [row['name'], row['builtin']],
    );
    notifyListeners();
    return SymptomType(id: id, name: type.name, builtin: type.builtin);
  }

  Future<List<SymptomEntry>> listEntries() async {
    final rows = await _database.rawQuery('''
      SELECT id, date, type_id, severity, note
      FROM symptom_entries
      ORDER BY date ASC, type_id ASC
    ''');
    return rows.map(_symptomEntryFromRow).toList();
  }

  Future<SymptomEntry?> upsertEntry(
    SymptomEntry entry, {
    required DateTime today,
  }) async {
    if (entry.date.isAfter(dateOnly(today))) {
      throw ArgumentError('Symptom date cannot be in the future.');
    }
    if (entry.severity == 0) {
      await _clearEntry(entry.date, entry.typeId);
      return null;
    }
    validateSymptomEntry(entry, today: today);
    final iso = dateToIso(entry.date);
    await _database.rawInsert(
      '''
      INSERT INTO symptom_entries(date, type_id, severity, note)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(date, type_id) DO UPDATE SET
        severity = excluded.severity,
        note = excluded.note
      ''',
      [iso, entry.typeId, entry.severity, entry.note],
    );
    final rows = await _database.rawQuery(
      '''
      SELECT id, date, type_id, severity, note
      FROM symptom_entries
      WHERE date = ? AND type_id = ?
      LIMIT 1
      ''',
      [iso, entry.typeId],
    );
    notifyListeners();
    return _symptomEntryFromRow(rows.single);
  }

  Future<void> _clearEntry(DateTime date, int typeId) async {
    await _database.rawDelete(
      'DELETE FROM symptom_entries WHERE date = ? AND type_id = ?',
      [dateToIso(date), typeId],
    );
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

SymptomType _symptomTypeFromRow(Map<String, Object?> row) => SymptomType(
  id: row['id'] as int,
  name: row['name'] as String,
  builtin: row['builtin'] == 1,
);

Map<String, Object?> _symptomTypeToRow(SymptomType type) => {
  'name': type.name,
  'builtin': type.builtin ? 1 : 0,
};

SymptomEntry _symptomEntryFromRow(Map<String, Object?> row) => SymptomEntry(
  id: row['id'] as int,
  date: dateFromIso(row['date'] as String),
  typeId: row['type_id'] as int,
  severity: row['severity'] as int,
  note: row['note'] as String?,
);
