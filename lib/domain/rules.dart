import 'package:omni_plan/domain/models.dart';

/// Progress as done / total. [fraction] is null when there is nothing to
/// measure, so screens show "No tasks yet" instead of a misleading 0 %.
class Progress {
  final int done;
  final int total;

  const Progress(this.done, this.total);

  static const empty = Progress(0, 0);

  double? get fraction => total == 0 ? null : done / total;
  int? get percent => total == 0 ? null : (done * 100 / total).round();
  int get remaining => total - done;

  String get label => total == 0 ? 'No tasks yet' : '$done of $total done';

  Progress operator +(Progress o) => Progress(done + o.done, total + o.total);
}

/// Progress rule, used everywhere a percentage is shown:
/// every task (subtasks included) that is not archived counts once; a task
/// counts as done only when its status is Done. Checklist items do not count
/// towards project progress; they show on their own task.
Progress progressOf(Iterable<PlanTask> tasks) {
  var done = 0;
  var total = 0;
  for (final t in tasks) {
    if (t.isArchived) continue;
    total++;
    if (t.isDone) done++;
  }
  return Progress(done, total);
}

/// Milestone progress for a project: done milestones / milestones.
Progress milestoneProgress(Iterable<Milestone> milestones) {
  final list = milestones.toList();
  return Progress(list.where((m) => m.isDone).length, list.length);
}

// --- dependencies ---

/// Whether adding "[taskId] depends on [dependencyId]" would make a cycle,
/// given the existing dependencies in [dependsOn] (task id -> ids it depends
/// on). Dependencies form a directed acyclic graph.
bool wouldCreateCycle(
  String taskId,
  String dependencyId,
  Map<String, List<String>> dependsOn,
) {
  if (taskId == dependencyId) return true;
  final seen = <String>{};
  final stack = [dependencyId];
  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    if (current == taskId) return true;
    if (!seen.add(current)) continue;
    stack.addAll(dependsOn[current] ?? const []);
  }
  return false;
}

// --- filtering and sorting ---

enum TaskQuick {
  all('All'),
  today('Today'),
  upcoming('Upcoming'),
  overdue('Overdue'),
  noDate('No date'),
  inbox('No project'),
  completed('Completed');

  final String label;
  const TaskQuick(this.label);
}

enum TaskSort {
  smart('Smart (due date, then priority)'),
  dueDate('Due date'),
  priority('Priority'),
  created('Newest first'),
  updated('Recently updated'),
  title('Title A–Z');

  final String label;
  const TaskSort(this.label);
}

class TaskFilter {
  final TaskQuick quick;
  final String query;
  final Set<String> projectIds;
  final Set<Priority> priorities;
  final Set<TaskStatus> statuses;
  final Set<String> tags;
  final TaskSort sort;

  /// Include subtasks as their own rows.
  final bool showSubtasks;

  const TaskFilter({
    this.quick = TaskQuick.all,
    this.query = '',
    this.projectIds = const {},
    this.priorities = const {},
    this.statuses = const {},
    this.tags = const {},
    this.sort = TaskSort.smart,
    this.showSubtasks = false,
  });

  bool get hasAdvanced =>
      projectIds.isNotEmpty ||
      priorities.isNotEmpty ||
      statuses.isNotEmpty ||
      tags.isNotEmpty ||
      sort != TaskSort.smart ||
      showSubtasks;

  TaskFilter copyWith({
    TaskQuick? quick,
    String? query,
    Set<String>? projectIds,
    Set<Priority>? priorities,
    Set<TaskStatus>? statuses,
    Set<String>? tags,
    TaskSort? sort,
    bool? showSubtasks,
  }) => TaskFilter(
    quick: quick ?? this.quick,
    query: query ?? this.query,
    projectIds: projectIds ?? this.projectIds,
    priorities: priorities ?? this.priorities,
    statuses: statuses ?? this.statuses,
    tags: tags ?? this.tags,
    sort: sort ?? this.sort,
    showSubtasks: showSubtasks ?? this.showSubtasks,
  );

  TaskFilter cleared() => TaskFilter(quick: quick, query: query);

  /// Upcoming = due within the next [upcomingDays] days, after today.
  static const int upcomingDays = 7;

