import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';

// Every entity is stored as one JSON object, so the on-device format stays
// readable, a damaged entry can be skipped on its own, and a backup is the
// same JSON. Dates without a time are kept as "yyyy-MM-dd" strings so a
// change of time zone never moves a due date to another day.

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _iso(DateTime? d) => d?.toIso8601String();

/// Calendar day only (no time).
String? dayKey(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseDay(Object? v) {
  if (v is! String || v.length < 10) return null;
  final d = DateTime.tryParse(v.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

// --- shared enums ---

enum Priority {
  none('No priority', Color(0xFF8A9499)),
  low('Low', OmniDesignTokens.categoryConverters),
  medium('Medium', OmniDesignTokens.accentAmber),
  high('High', Color(0xFFE0523F)),
  urgent('Urgent', Color(0xFFB3261E));

  final String label;
  final Color color;
  const Priority(this.label, this.color);

  static Priority parse(Object? v, [Priority f = Priority.none]) =>
      _enum(values, v, f);
}

enum TaskStatus {
  todo('To do', Icons.radio_button_unchecked_rounded, Color(0xFF5F6368)),
  inProgress('In progress', Icons.timelapse_rounded, OmniDesignTokens.primary),
  onHold('On hold', Icons.pause_circle_outline_rounded, OmniDesignTokens.accentAmber),
  done('Done', Icons.check_circle_rounded, OmniDesignTokens.success);

  final String label;
  final IconData icon;
  final Color color;
  const TaskStatus(this.label, this.icon, this.color);

  static TaskStatus parse(Object? v, [TaskStatus f = TaskStatus.todo]) =>
      _enum(values, v, f);
}

/// The lifecycle of a project. "Archived" is not a status: archiving keeps
/// the status the project had, so restoring puts it back exactly.
enum ProjectStatus {
  planning('Planning', OmniDesignTokens.categoryNfc),
  notStarted('Not started', Color(0xFF5F6368)),
  inProgress('In progress', OmniDesignTokens.primary),
  onHold('On hold', OmniDesignTokens.accentAmber),
  completed('Completed', OmniDesignTokens.success);

  final String label;
  final Color color;
  const ProjectStatus(this.label, this.color);

  bool get isActive => this != completed;

  static ProjectStatus parse(Object? v) =>
      _enum(values, v, ProjectStatus.planning);
}

enum GoalStatus {
  active('Active', OmniDesignTokens.primary),
  completed('Completed', OmniDesignTokens.success);

  final String label;
  final Color color;
  const GoalStatus(this.label, this.color);

  static GoalStatus parse(Object? v) => _enum(values, v, GoalStatus.active);
}

/// Icons a project or goal can carry. Stored by key, never by code point, so
/// they survive icon-font changes.
const Map<String, IconData> planIcons = {
  'folder': Icons.folder_rounded,
  'rocket': Icons.rocket_launch_rounded,
  'school': Icons.school_rounded,
  'work': Icons.work_rounded,
  'code': Icons.code_rounded,
  'brush': Icons.brush_rounded,
  'campaign': Icons.campaign_rounded,
  'event': Icons.event_rounded,
  'flight': Icons.flight_takeoff_rounded,
  'home': Icons.home_rounded,
  'fitness': Icons.fitness_center_rounded,
  'store': Icons.storefront_rounded,
  'book': Icons.menu_book_rounded,
  'flag': Icons.flag_rounded,
  'star': Icons.star_rounded,
  'heart': Icons.favorite_rounded,
  'video': Icons.videocam_rounded,
  'groups': Icons.groups_rounded,
  'savings': Icons.savings_rounded,
  'build': Icons.build_rounded,
  'celebration': Icons.celebration_rounded,
  'laptop': Icons.laptop_mac_rounded,
};

IconData planIcon(String key) => planIcons[key] ?? Icons.folder_rounded;

/// Project and goal colours: the Omni category accents, nothing new.
const List<Color> planColors = [
  OmniDesignTokens.primary,
  OmniDesignTokens.categoryConverters,
  OmniDesignTokens.categoryNfc,
  OmniDesignTokens.categoryText,
  OmniDesignTokens.categoryLinks,
  OmniDesignTokens.categoryFiles,
  OmniDesignTokens.categoryBusiness,
  OmniDesignTokens.categoryCalculator,
  OmniDesignTokens.categoryDevice,
  OmniDesignTokens.categoryDeveloper,
];

/// Project categories, matching the template catalogue's sections.
const List<String> planCategories = [
  'Personal',
  'Academic',
  'Work & Career',
  'Freelance',
  'Business',
  'Project Management',
  'Marketing & Content',
  'Events',
  'Goals & Habits',
  'Travel & Life Admin',
];

// --- project ---

class Project {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int color;
  final ProjectStatus status;
  final Priority priority;
  final String category;
  final DateTime? startDate;
  final DateTime? dueDate;
  final String? goalId;
  final String notes;

  /// Links, references and other resources, one per line.
  final List<String> resources;
  final String? templateId;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final DateTime lastOpenedAt;

  const Project({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = 'folder',
    this.color = 0xFF1FC6C1,
    this.status = ProjectStatus.planning,
    this.priority = Priority.none,
    this.category = '',
    this.startDate,
    this.dueDate,
    this.goalId,
    this.notes = '',
    this.resources = const [],
    this.templateId,
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
    required this.lastOpenedAt,
  });

  bool get isArchived => archivedAt != null;
  Color get colorValue => Color(color);
  IconData get iconData => planIcon(icon);

  Project copyWith({
    String? name,
    String? description,
    String? icon,
    int? color,
    ProjectStatus? status,
    Priority? priority,
    String? category,
    DateTime? startDate,
    bool clearStart = false,
    DateTime? dueDate,
    bool clearDue = false,
    String? goalId,
    bool clearGoal = false,
    String? notes,
    List<String>? resources,
    bool? favorite,
    DateTime? updatedAt,
    DateTime? archivedAt,
    bool clearArchived = false,
    DateTime? lastOpenedAt,
  }) => Project(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    category: category ?? this.category,
    startDate: clearStart ? null : (startDate ?? this.startDate),
    dueDate: clearDue ? null : (dueDate ?? this.dueDate),
    goalId: clearGoal ? null : (goalId ?? this.goalId),
    notes: notes ?? this.notes,
    resources: resources ?? this.resources,
    templateId: templateId,
    favorite: favorite ?? this.favorite,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'color': color,
    'status': status.name,
    'priority': priority.name,
    'category': category,
    'startDate': dayKey(startDate),
    'dueDate': dayKey(dueDate),
    'goalId': goalId,
    'notes': notes,
    'resources': resources,
    'templateId': templateId,
    'favorite': favorite,
    'createdAt': _iso(createdAt),
    'updatedAt': _iso(updatedAt),
    'archivedAt': _iso(archivedAt),
    'lastOpenedAt': _iso(lastOpenedAt),
  };

  factory Project.fromJson(Map<String, dynamic> j) {
    final created = _date(j['createdAt']) ?? DateTime.now();
    return Project(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? 'Untitled project',
      description: (j['description'] as String?) ?? '',
      icon: (j['icon'] as String?) ?? 'folder',
      color: (j['color'] as int?) ?? 0xFF1FC6C1,
      status: ProjectStatus.parse(j['status']),
      priority: Priority.parse(j['priority']),
      category: (j['category'] as String?) ?? '',
      startDate: parseDay(j['startDate']),
      dueDate: parseDay(j['dueDate']),
      goalId: _str(j['goalId']),
      notes: (j['notes'] as String?) ?? '',
      resources: [
        for (final r in (j['resources'] as List? ?? const []))
          if (r is String && r.trim().isNotEmpty) r,
      ],
      templateId: _str(j['templateId']),
      favorite: j['favorite'] == true,
      createdAt: created,
      updatedAt: _date(j['updatedAt']) ?? created,
      archivedAt: _date(j['archivedAt']),
      lastOpenedAt: _date(j['lastOpenedAt']) ?? created,
    );
  }
}

class ProjectSection {
  final String id;
  final String projectId;
  final String name;
  final int position;

  const ProjectSection({
    required this.id,
    required this.projectId,
    required this.name,
    this.position = 0,
  });

  ProjectSection copyWith({String? name, int? position}) => ProjectSection(
    id: id,
    projectId: projectId,
    name: name ?? this.name,
    position: position ?? this.position,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'name': name,
    'position': position,
  };

  factory ProjectSection.fromJson(Map<String, dynamic> j) => ProjectSection(
    id: j['id'] as String,
    projectId: j['projectId'] as String,
    name: (j['name'] as String?) ?? 'Section',
    position: (j['position'] as int?) ?? 0,
  );
}

// --- task ---

class ChecklistItem {
  final String id;
  final String title;
  final bool done;

  const ChecklistItem({required this.id, required this.title, this.done = false});

  ChecklistItem copyWith({String? title, bool? done}) =>
      ChecklistItem(id: id, title: title ?? this.title, done: done ?? this.done);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? '',
    done: j['done'] == true,
  );
}

enum RecurrenceFrequency {
  daily('Daily', 'day'),
  weekly('Weekly', 'week'),
  monthly('Monthly', 'month'),
  yearly('Yearly', 'year');

  final String label;
  final String unit;
  const RecurrenceFrequency(this.label, this.unit);
}

/// How a task repeats. Policy: a recurring task needs a due date. Completing
/// it creates the next occurrence (same details, checklist reset) with the
/// next due date, and the completed one keeps no recurrence of its own.
class Recurrence {
  final RecurrenceFrequency frequency;
  final int interval;

  /// ISO weekdays (1 = Monday) for weekly rules; empty = the due date's day.
  final List<int> weekdays;
  final DateTime? endDate;

  const Recurrence({
    required this.frequency,
    this.interval = 1,
    this.weekdays = const [],
    this.endDate,
  });

  String get summary {
    final every = interval == 1
        ? frequency.label
        : 'Every $interval ${frequency.unit}s';
    if (frequency == RecurrenceFrequency.weekly && weekdays.isNotEmpty) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final days = (weekdays.toList()..sort()).map((d) => names[d - 1]);
      return '$every on ${days.join(', ')}';
    }
    return every;
  }

  /// The first due date after [from] that this rule produces, or null when
  /// the rule has ended.
  DateTime? next(DateTime from) {
    final base = dateOnly(from);
    DateTime candidate;
    switch (frequency) {
      case RecurrenceFrequency.daily:
        candidate = DateTime(base.year, base.month, base.day + interval);
      case RecurrenceFrequency.weekly:
        if (weekdays.isEmpty) {
          candidate = DateTime(base.year, base.month, base.day + 7 * interval);
        } else {
          final days = weekdays.toSet();
          // Later chosen days this week first, then the chosen days of the
          // week [interval] weeks on.
          final monday = DateTime.utc(base.year, base.month, base.day - base.weekday + 1);
          DateTime? found;
          for (var i = 1; i <= 7 * (interval + 1); i++) {
            final d = DateTime(base.year, base.month, base.day + i);
            final week = DateTime.utc(d.year, d.month, d.day - d.weekday + 1)
                    .difference(monday)
                    .inDays ~/
                7;
            if (days.contains(d.weekday) && (week == 0 || week == interval)) {
              found = d;
              break;
            }
          }
          candidate =
              found ?? DateTime(base.year, base.month, base.day + 7 * interval);
        }
      case RecurrenceFrequency.monthly:
        candidate = _addMonths(base, interval);
      case RecurrenceFrequency.yearly:
        candidate = _addMonths(base, 12 * interval);
    }
    final end = endDate;
    if (end != null && candidate.isAfter(dateOnly(end))) return null;
    return candidate;
  }

  static DateTime _addMonths(DateTime d, int months) {
    final m = d.month - 1 + months;
    final year = d.year + m ~/ 12;
    final month = m % 12 + 1;
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, d.day > last ? last : d.day);
  }

  Map<String, dynamic> toJson() => {
    'frequency': frequency.name,
    'interval': interval,
    'weekdays': weekdays,
    'endDate': dayKey(endDate),
  };

  static Recurrence? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final freq = _enum<RecurrenceFrequency>(
      RecurrenceFrequency.values,
      raw['frequency'],
      RecurrenceFrequency.weekly,
    );
    final interval = raw['interval'];
    return Recurrence(
      frequency: freq,
      interval: interval is int && interval > 0 ? interval : 1,
      weekdays: [
        for (final d in (raw['weekdays'] as List? ?? const []))
          if (d is int && d >= 1 && d <= 7) d,
      ],
      endDate: parseDay(raw['endDate']),
    );
  }
}

