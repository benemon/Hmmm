import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/validation.dart';

class PeriodRepository extends ChangeNotifier {
  PeriodRepository(this._database);

  final Database _database;

  Future<List<Period>> listPeriods() async {
    final rows = await _database.rawQuery('''
      SELECT id, start_date, end_date
      FROM periods
      ORDER BY start_date ASC
    ''');
    return rows.map(_periodFromRow).toList();
  }

  Future<Period> insert(Period period, {required DateTime today}) async {
    validatePeriod(period, await listPeriods(), today: today);
    final row = _periodToRow(period);
    final id = await _database.rawInsert(
      'INSERT INTO periods(start_date, end_date) VALUES (?, ?)',
      [row['start_date'], row['end_date']],
    );
    notifyListeners();
    return Period(id: id, start: period.start, end: period.end);
  }

  Future<void> update(Period period, {required DateTime today}) async {
    final id = period.id;
    if (id == null) {
      throw ArgumentError('Period id is required for update.');
    }
    validatePeriod(period, await listPeriods(), today: today, excludingId: id);
    final row = _periodToRow(period);
    await _database.rawUpdate(
      'UPDATE periods SET start_date = ?, end_date = ? WHERE id = ?',
      [row['start_date'], row['end_date'], id],
    );
    notifyListeners();
  }

  Future<void> delete(int id) async {
    await _database.rawDelete('DELETE FROM periods WHERE id = ?', [id]);
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

Period _periodFromRow(Map<String, Object?> row) => Period(
  id: row['id'] as int,
  start: dateFromIso(row['start_date'] as String),
  end: row['end_date'] == null ? null : dateFromIso(row['end_date'] as String),
);

Map<String, Object?> _periodToRow(Period period) => {
  'start_date': dateToIso(period.start),
  'end_date': period.end == null ? null : dateToIso(period.end!),
};