  bool matches(PlanTask t, DateTime now, {String Function(PlanTask)? projectName}) {
    if (t.isArchived) return false;
    // Subtasks show under their parent, except in the date views (Today,
    // Upcoming, Overdue), where a subtask with a date is work on that date.
    final dateView =
        quick == TaskQuick.today ||
        quick == TaskQuick.upcoming ||
        quick == TaskQuick.overdue;
    if (!showSubtasks && t.isSubtask && !dateView) return false;
    final today = dateOnly(now);
    switch (quick) {
      case TaskQuick.all:
        if (t.isDone && statuses.isEmpty) return false;
      case TaskQuick.today:
        if (t.isDone) return false;
        final due = t.dueDate;
        if (due == null || dateOnly(due).isAfter(today)) return false;
      case TaskQuick.upcoming:
        if (t.isDone) return false;
        final due = t.dueDate;
        if (due == null) return false;
        final d = dateOnly(due);
        if (!d.isAfter(today) ||
            d.isAfter(today.add(const Duration(days: upcomingDays)))) {
          return false;
        }
      case TaskQuick.overdue:
        if (!t.isOverdue(now)) return false;
      case TaskQuick.noDate:
        if (t.isDone || t.dueDate != null) return false;
      case TaskQuick.inbox:
        if (t.isDone || t.projectId != null) return false;
      case TaskQuick.completed:
        if (!t.isDone) return false;
    }
    if (projectIds.isNotEmpty && !projectIds.contains(t.projectId ?? '')) {
      return false;
    }
    if (priorities.isNotEmpty && !priorities.contains(t.priority)) return false;
    if (statuses.isNotEmpty && !statuses.contains(t.status)) return false;
    if (tags.isNotEmpty && !t.tags.any(tags.contains)) return false;
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = [
        t.title,
        t.description,
        t.notes,
        ...t.tags,
        projectName?.call(t) ?? '',
      ].join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }
}

int compareTasks(PlanTask a, PlanTask b, TaskSort sort) {
  int byDue() {
    final da = a.dueAt, db = b.dueAt;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  int byPriority() => b.priority.index.compareTo(a.priority.index);

  switch (sort) {
    case TaskSort.smart:
      final d = byDue();
      if (d != 0) return d;
      final p = byPriority();
      if (p != 0) return p;
      return a.position.compareTo(b.position);
    case TaskSort.dueDate:
      final d = byDue();
      return d != 0 ? d : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    case TaskSort.priority:
      final p = byPriority();
      return p != 0 ? p : byDue();
    case TaskSort.created:
      return b.createdAt.compareTo(a.createdAt);
    case TaskSort.updated:
      return b.updatedAt.compareTo(a.updatedAt);
    case TaskSort.title:
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }
}

enum ProjectFilter {
  all('All'),
  planning('Planning'),
  inProgress('In progress'),
  onHold('On hold'),
  completed('Completed'),
  archived('Archived');

  final String label;
  const ProjectFilter(this.label);

  bool matches(Project p) {
    switch (this) {
      case ProjectFilter.all:
        return !p.isArchived;
      case ProjectFilter.planning:
        return !p.isArchived &&
            (p.status == ProjectStatus.planning ||
                p.status == ProjectStatus.notStarted);
      case ProjectFilter.inProgress:
        return !p.isArchived && p.status == ProjectStatus.inProgress;
      case ProjectFilter.onHold:
        return !p.isArchived && p.status == ProjectStatus.onHold;
      case ProjectFilter.completed:
        return !p.isArchived && p.status == ProjectStatus.completed;
      case ProjectFilter.archived:
        return p.isArchived;
    }
  }
}

enum ProjectSort {
  updated('Recently updated'),
  dueDate('Due date'),
  created('Creation date'),
  name('Name A–Z'),
  status('Status'),
  priority('Priority'),
  category('Category');

  final String label;
  const ProjectSort(this.label);
}

int compareProjects(Project a, Project b, ProjectSort sort) {
  switch (sort) {
    case ProjectSort.updated:
      return b.updatedAt.compareTo(a.updatedAt);
    case ProjectSort.dueDate:
      final da = a.dueDate, db = b.dueDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    case ProjectSort.created:
      return b.createdAt.compareTo(a.createdAt);
    case ProjectSort.name:
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    case ProjectSort.status:
      return a.status.index.compareTo(b.status.index);
    case ProjectSort.priority:
      return b.priority.index.compareTo(a.priority.index);
    case ProjectSort.category:
      return a.category.toLowerCase().compareTo(b.category.toLowerCase());
  }
}
