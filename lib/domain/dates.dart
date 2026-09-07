DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime addCalendarDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);

int calendarDaysBetween(DateTime start, DateTime end) => DateTime.utc(
  end.year,
  end.month,
  end.day,
).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

String dateToIso(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
}

DateTime dateFromIso(String value) {
  final parts = value.split('-');
  if (parts.length != 3) {
    throw FormatException('Invalid date: $value');
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}