class PlanTask {
  final String id;
  final String title;
  final String description;
  final String? projectId;
  final String? sectionId;
  final String? parentId;
  final String? milestoneId;
  final TaskStatus status;
  final Priority priority;
  final DateTime? startDate;
  final DateTime? dueDate;

  /// Minutes after midnight, when the task is due at a time of day.
  final int? dueMinutes;
  final int? estimateMinutes;
  final List<String> tags;
  final List<ChecklistItem> checklist;
  final String notes;
  final Recurrence? recurrence;

  /// Minutes before the due moment to remind; null = no reminder.
  final int? reminderMinutes;

  /// Tasks that must be done before this one ("depends on").
  final List<String> dependsOn;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? archivedAt;
  final DateTime lastOpenedAt;

  const PlanTask({
    required this.id,
    required this.title,
    this.description = '',
    this.projectId,
    this.sectionId,
    this.parentId,
    this.milestoneId,
    this.status = TaskStatus.todo,
    this.priority = Priority.none,
    this.startDate,
    this.dueDate,
    this.dueMinutes,
    this.estimateMinutes,
    this.tags = const [],
    this.checklist = const [],
    this.notes = '',
    this.recurrence,
    this.reminderMinutes,
    this.dependsOn = const [],
    this.position = 0,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.archivedAt,
    required this.lastOpenedAt,
  });

