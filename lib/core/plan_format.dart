import 'package:intl/intl.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/preferences.dart';

/// Dates and times as the person chose in Settings (date style, 12/24 h).
class PlanFormat {
  final PlanPreferences prefs;

  const PlanFormat(this.prefs);

  String date(DateTime d) => DateFormat(prefs.dateStyle.pattern, 'en_US').format(d);

  String time(int minutes) {
    final t = DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60);
    return DateFormat(prefs.use24h ? 'HH:mm' : 'h:mm a', 'en_US').format(t);
  }

  String dateTime(DateTime d) =>
      '${date(d)}, ${time(d.hour * 60 + d.minute)}';

  /// "Today", "Tomorrow", "Yesterday", "Wed", or the date.
  String relativeDay(DateTime d, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final diff = dateOnly(d).difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff > 1 && diff < 7) return DateFormat('EEEE', 'en_US').format(d);
    return date(d);
  }

  /// "Today, 3:00 PM" / "Tomorrow" / "12 Nov 2026".
  String due(PlanTask t, {DateTime? now}) {
    final d = t.dueDate;
    if (d == null) return 'No date';
    final m = t.dueMinutes;
    final day = relativeDay(d, now: now);
    return m == null ? day : '$day, ${time(m)}';
  }

  String duration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  static String monthYear(DateTime d) => DateFormat('MMMM yyyy', 'en_US').format(d);
  static String weekdayShort(DateTime d) => DateFormat('EEE', 'en_US').format(d);
  static String dayMonth(DateTime d) => DateFormat('d MMM', 'en_US').format(d);

  static String reminderLabel(int? minutes, {required bool timed}) {
    if (minutes == null) return 'No reminder';
    if (!timed) {
      if (minutes == 0) return 'On the day, 9:00 AM';
      if (minutes == 1440) return 'The day before, 9:00 AM';
      return '${minutes ~/ 1440} days before, 9:00 AM';
    }
    if (minutes == 0) return 'At due time';
    if (minutes < 60) return '$minutes min before';
    if (minutes < 1440) return '${minutes ~/ 60} h before';
    return '${minutes ~/ 1440} day${minutes >= 2880 ? 's' : ''} before';
  }

  static const List<int> timedReminderOptions = [0, 5, 15, 30, 60, 1440];
  static const List<int> allDayReminderOptions = [0, 1440, 2880];
}
