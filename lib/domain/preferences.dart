import 'package:omni_plan/domain/models.dart';

enum TaskView {
  list('List'),
  board('Board'),
  agenda('Agenda');

  final String label;
  const TaskView(this.label);
}

enum CalendarView {
  month('Month'),
  week('Week'),
  day('Day'),
  agenda('Agenda');

  final String label;
  const CalendarView(this.label);
}

enum DateStyle {
  dayMonth('20 Oct 2026', 'd MMM yyyy'),
  monthDay('Oct 20, 2026', 'MMM d, yyyy'),
  iso('2026-10-20', 'yyyy-MM-dd');

  final String example;
  final String pattern;
  const DateStyle(this.example, this.pattern);
}

/// Planning preferences. Each one is read where it takes effect: defaults
/// prefill the task and project forms, views open first, the week start
/// lays out the calendar, formats are used by every date shown, and the
/// notification switches decide what is scheduled or listed.
class PlanPreferences {
  final Priority defaultPriority;
  final TaskStatus defaultTaskStatus;
  final TaskView defaultTaskView;
  final bool projectsAsGrid;
  final CalendarView defaultCalendarView;

  /// 1 = Monday, 7 = Sunday.
  final int weekStart;
  final DateStyle dateStyle;
  final bool use24h;

  /// Reminder added to new tasks that have a due date; null = none.
  final int? defaultReminderMinutes;

  final bool notifyReminders;
  final bool notifyDueToday;
  final bool notifyOverdue;
  final bool notifyMilestones;

  /// Days ahead a milestone is announced.
  final int milestoneLeadDays;

  /// What happens to a task's checklist when the task is completed.
  final bool completeChecklistWithTask;

  const PlanPreferences({
    this.defaultPriority = Priority.none,
    this.defaultTaskStatus = TaskStatus.todo,
    this.defaultTaskView = TaskView.list,
    this.projectsAsGrid = false,
    this.defaultCalendarView = CalendarView.month,
    this.weekStart = 1,
    this.dateStyle = DateStyle.dayMonth,
    this.use24h = false,
    this.defaultReminderMinutes,
    this.notifyReminders = true,
    this.notifyDueToday = true,
    this.notifyOverdue = true,
    this.notifyMilestones = true,
    this.milestoneLeadDays = 3,
    this.completeChecklistWithTask = false,
  });

  PlanPreferences copyWith({
    Priority? defaultPriority,
    TaskStatus? defaultTaskStatus,
    TaskView? defaultTaskView,
    bool? projectsAsGrid,
    CalendarView? defaultCalendarView,
    int? weekStart,
    DateStyle? dateStyle,
    bool? use24h,
    int? defaultReminderMinutes,
    bool clearDefaultReminder = false,
    bool? notifyReminders,
    bool? notifyDueToday,
    bool? notifyOverdue,
    bool? notifyMilestones,
    int? milestoneLeadDays,
    bool? completeChecklistWithTask,
  }) => PlanPreferences(
    defaultPriority: defaultPriority ?? this.defaultPriority,
    defaultTaskStatus: defaultTaskStatus ?? this.defaultTaskStatus,
    defaultTaskView: defaultTaskView ?? this.defaultTaskView,
    projectsAsGrid: projectsAsGrid ?? this.projectsAsGrid,
    defaultCalendarView: defaultCalendarView ?? this.defaultCalendarView,
    weekStart: weekStart ?? this.weekStart,
    dateStyle: dateStyle ?? this.dateStyle,
    use24h: use24h ?? this.use24h,
    defaultReminderMinutes: clearDefaultReminder
        ? null
        : (defaultReminderMinutes ?? this.defaultReminderMinutes),
    notifyReminders: notifyReminders ?? this.notifyReminders,
    notifyDueToday: notifyDueToday ?? this.notifyDueToday,
    notifyOverdue: notifyOverdue ?? this.notifyOverdue,
    notifyMilestones: notifyMilestones ?? this.notifyMilestones,
    milestoneLeadDays: milestoneLeadDays ?? this.milestoneLeadDays,
    completeChecklistWithTask:
        completeChecklistWithTask ?? this.completeChecklistWithTask,
  );

  Map<String, dynamic> toJson() => {
    'defaultPriority': defaultPriority.name,
    'defaultTaskStatus': defaultTaskStatus.name,
    'defaultTaskView': defaultTaskView.name,
    'projectsAsGrid': projectsAsGrid,
    'defaultCalendarView': defaultCalendarView.name,
    'weekStart': weekStart,
    'dateStyle': dateStyle.name,
    'use24h': use24h,
    'defaultReminderMinutes': defaultReminderMinutes,
    'notifyReminders': notifyReminders,
    'notifyDueToday': notifyDueToday,
    'notifyOverdue': notifyOverdue,
    'notifyMilestones': notifyMilestones,
    'milestoneLeadDays': milestoneLeadDays,
    'completeChecklistWithTask': completeChecklistWithTask,
  };

  static T _pick<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  factory PlanPreferences.fromJson(Map<String, dynamic> j) {
    const d = PlanPreferences();
    bool flag(String k, bool f) => j[k] is bool ? j[k] as bool : f;
    final week = j['weekStart'];
    final lead = j['milestoneLeadDays'];
    return PlanPreferences(
      defaultPriority: Priority.parse(j['defaultPriority']),
      defaultTaskStatus: TaskStatus.parse(j['defaultTaskStatus']),
      defaultTaskView: _pick(TaskView.values, j['defaultTaskView'], TaskView.list),
      projectsAsGrid: flag('projectsAsGrid', d.projectsAsGrid),
      defaultCalendarView: _pick(
        CalendarView.values,
        j['defaultCalendarView'],
        CalendarView.month,
      ),
      weekStart: week == 7 ? 7 : 1,
      dateStyle: _pick(DateStyle.values, j['dateStyle'], DateStyle.dayMonth),
      use24h: flag('use24h', d.use24h),
      defaultReminderMinutes: j['defaultReminderMinutes'] is int
          ? j['defaultReminderMinutes'] as int
          : null,
      notifyReminders: flag('notifyReminders', true),
      notifyDueToday: flag('notifyDueToday', true),
      notifyOverdue: flag('notifyOverdue', true),
      notifyMilestones: flag('notifyMilestones', true),
      milestoneLeadDays: lead is int && lead >= 0 && lead <= 30 ? lead : 3,
      completeChecklistWithTask: flag('completeChecklistWithTask', false),
    );
  }
}