  bool get isDone => status == TaskStatus.done;
  bool get isArchived => archivedAt != null;
  bool get isSubtask => parentId != null;

  /// The moment the task is due: the due time, or the end of the due day.
  DateTime? get dueAt {
    final d = dueDate;
    if (d == null) return null;
    final m = dueMinutes;
    return m == null
        ? DateTime(d.year, d.month, d.day, 23, 59)
        : DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  /// When the reminder fires: [reminderMinutes] before the due time, or before
  /// 09:00 on the due day for an all-day task (0 = that morning, 1440 = the
  /// morning before).
  DateTime? get reminderAt {
    final d = dueDate;
    final r = reminderMinutes;
    if (d == null || r == null) return null;
    final base = dueMinutes == null
        ? DateTime(d.year, d.month, d.day, 9)
        : dueAt!;
    return base.subtract(Duration(minutes: r));
  }

  bool isOverdue(DateTime now) {
    if (isDone || isArchived) return false;
    final due = dueDate;
    if (due == null) return false;
    if (dueMinutes == null) return dateOnly(due).isBefore(dateOnly(now));
    return dueAt!.isBefore(now);
  }

  bool isDueOn(DateTime day) {
    final d = dueDate;
    return d != null &&
        d.year == day.year &&
        d.month == day.month &&
        d.day == day.day;
  }

  int get checklistDone => checklist.where((c) => c.done).length;

  PlanTask copyWith({
    String? title,
    String? description,
    String? projectId,
    bool clearProject = false,
    String? sectionId,
    bool clearSection = false,
    String? parentId,
    bool clearParent = false,
    String? milestoneId,
    bool clearMilestone = false,
    TaskStatus? status,
    Priority? priority,
    DateTime? startDate,
    bool clearStart = false,
    DateTime? dueDate,
    bool clearDue = false,
    int? dueMinutes,
    bool clearDueTime = false,
    int? estimateMinutes,
    bool clearEstimate = false,
    List<String>? tags,
    List<ChecklistItem>? checklist,
    String? notes,
    Recurrence? recurrence,
    bool clearRecurrence = false,
    int? reminderMinutes,
    bool clearReminder = false,
    List<String>? dependsOn,
    int? position,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompleted = false,
    DateTime? archivedAt,
    bool clearArchived = false,
    DateTime? lastOpenedAt,
  }) => PlanTask(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    projectId: clearProject ? null : (projectId ?? this.projectId),
    sectionId: clearSection ? null : (sectionId ?? this.sectionId),
    parentId: clearParent ? null : (parentId ?? this.parentId),
    milestoneId: clearMilestone ? null : (milestoneId ?? this.milestoneId),
    status: status ?? this.status,
    priority: priority ?? this.priority,
    startDate: clearStart ? null : (startDate ?? this.startDate),
    dueDate: clearDue ? null : (dueDate ?? this.dueDate),
    dueMinutes: clearDueTime || clearDue ? null : (dueMinutes ?? this.dueMinutes),
    estimateMinutes: clearEstimate ? null : (estimateMinutes ?? this.estimateMinutes),
    tags: tags ?? this.tags,
    checklist: checklist ?? this.checklist,
    notes: notes ?? this.notes,
    recurrence: clearRecurrence ? null : (recurrence ?? this.recurrence),
    reminderMinutes: clearReminder ? null : (reminderMinutes ?? this.reminderMinutes),
    dependsOn: dependsOn ?? this.dependsOn,
    position: position ?? this.position,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
    archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'projectId': projectId,
    'sectionId': sectionId,
    'parentId': parentId,
    'milestoneId': milestoneId,
    'status': status.name,
    'priority': priority.name,
    'startDate': dayKey(startDate),
    'dueDate': dayKey(dueDate),
    'dueMinutes': dueMinutes,
    'estimateMinutes': estimateMinutes,
    'tags': tags,
    'checklist': [for (final c in checklist) c.toJson()],
    'notes': notes,
    'recurrence': recurrence?.toJson(),
    'reminderMinutes': reminderMinutes,
    'dependsOn': dependsOn,
    'position': position,
    'createdAt': _iso(createdAt),
    'updatedAt': _iso(updatedAt),
    'completedAt': _iso(completedAt),
    'archivedAt': _iso(archivedAt),
    'lastOpenedAt': _iso(lastOpenedAt),
  };

  factory PlanTask.fromJson(Map<String, dynamic> j) {
    final created = _date(j['createdAt']) ?? DateTime.now();
    int? intOrNull(Object? v) => v is int ? v : null;
    return PlanTask(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? 'Untitled task',
      description: (j['description'] as String?) ?? '',
      projectId: _str(j['projectId']),
      sectionId: _str(j['sectionId']),
      parentId: _str(j['parentId']),
      milestoneId: _str(j['milestoneId']),
      status: TaskStatus.parse(j['status']),
      priority: Priority.parse(j['priority']),
      startDate: parseDay(j['startDate']),
      dueDate: parseDay(j['dueDate']),
      dueMinutes: intOrNull(j['dueMinutes']),
      estimateMinutes: intOrNull(j['estimateMinutes']),
      tags: [
        for (final t in (j['tags'] as List? ?? const []))
          if (t is String && t.trim().isNotEmpty) t.trim(),
      ],
      checklist: [
        for (final c in (j['checklist'] as List? ?? const []))
          if (c is Map) ChecklistItem.fromJson(Map<String, dynamic>.from(c)),
      ],
      notes: (j['notes'] as String?) ?? '',
      recurrence: Recurrence.fromJson(j['recurrence']),
      reminderMinutes: intOrNull(j['reminderMinutes']),
      dependsOn: [
        for (final d in (j['dependsOn'] as List? ?? const []))
          if (d is String && d.isNotEmpty) d,
      ],
      position: (j['position'] as int?) ?? 0,
      createdAt: created,
      updatedAt: _date(j['updatedAt']) ?? created,
      completedAt: _date(j['completedAt']),
      archivedAt: _date(j['archivedAt']),
      lastOpenedAt: _date(j['lastOpenedAt']) ?? created,
    );
  }
}

// --- milestone and goal ---

class Milestone {
  final String id;
  final String projectId;
  final String title;
  final String description;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Milestone({
    required this.id,
    required this.projectId,
    required this.title,
    this.description = '',
    this.dueDate,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDone => completedAt != null;

  bool isOverdue(DateTime now) =>
      !isDone && dueDate != null && dateOnly(dueDate!).isBefore(dateOnly(now));

  Milestone copyWith({
    String? projectId,
    String? title,
    String? description,
    DateTime? dueDate,
    bool clearDue = false,
    DateTime? completedAt,
    bool clearCompleted = false,
    DateTime? updatedAt,
  }) => Milestone(
    id: id,
    projectId: projectId ?? this.projectId,
    title: title ?? this.title,
    description: description ?? this.description,
    dueDate: clearDue ? null : (dueDate ?? this.dueDate),
    completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'description': description,
    'dueDate': dayKey(dueDate),
    'completedAt': _iso(completedAt),
    'createdAt': _iso(createdAt),
    'updatedAt': _iso(updatedAt),
  };

  factory Milestone.fromJson(Map<String, dynamic> j) {
    final created = _date(j['createdAt']) ?? DateTime.now();
    return Milestone(
      id: j['id'] as String,
      projectId: j['projectId'] as String,
      title: (j['title'] as String?) ?? 'Milestone',
      description: (j['description'] as String?) ?? '',
      dueDate: parseDay(j['dueDate']),
      completedAt: _date(j['completedAt']),
      createdAt: created,
      updatedAt: _date(j['updatedAt']) ?? created,
    );
  }
}

class Goal {
  final String id;
  final String title;
  final String description;
  final String category;
  final DateTime? targetDate;
  final GoalStatus status;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? archivedAt;

  const Goal({
    required this.id,
    required this.title,
    this.description = '',
    this.category = '',
    this.targetDate,
    this.status = GoalStatus.active,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.archivedAt,
  });

  bool get isArchived => archivedAt != null;

  bool isOverdue(DateTime now) =>
      status == GoalStatus.active &&
      targetDate != null &&
      dateOnly(targetDate!).isBefore(dateOnly(now));

  Goal copyWith({
    String? title,
    String? description,
    String? category,
    DateTime? targetDate,
    bool clearTarget = false,
    GoalStatus? status,
    String? notes,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompleted = false,
    DateTime? archivedAt,
    bool clearArchived = false,
  }) => Goal(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    targetDate: clearTarget ? null : (targetDate ?? this.targetDate),
    status: status ?? this.status,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: clearCompleted ? null : (completedAt ?? this.completedAt),
    archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'targetDate': dayKey(targetDate),
    'status': status.name,
    'notes': notes,
    'createdAt': _iso(createdAt),
    'updatedAt': _iso(updatedAt),
    'completedAt': _iso(completedAt),
    'archivedAt': _iso(archivedAt),
  };

  factory Goal.fromJson(Map<String, dynamic> j) {
    final created = _date(j['createdAt']) ?? DateTime.now();
    return Goal(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? 'Goal',
      description: (j['description'] as String?) ?? '',
      category: (j['category'] as String?) ?? '',
      targetDate: parseDay(j['targetDate']),
      status: GoalStatus.parse(j['status']),
      notes: (j['notes'] as String?) ?? '',
      createdAt: created,
      updatedAt: _date(j['updatedAt']) ?? created,
      completedAt: _date(j['completedAt']),
      archivedAt: _date(j['archivedAt']),
    );
  }
}

// --- activity and inbox ---

enum EntityKind { task, project, milestone, goal, template, backup }

class ActivityEntry {
  final String id;
  final EntityKind kind;
  final String? entityId;
  final String title;

  /// "Created", "Completed", "Archived"...
  final String action;
  final DateTime at;

  const ActivityEntry({
    required this.id,
    required this.kind,
    this.entityId,
    required this.title,
    required this.action,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'entityId': entityId,
    'title': title,
    'action': action,
    'at': _iso(at),
  };

  factory ActivityEntry.fromJson(Map<String, dynamic> j) => ActivityEntry(
    id: j['id'] as String,
    kind: _enum(EntityKind.values, j['kind'], EntityKind.task),
    entityId: _str(j['entityId']),
    title: (j['title'] as String?) ?? '',
    action: (j['action'] as String?) ?? '',
    at: _date(j['at']) ?? DateTime.now(),
  );
}

enum NoticeType {
  dueToday('Due today', Icons.today_rounded, OmniDesignTokens.primary),
  overdue('Overdue', Icons.warning_amber_rounded, Color(0xFFE0523F)),
  milestone('Milestone', Icons.flag_rounded, OmniDesignTokens.categoryNfc),
  reminder('Reminder', Icons.alarm_rounded, OmniDesignTokens.categoryConverters),
  backup('Backup', Icons.settings_backup_restore_rounded, OmniDesignTokens.categoryCalculator),
  info('Omni Plan', Icons.info_rounded, OmniDesignTokens.primary);

  final String label;
  final IconData icon;
  final Color color;
  const NoticeType(this.label, this.icon, this.color);
}

/// One entry of the in-app notification list. [key] makes generation
/// idempotent: the same overdue task on the same day is listed once.
class PlanNotice {
  final String id;
  final String key;
  final NoticeType type;
  final String title;
  final String body;
  final EntityKind? targetKind;
  final String? targetId;
  final DateTime at;
  final bool read;

  const PlanNotice({
    required this.id,
    required this.key,
    required this.type,
    required this.title,
    required this.body,
    this.targetKind,
    this.targetId,
    required this.at,
    this.read = false,
  });

  PlanNotice markRead() => PlanNotice(
    id: id,
    key: key,
    type: type,
    title: title,
    body: body,
    targetKind: targetKind,
    targetId: targetId,
    at: at,
    read: true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'key': key,
    'type': type.name,
    'title': title,
    'body': body,
    'targetKind': targetKind?.name,
    'targetId': targetId,
    'at': _iso(at),
    'read': read,
  };

  factory PlanNotice.fromJson(Map<String, dynamic> j) => PlanNotice(
    id: j['id'] as String,
    key: (j['key'] as String?) ?? j['id'] as String,
    type: _enum(NoticeType.values, j['type'], NoticeType.info),
    title: (j['title'] as String?) ?? '',
    body: (j['body'] as String?) ?? '',
    targetKind: j['targetKind'] == null
        ? null
        : _enum(EntityKind.values, j['targetKind'], EntityKind.task),
    targetId: _str(j['targetId']),
    at: _date(j['at']) ?? DateTime.now(),
    read: j['read'] == true,
  );
}
