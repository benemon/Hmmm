import 'package:flutter/material.dart';

const monthsFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatDate(DateTime date) =>
    '${date.day} ${monthsShort[date.month - 1]} ${date.year}';

String formatDayMonth(DateTime date) =>
    '${date.day} ${monthsShort[date.month - 1]}';

String formatLongDate(DateTime date) =>
    '${date.day} ${monthsFull[date.month - 1]} ${date.year}';

String formatMonthYear(DateTime date) =>
    '${monthsShort[date.month - 1]} ${date.year}';

String formatPeriodRange(DateTime start, DateTime? end) =>
    '${formatDate(start)} – ${end == null ? 'open' : formatDate(end)}';

Future<DateTime?> pickDate(
  BuildContext context,
  DateTime initialDate,
  DateTime today,
) => showDatePicker(
  context: context,
  initialDate: initialDate,
  firstDate: DateTime(1900),
  lastDate: today,
);
