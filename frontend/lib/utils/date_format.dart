const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Nov 4" style. The wireframe stores plan start/end as already-formatted
/// strings, so this is mainly for the New Plan modal where the user picks
/// real DateTimes via a date picker.
String formatMonthDay(DateTime d) => '${_monthShort[d.month - 1]} ${d.day}';

/// "11/04" style for the calendar headers.
String formatSlashDate(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// "Mon" for a 1..7 weekday (Monday=1).
String formatWeekday(int weekday) => _dayShort[weekday - 1];

/// Build the days/dates parallel arrays for a date range, monday-first.
({List<String> days, List<String> dates, String start, String end}) expandRange(
  DateTime from,
  DateTime to,
) {
  final days = <String>[];
  final dates = <String>[];
  var d = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  while (!d.isAfter(end)) {
    days.add(formatWeekday(d.weekday));
    dates.add(formatSlashDate(d));
    d = d.add(const Duration(days: 1));
  }
  return (
    days: days,
    dates: dates,
    start: formatMonthDay(from),
    end: formatMonthDay(to),
  );
}
