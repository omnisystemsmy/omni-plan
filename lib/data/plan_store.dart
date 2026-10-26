import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/preferences.dart';
import 'package:omni_plan/domain/rules.dart';
import 'package:omni_plan/features/templates/template_models.dart';
import 'package:uuid/uuid.dart';

/// What to do with a project's tasks when the project is deleted.
enum ProjectDeleteMode { deleteTasks, keepTasks }

class PlanStoreException implements Exception {
  final String message;
  const PlanStoreException(this.message);
  @override
  String toString() => message;
}

/// The person's planning data, kept in one Hive box on this device.
///
/// The box belongs to one Omni account ([scope] is the Supabase user id, or
/// "local" when the app runs without the backend, as in widget tests), so
/// two accounts on the same phone never see each other's plans. Each record
/// is one JSON string under a typed key (`t:<id>` for a task...), so a
/// damaged entry is skipped without losing the rest.
///
/// Integrity rules kept here and nowhere else:
/// - a subtask belongs to its parent: archiving, restoring, deleting or
///   moving the parent does the same to its subtasks;
/// - deleting a task removes it from every "depends on" list;
/// - deleting a project either deletes its tasks, sections and milestones,
///   or keeps the tasks without a project ([ProjectDeleteMode]);
/// - deleting a milestone or goal unlinks the tasks or projects pointing at
///   it; it never deletes them;
/// - dates are never shifted implicitly: changing a project's dates leaves
///   its tasks alone ([shiftProjectDates] is the explicit action).
class PlanStore extends ChangeNotifier {
  static const Uuid _uuid = Uuid();
  static const int _activityLimit = 300;
  static const int _noticeLimit = 200;

  Box<String>? _box;
  String? _scope;

  final Map<String, Project> _projects = {};
  final Map<String, ProjectSection> _sections = {};
  final Map<String, PlanTask> _tasks = {};
  final Map<String, Milestone> _milestones = {};
  final Map<String, Goal> _goals = {};
  final Map<String, ActivityEntry> _activity = {};
  final Map<String, PlanNotice> _notices = {};
  final Map<String, PlanTemplate> _customTemplates = {};
  PlanPreferences _prefs = const PlanPreferences();
  List<String> _favoriteTemplates = [];
  List<String> _recentTemplates = [];
  List<String> _dismissedNotices = [];

  /// Entries that could not be read when the box was opened.
  int unreadableCount = 0;

  /// Clock, swappable in tests.
  DateTime Function() clock = DateTime.now;

  String? get scope => _scope;
  bool get isOpen => _box != null;

  static String boxNameFor(String scope) {
    final safe = scope.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return 'omni_plan_${safe.isEmpty ? 'local' : safe}';
  }

  /// Opens the data of [scope], closing any other account's data first.
  Future<void> open(String scope) async {
    if (_scope == scope && _box != null) return;
    await close(notify: false);
    final box = await Hive.openBox<String>(boxNameFor(scope));
    _box = box;
    _scope = scope;
    _load(box);
    notifyListeners();
  }

  /// Opens [scope] on an already open [box]. Widget tests pass an in-memory
  /// box here, because their fake clock cannot drive Hive's file I/O.
  @visibleForTesting
  Future<void> openWith(Box<String> box, String scope) async {
    await close(notify: false);
    _box = box;
    _scope = scope;
    _load(box);
    notifyListeners();
  }

  Future<void> close({bool notify = true}) async {
    final box = _box;
    _box = null;
    _scope = null;
    _clearMemory();
    if (box != null && box.isOpen) await box.close();
    if (notify) notifyListeners();
  }

  void _clearMemory() {
    _projects.clear();
    _sections.clear();
    _tasks.clear();
    _milestones.clear();
    _goals.clear();
    _activity.clear();
    _notices.clear();
    _customTemplates.clear();
    _prefs = const PlanPreferences();
    _favoriteTemplates = [];
    _recentTemplates = [];
    _dismissedNotices = [];
    unreadableCount = 0;
  }

  void _load(Box<String> box) {
    for (final key in box.keys) {
      final k = '$key';
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        _apply(k, decoded);
      } catch (e) {
        unreadableCount++;
        debugPrint('[PlanStore] skipped unreadable entry $k: $e');
      }
    }
  }

  /// Puts one stored entry into memory. Shared by loading and restoring.
  void _apply(String key, Object? decoded) {
    Map<String, dynamic> map() => Map<String, dynamic>.from(decoded as Map);
    if (key.startsWith('p:')) {
      final p = Project.fromJson(map());
      _projects[p.id] = p;
    } else if (key.startsWith('s:')) {
      final s = ProjectSection.fromJson(map());
      _sections[s.id] = s;
    } else if (key.startsWith('t:')) {
      final t = PlanTask.fromJson(map());
      _tasks[t.id] = t;
    } else if (key.startsWith('m:')) {
      final m = Milestone.fromJson(map());
      _milestones[m.id] = m;
    } else if (key.startsWith('g:')) {
      final g = Goal.fromJson(map());
      _goals[g.id] = g;
    } else if (key.startsWith('a:')) {
      final a = ActivityEntry.fromJson(map());
      _activity[a.id] = a;
    } else if (key.startsWith('n:')) {
      final n = PlanNotice.fromJson(map());
      _notices[n.id] = n;
    } else if (key.startsWith('ct:')) {
      final t = PlanTemplate.fromJson(map());
      _customTemplates[t.id] = t;
    } else if (key == _kPrefs) {
      _prefs = PlanPreferences.fromJson(map());
    } else if (key == _kFavTemplates) {
      _favoriteTemplates = [for (final v in decoded as List) '$v'];
    } else if (key == _kRecentTemplates) {
      _recentTemplates = [for (final v in decoded as List) '$v'];
    } else if (key == _kDismissed) {
      _dismissedNotices = [for (final v in decoded as List) '$v'];
    }
  }

  static const _kPrefs = 'meta:prefs';
  static const _kFavTemplates = 'meta:favoriteTemplates';
  static const _kRecentTemplates = 'meta:recentTemplates';
  static const _kDismissed = 'meta:dismissedNotices';

  Box<String> get _requireBox {
    final box = _box;
    if (box == null) {
      throw const PlanStoreException('Your plans are not open yet.');
    }
    return box;
  }

  Future<void> _put(String key, Object json) =>
      _requireBox.put(key, jsonEncode(json));

  Future<void> _delete(String key) => _requireBox.delete(key);

  String newId() => _uuid.v4();

  // ---------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------

  PlanPreferences get prefs => _prefs;

  List<Project> get allProjects => _projects.values.toList();
  List<Project> get projects => [
    for (final p in _projects.values)
      if (!p.isArchived) p,
  ];
  List<Project> get activeProjects => [
    for (final p in projects)
      if (p.status.isActive) p,
  ]..sort((a, b) => compareProjects(a, b, ProjectSort.updated));
  List<Project> get archivedProjects => [
    for (final p in _projects.values)
      if (p.isArchived) p,
  ]..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));

  Project? project(String? id) => id == null ? null : _projects[id];
  PlanTask? task(String? id) => id == null ? null : _tasks[id];
  Milestone? milestone(String? id) => id == null ? null : _milestones[id];
  Goal? goal(String? id) => id == null ? null : _goals[id];
  ProjectSection? section(String? id) => id == null ? null : _sections[id];

  List<PlanTask> get allTasks => _tasks.values.toList();

  /// Tasks a person works with: not archived, and not inside an archived
  /// project (archiving a project puts its tasks away with it).
  List<PlanTask> get tasks => [
    for (final t in _tasks.values)
      if (!t.isArchived && !_inArchivedProject(t)) t,
  ];

  bool _inArchivedProject(PlanTask t) =>
      t.projectId != null && (_projects[t.projectId]?.isArchived ?? false);

  List<PlanTask> get archivedTasks => [
    for (final t in _tasks.values)
      if (t.isArchived && !(t.parentId != null && (_tasks[t.parentId]?.isArchived ?? false)))
        t,
  ]..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));

  List<PlanTask> tasksOfProject(String projectId, {bool includeArchived = false}) => [
    for (final t in _tasks.values)
      if (t.projectId == projectId && (includeArchived || !t.isArchived)) t,
  ]..sort((a, b) => compareTasks(a, b, TaskSort.smart));

  List<PlanTask> subtasksOf(String taskId) => [
    for (final t in _tasks.values)
      if (t.parentId == taskId && !t.isArchived) t,
  ]..sort((a, b) => a.position.compareTo(b.position));

  List<ProjectSection> sectionsOf(String projectId) => [
    for (final s in _sections.values)
      if (s.projectId == projectId) s,
  ]..sort((a, b) => a.position.compareTo(b.position));

  List<Milestone> milestonesOf(String projectId) => [
    for (final m in _milestones.values)
      if (m.projectId == projectId) m,
  ]..sort(_compareMilestones);

  static int _compareMilestones(Milestone a, Milestone b) {
    final da = a.dueDate, db = b.dueDate;
    if (da == null && db == null) return a.title.compareTo(b.title);
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  List<Milestone> get milestones => [
    for (final m in _milestones.values)
      if (!(_projects[m.projectId]?.isArchived ?? true)) m,
  ]..sort(_compareMilestones);

  List<Milestone> upcomingMilestones({int days = 30}) {
    final today = dateOnly(clock());
    final limit = today.add(Duration(days: days));
    return [
      for (final m in milestones)
        if (!m.isDone && m.dueDate != null && !m.dueDate!.isAfter(limit)) m,
    ];
  }

  List<PlanTask> tasksOfMilestone(String milestoneId) => [
    for (final t in _tasks.values)
      if (t.milestoneId == milestoneId && !t.isArchived) t,
  ];

  List<Goal> get goals => [
    for (final g in _goals.values)
      if (!g.isArchived) g,
  ]..sort((a, b) {
    final s = a.status.index.compareTo(b.status.index);
    if (s != 0) return s;
    final da = a.targetDate, db = b.targetDate;
    if (da == null && db == null) return a.title.compareTo(b.title);
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });
  List<Goal> get archivedGoals => [
    for (final g in _goals.values)
      if (g.isArchived) g,
  ];

  List<Project> projectsOfGoal(String goalId) => [
    for (final p in _projects.values)
      if (p.goalId == goalId && !p.isArchived) p,
  ];

  Progress projectProgress(String projectId) =>
      progressOf(tasksOfProject(projectId));

  /// Goal progress: the tasks of every linked project, by the same rule as
  /// project progress. A goal with no linked work has no percentage.
  Progress goalProgress(String goalId) {
    var p = Progress.empty;
    for (final project in projectsOfGoal(goalId)) {
      p = p + projectProgress(project.id);
    }
    return p;
  }

  Progress milestoneTaskProgress(String milestoneId) =>
      progressOf(tasksOfMilestone(milestoneId));

  /// The next open milestone of a project.
  Milestone? nextMilestone(String projectId) {
    for (final m in milestonesOf(projectId)) {
      if (!m.isDone) return m;
    }
    return null;
  }

  int overdueCountOf(String projectId) {
    final now = clock();
    return tasksOfProject(projectId).where((t) => t.isOverdue(now)).length;
  }

  /// The tasks [t] depends on that are not done yet. A task is "blocked"
  /// only when this list is not empty.
  List<PlanTask> openDependencies(PlanTask t) => [
    for (final id in t.dependsOn)
      if (_tasks[id] != null && !_tasks[id]!.isDone && !_tasks[id]!.isArchived)
        _tasks[id]!,
  ];

  bool isBlocked(PlanTask t) => !t.isDone && openDependencies(t).isNotEmpty;

  /// Tasks that wait for [t].
  List<PlanTask> dependents(PlanTask t) => [
    for (final other in _tasks.values)
      if (other.dependsOn.contains(t.id) && !other.isArchived) other,
  ];

  Set<String> get allTags => {
    for (final t in tasks) ...t.tags,
  };

  String projectNameOf(PlanTask t) => _projects[t.projectId]?.name ?? '';

  List<PlanTask> filterTasks(TaskFilter filter) {
    final now = clock();
    return [
      for (final t in tasks)
        if (filter.matches(t, now, projectName: projectNameOf)) t,
    ]..sort((a, b) => compareTasks(a, b, filter.sort));
  }

  List<PlanTask> tasksDueOn(DateTime day) => [
    for (final t in tasks)
      if (t.isDueOn(day)) t,
  ]..sort((a, b) => compareTasks(a, b, TaskSort.smart));

  /// Recently opened tasks and projects, newest first.
  List<Object> recentItems({int limit = 5}) {
    final items = <(DateTime, Object)>[
      for (final p in projects) (p.lastOpenedAt, p),
      for (final t in tasks)
        if (t.lastOpenedAt.isAfter(t.createdAt.add(const Duration(seconds: 1))))
          (t.lastOpenedAt, t),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final i in items.take(limit)) i.$2];
  }

  List<ActivityEntry> get activity =>
      _activity.values.toList()..sort((a, b) => b.at.compareTo(a.at));

  List<PlanNotice> get notices =>
      _notices.values.toList()..sort((a, b) => b.at.compareTo(a.at));

  int get unreadNotices => _notices.values.where((n) => !n.read).length;

  // --- templates ---

  List<PlanTemplate> get customTemplates =>
      _customTemplates.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  List<String> get favoriteTemplates => List.unmodifiable(_favoriteTemplates);
  List<String> get recentTemplates => List.unmodifiable(_recentTemplates);
  bool isFavoriteTemplate(String id) => _favoriteTemplates.contains(id);

  Future<void> toggleFavoriteTemplate(String id) async {
    if (!_favoriteTemplates.remove(id)) _favoriteTemplates.add(id);
    await _put(_kFavTemplates, _favoriteTemplates);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Preferences
  // ---------------------------------------------------------------------

  Future<void> updatePrefs(PlanPreferences prefs) async {
    _prefs = prefs;
    await _put(_kPrefs, prefs.toJson());
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Activity
  // ---------------------------------------------------------------------

  Future<void> _log(EntityKind kind, String? id, String title, String action) async {
    final entry = ActivityEntry(
      id: newId(),
      kind: kind,
      entityId: id,
      title: title,
      action: action,
      at: clock(),
    );
    _activity[entry.id] = entry;
    await _put('a:${entry.id}', entry.toJson());
    if (_activity.length > _activityLimit) {
      final old = activity.skip(_activityLimit).toList();
      for (final a in old) {
        _activity.remove(a.id);
        await _delete('a:${a.id}');
      }
    }
  }

  Future<void> clearActivity() async {
    for (final id in _activity.keys.toList()) {
      await _delete('a:$id');
    }
    _activity.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------

  /// A new task with the person's defaults, not stored yet.
  PlanTask draftTask({
    String? projectId,
    String? sectionId,
    String? parentId,
    String? milestoneId,
    DateTime? dueDate,
  }) {
    final now = clock();
    final parent = task(parentId);
    return PlanTask(
      id: newId(),
      title: '',
      projectId: projectId ?? parent?.projectId,
      sectionId: sectionId,
      parentId: parentId,
      milestoneId: milestoneId,
      status: _prefs.defaultTaskStatus == TaskStatus.done
          ? TaskStatus.todo
          : _prefs.defaultTaskStatus,
      priority: _prefs.defaultPriority,
      dueDate: dueDate,
      reminderMinutes: dueDate == null ? null : _prefs.defaultReminderMinutes,
      createdAt: now,
      updatedAt: now,
      lastOpenedAt: now,
    );
  }

  String? validateTask(PlanTask t) {
    if (t.title.trim().isEmpty) return 'Give the task a title.';
    final start = t.startDate, due = t.dueDate;
    if (start != null && due != null && dateOnly(start).isAfter(dateOnly(due))) {
      return 'The start date is after the due date.';
    }
    if (t.recurrence != null && t.dueDate == null) {
      return 'A repeating task needs a due date.';
    }
    if (t.parentId != null && t.parentId == t.id) {
      return 'A task cannot be its own subtask.';
    }
    if (t.projectId != null && _projects[t.projectId] == null) {
      return 'That project no longer exists.';
    }
    return null;
  }

  /// Creates or updates [t]. Moving a task to another project moves its
  /// subtasks too, and drops a section or milestone of the old project.
  Future<PlanTask> saveTask(PlanTask t) async {
    final error = validateTask(t);
    if (error != null) throw PlanStoreException(error);
    final existing = _tasks[t.id];
    final now = clock();
    var next = t.copyWith(title: t.title.trim(), updatedAt: now);
    if (next.sectionId != null && _sections[next.sectionId]?.projectId != next.projectId) {
      next = next.copyWith(clearSection: true);
    }
    if (next.milestoneId != null && _milestones[next.milestoneId]?.projectId != next.projectId) {
      next = next.copyWith(clearMilestone: true);
    }
    if (next.isDone && next.completedAt == null) {
      next = next.copyWith(completedAt: now);
    } else if (!next.isDone && next.completedAt != null) {
      next = next.copyWith(clearCompleted: true);
    }
    if (existing == null && next.parentId == null) {
      next = next.copyWith(position: _nextPosition(next.projectId));
    }
    _tasks[next.id] = next;
    await _put('t:${next.id}', next.toJson());
    if (existing != null && existing.projectId != next.projectId) {
      for (final s in subtasksOf(next.id)) {
        final moved = s.copyWith(
          projectId: next.projectId,
          clearProject: next.projectId == null,
          clearSection: true,
          clearMilestone: true,
          updatedAt: now,
        );
        _tasks[s.id] = moved;
        await _put('t:${s.id}', moved.toJson());
      }
    }
    await _log(
      EntityKind.task,
      next.id,
      next.title,
      existing == null ? (next.isSubtask ? 'Subtask added' : 'Created') : 'Updated',
    );
    await _touchProject(next.projectId);
    notifyListeners();
    return next;
  }

  int _nextPosition(String? projectId) {
    var max = -1;
    for (final t in _tasks.values) {
      if (t.projectId == projectId && t.position > max) max = t.position;
    }
    return max + 1;
  }

  Future<void> _touchProject(String? projectId) async {
    final p = _projects[projectId];
    if (p == null) return;
    final next = p.copyWith(updatedAt: clock());
    _projects[p.id] = next;
    await _put('p:${p.id}', next.toJson());
  }

  Future<void> markTaskOpened(PlanTask t) async {
    final current = _tasks[t.id];
    if (current == null) return;
    final next = current.copyWith(lastOpenedAt: clock());
    _tasks[t.id] = next;
    await _put('t:${t.id}', next.toJson());
  }

  /// Completes or reopens [t]. Completing a repeating task creates its next
  /// occurrence (returned) according to the recurrence policy.
  Future<PlanTask?> setTaskDone(PlanTask t, bool done) async {
    final current = _tasks[t.id] ?? t;
    final now = clock();
    PlanTask? created;
    if (done) {
      var next = current.copyWith(
        status: TaskStatus.done,
        completedAt: now,
        updatedAt: now,
      );
      final rule = current.recurrence;
      if (rule != null && current.dueDate != null) {
        final nextDue = rule.next(current.dueDate!);
        if (nextDue != null) {
          final gap = current.startDate == null
              ? null
              : dateOnly(current.dueDate!).difference(dateOnly(current.startDate!));
          created = current.copyWith(
            status: TaskStatus.todo,
            clearCompleted: true,
            dueDate: nextDue,
            startDate: gap == null ? null : nextDue.subtract(gap),
            clearStart: gap == null,
            checklist: [for (final c in current.checklist) c.copyWith(done: false)],
            updatedAt: now,
          );
          created = PlanTask.fromJson({...created.toJson(), 'id': newId(), 'createdAt': now.toIso8601String(), 'lastOpenedAt': now.toIso8601String()});
        }
        next = next.copyWith(clearRecurrence: true);
      }
      if (_prefs.completeChecklistWithTask) {
        next = next.copyWith(
          checklist: [for (final c in next.checklist) c.copyWith(done: true)],
        );
      }
      _tasks[t.id] = next;
      await _put('t:${t.id}', next.toJson());
      if (created != null) {
        _tasks[created.id] = created;
        await _put('t:${created.id}', created.toJson());
      }
      await _log(EntityKind.task, t.id, current.title, 'Completed');
    } else {
      final next = current.copyWith(
        status: TaskStatus.todo,
        clearCompleted: true,
        updatedAt: now,
      );
      _tasks[t.id] = next;
      await _put('t:${t.id}', next.toJson());
      await _log(EntityKind.task, t.id, current.title, 'Reopened');
    }
    await _touchProject(current.projectId);
    notifyListeners();
    return created;
  }

  Future<void> setTaskStatus(PlanTask t, TaskStatus status) async {
    final current = _tasks[t.id] ?? t;
    if (current.status == status) return;
    if (status == TaskStatus.done) {
      await setTaskDone(current, true);
      return;
    }
    final now = clock();
    final next = current.copyWith(
      status: status,
      clearCompleted: true,
      updatedAt: now,
    );
    _tasks[t.id] = next;
    await _put('t:${t.id}', next.toJson());
    await _log(EntityKind.task, t.id, current.title, 'Moved to ${status.label}');
    await _touchProject(current.projectId);
    notifyListeners();
  }

  /// Changes only the dates of [t] (calendar rescheduling).
  Future<void> rescheduleTask(PlanTask t, DateTime? due, {bool keepTime = true}) async {
    final current = _tasks[t.id] ?? t;
    final next = due == null
        ? current.copyWith(clearDue: true, clearReminder: true, clearRecurrence: true, updatedAt: clock())
        : current.copyWith(
            dueDate: dateOnly(due),
            clearDueTime: !keepTime,
            clearStart: current.startDate != null && dateOnly(current.startDate!).isAfter(dateOnly(due)),
            updatedAt: clock(),
          );
    _tasks[t.id] = next;
    await _put('t:${t.id}', next.toJson());
    await _log(EntityKind.task, t.id, current.title, 'Rescheduled');
    notifyListeners();
  }

  Future<void> toggleChecklistItem(PlanTask t, String itemId) async {
    final current = _tasks[t.id] ?? t;
    final next = current.copyWith(
      checklist: [
        for (final c in current.checklist) c.id == itemId ? c.copyWith(done: !c.done) : c,
      ],
      updatedAt: clock(),
    );
    _tasks[t.id] = next;
    await _put('t:${t.id}', next.toJson());
    notifyListeners();
  }

  /// A copy of [t] (and its subtasks) as a new task, not done.
  Future<PlanTask> duplicateTask(PlanTask t) async {
    final now = clock();
    PlanTask copyOf(PlanTask source, {String? parentId}) => PlanTask.fromJson({
      ...source.toJson(),
      'id': newId(),
      'title': parentId == null ? '${source.title} (copy)' : source.title,
      'parentId': parentId ?? source.parentId,
      'status': TaskStatus.todo.name,
      'completedAt': null,
      'archivedAt': null,
      'dependsOn': <String>[],
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'lastOpenedAt': now.toIso8601String(),
      'checklist': [for (final c in source.checklist) {...c.toJson(), 'done': false, 'id': newId()}],
    });
    final copy = copyOf(t);
    _tasks[copy.id] = copy;
    await _put('t:${copy.id}', copy.toJson());
    for (final s in subtasksOf(t.id)) {
      final sub = copyOf(s, parentId: copy.id);
      _tasks[sub.id] = sub;
      await _put('t:${sub.id}', sub.toJson());
    }
    await _log(EntityKind.task, copy.id, copy.title, 'Duplicated');
    notifyListeners();
    return copy;
  }

  Future<void> archiveTask(PlanTask t) => _setTaskArchived(t, clock());
  Future<void> restoreTask(PlanTask t) => _setTaskArchived(t, null);

  Future<void> _setTaskArchived(PlanTask t, DateTime? at) async {
    final ids = [t.id, ..._descendantIds(t.id)];
    for (final id in ids) {
      final current = _tasks[id];
      if (current == null) continue;
      final next = at == null
          ? current.copyWith(clearArchived: true, updatedAt: clock())
          : current.copyWith(archivedAt: at, updatedAt: clock());
      _tasks[id] = next;
      await _put('t:$id', next.toJson());
    }
    // Restoring a subtask of an archived parent brings it back on its own.
    final restored = _tasks[t.id];
    if (at == null && restored != null && restored.parentId != null &&
        (_tasks[restored.parentId]?.isArchived ?? true)) {
      final detached = restored.copyWith(clearParent: true);
      _tasks[t.id] = detached;
      await _put('t:${t.id}', detached.toJson());
    }
    await _log(EntityKind.task, t.id, t.title, at == null ? 'Restored' : 'Archived');
    notifyListeners();
  }

  List<String> _descendantIds(String id) {
    final out = <String>[];
    final stack = [id];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      for (final t in _tasks.values) {
        if (t.parentId == current) {
          out.add(t.id);
          stack.add(t.id);
        }
      }
    }
    return out;
  }

  int subtaskCount(String taskId) => _descendantIds(taskId).length;

  /// Deletes [t] and its subtasks for good.
  Future<void> deleteTask(PlanTask t) async {
    final ids = {t.id, ..._descendantIds(t.id)};
    for (final id in ids) {
      _tasks.remove(id);
      await _delete('t:$id');
    }
    for (final other in _tasks.values.toList()) {
      if (other.dependsOn.any(ids.contains)) {
        final next = other.copyWith(
          dependsOn: other.dependsOn.where((d) => !ids.contains(d)).toList(),
        );
        _tasks[other.id] = next;
        await _put('t:${other.id}', next.toJson());
      }
    }
    await _log(EntityKind.task, null, t.title, 'Deleted');
    notifyListeners();
  }

  /// Adds "[t] depends on [dependency]". Throws when it would form a cycle
  /// or the tasks are in different projects.
  Future<void> addDependency(PlanTask t, PlanTask dependency) async {
    final current = _tasks[t.id] ?? t;
    if (current.dependsOn.contains(dependency.id)) return;
    if (current.projectId == null || current.projectId != dependency.projectId) {
      throw const PlanStoreException('Dependencies can only link tasks of the same project.');
    }
    final graph = {for (final x in _tasks.values) x.id: x.dependsOn};
    if (wouldCreateCycle(current.id, dependency.id, graph)) {
      throw const PlanStoreException(
        'That would make a loop: the other task already waits for this one.',
      );
    }
    final next = current.copyWith(
      dependsOn: [...current.dependsOn, dependency.id],
      updatedAt: clock(),
    );
    _tasks[t.id] = next;
    await _put('t:${t.id}', next.toJson());
    notifyListeners();
  }

  Future<void> removeDependency(PlanTask t, String dependencyId) async {
    final current = _tasks[t.id] ?? t;
    final next = current.copyWith(
      dependsOn: current.dependsOn.where((d) => d != dependencyId).toList(),
      updatedAt: clock(),
    );
    _tasks[t.id] = next;
    await _put('t:${t.id}', next.toJson());
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Projects and sections
  // ---------------------------------------------------------------------

  Project draftProject() {
    final now = clock();
    return Project(
      id: newId(),
      name: '',
      color: planColors.first.toARGB32(),
      createdAt: now,
      updatedAt: now,
      lastOpenedAt: now,
    );
  }

  String? validateProject(Project p) {
    if (p.name.trim().isEmpty) return 'Give the project a name.';
    final s = p.startDate, d = p.dueDate;
    if (s != null && d != null && s.isAfter(d)) {
      return 'The start date is after the target date.';
    }
    if (p.goalId != null && _goals[p.goalId] == null) {
      return 'That goal no longer exists.';
    }
    return null;
  }

  Future<Project> saveProject(Project p) async {
    final error = validateProject(p);
    if (error != null) throw PlanStoreException(error);
    final existing = _projects[p.id];
    final next = p.copyWith(name: p.name.trim(), updatedAt: clock());
    _projects[next.id] = next;
    await _put('p:${next.id}', next.toJson());
    String action = existing == null ? 'Created' : 'Updated';
    if (existing != null && existing.status != next.status) {
      action = 'Status: ${next.status.label}';
    }
    await _log(EntityKind.project, next.id, next.name, action);
    notifyListeners();
    return next;
  }

  Future<void> markProjectOpened(Project p) async {
    final current = _projects[p.id];
    if (current == null) return;
    final next = current.copyWith(lastOpenedAt: clock());
    _projects[p.id] = next;
    await _put('p:${p.id}', next.toJson());
  }

  Future<void> toggleFavoriteProject(Project p) async {
    final current = _projects[p.id] ?? p;
    final next = current.copyWith(favorite: !current.favorite);
    _projects[p.id] = next;
    await _put('p:${p.id}', next.toJson());
    notifyListeners();
  }

  Future<void> archiveProject(Project p) async {
    final next = (_projects[p.id] ?? p).copyWith(archivedAt: clock(), updatedAt: clock());
    _projects[p.id] = next;
    await _put('p:${p.id}', next.toJson());
    await _log(EntityKind.project, p.id, p.name, 'Archived');
    notifyListeners();
  }

  Future<void> restoreProject(Project p) async {
    final next = (_projects[p.id] ?? p).copyWith(clearArchived: true, updatedAt: clock());
    _projects[p.id] = next;
    await _put('p:${p.id}', next.toJson());
    await _log(EntityKind.project, p.id, p.name, 'Restored');
    notifyListeners();
  }

  Future<void> deleteProject(Project p, ProjectDeleteMode mode) async {
    final tasks = [
      for (final t in _tasks.values)
        if (t.projectId == p.id) t,
    ];
    for (final t in tasks) {
      if (mode == ProjectDeleteMode.deleteTasks) {
        _tasks.remove(t.id);
        await _delete('t:${t.id}');
      } else {
        final next = t.copyWith(
          clearProject: true,
          clearSection: true,
          clearMilestone: true,
          dependsOn: const [],
          updatedAt: clock(),
        );
        _tasks[t.id] = next;
        await _put('t:${t.id}', next.toJson());
      }
    }
    if (mode == ProjectDeleteMode.deleteTasks) {
      final gone = {for (final t in tasks) t.id};
      for (final other in _tasks.values.toList()) {
        if (other.dependsOn.any(gone.contains)) {
          final next = other.copyWith(dependsOn: other.dependsOn.where((d) => !gone.contains(d)).toList());
          _tasks[other.id] = next;
          await _put('t:${other.id}', next.toJson());
        }
      }
    }
    for (final s in sectionsOf(p.id)) {
      _sections.remove(s.id);
      await _delete('s:${s.id}');
    }
    for (final m in milestonesOf(p.id)) {
      _milestones.remove(m.id);
      await _delete('m:${m.id}');
    }
    _projects.remove(p.id);
    await _delete('p:${p.id}');
    await _log(EntityKind.project, null, p.name, 'Deleted');
    notifyListeners();
  }

  /// A full copy of [p]: sections, tasks (reset to not done), subtasks,
  /// milestones (not done) and the dependencies between the copied tasks.
  Future<Project> duplicateProject(Project p) async {
    final now = clock();
    final copy = Project.fromJson({
      ...p.toJson(),
      'id': newId(),
      'name': '${p.name} (copy)',
      'favorite': false,
      'archivedAt': null,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'lastOpenedAt': now.toIso8601String(),
    });
    _projects[copy.id] = copy;
    await _put('p:${copy.id}', copy.toJson());
    final sectionMap = <String, String>{};
    for (final s in sectionsOf(p.id)) {
      final ns = ProjectSection(id: newId(), projectId: copy.id, name: s.name, position: s.position);
      sectionMap[s.id] = ns.id;
      _sections[ns.id] = ns;
      await _put('s:${ns.id}', ns.toJson());
    }
    final milestoneMap = <String, String>{};
    for (final m in milestonesOf(p.id)) {
      final nm = Milestone(
        id: newId(),
        projectId: copy.id,
        title: m.title,
        description: m.description,
        dueDate: m.dueDate,
        createdAt: now,
        updatedAt: now,
      );
      milestoneMap[m.id] = nm.id;
      _milestones[nm.id] = nm;
      await _put('m:${nm.id}', nm.toJson());
    }
    final source = tasksOfProject(p.id);
    final taskMap = {for (final t in source) t.id: newId()};
    for (final t in source) {
      final nt = PlanTask.fromJson({
        ...t.toJson(),
        'id': taskMap[t.id],
        'projectId': copy.id,
        'sectionId': sectionMap[t.sectionId],
        'milestoneId': milestoneMap[t.milestoneId],
        'parentId': taskMap[t.parentId],
        'dependsOn': [for (final d in t.dependsOn) if (taskMap[d] != null) taskMap[d]],
        'status': TaskStatus.todo.name,
        'completedAt': null,
        'checklist': [for (final c in t.checklist) {...c.toJson(), 'done': false}],
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'lastOpenedAt': now.toIso8601String(),
      });
      _tasks[nt.id] = nt;
      await _put('t:${nt.id}', nt.toJson());
    }
    await _log(EntityKind.project, copy.id, copy.name, 'Duplicated');
    notifyListeners();
    return copy;
  }

  /// Moves every dated task and milestone of [p] by [days]. Only ever called
  /// when the person asks for it.
  Future<void> shiftProjectDates(Project p, int days) async {
    if (days == 0) return;
    final delta = Duration(days: days);
    DateTime? shift(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day + days);
    for (final t in tasksOfProject(p.id)) {
      final next = t.copyWith(dueDate: shift(t.dueDate), startDate: shift(t.startDate), updatedAt: clock());
      _tasks[t.id] = next;
      await _put('t:${t.id}', next.toJson());
    }
    for (final m in milestonesOf(p.id)) {
      if (m.dueDate == null) continue;
      final next = m.copyWith(dueDate: m.dueDate!.add(delta), updatedAt: clock());
      _milestones[m.id] = next;
      await _put('m:${m.id}', next.toJson());
    }
    await _log(EntityKind.project, p.id, p.name, 'Rescheduled by $days days');
    notifyListeners();
  }

  Future<ProjectSection> addSection(String projectId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const PlanStoreException('Give the section a name.');
    final existing = sectionsOf(projectId);
    final s = ProjectSection(
      id: newId(),
      projectId: projectId,
      name: trimmed,
      position: existing.isEmpty ? 0 : existing.last.position + 1,
    );
    _sections[s.id] = s;
    await _put('s:${s.id}', s.toJson());
    notifyListeners();
    return s;
  }

  Future<void> renameSection(ProjectSection s, String name) async {
    if (name.trim().isEmpty) throw const PlanStoreException('Give the section a name.');
    final next = s.copyWith(name: name.trim());
    _sections[s.id] = next;
    await _put('s:${s.id}', next.toJson());
    notifyListeners();
  }

  /// Removes a section; its tasks stay in the project without a section.
  Future<void> deleteSection(ProjectSection s) async {
    for (final t in _tasks.values.toList()) {
      if (t.sectionId == s.id) {
        final next = t.copyWith(clearSection: true);
        _tasks[t.id] = next;
        await _put('t:${t.id}', next.toJson());
      }
    }
    _sections.remove(s.id);
    await _delete('s:${s.id}');
    notifyListeners();
  }

  Future<void> moveSection(ProjectSection s, int delta) async {
    final list = sectionsOf(s.projectId);
    final i = list.indexWhere((x) => x.id == s.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= list.length) return;
    list.insert(j, list.removeAt(i));
    for (var k = 0; k < list.length; k++) {
      final next = list[k].copyWith(position: k);
      _sections[next.id] = next;
      await _put('s:${next.id}', next.toJson());
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Milestones
  // ---------------------------------------------------------------------

  Milestone draftMilestone(String projectId) {
    final now = clock();
    return Milestone(id: newId(), projectId: projectId, title: '', createdAt: now, updatedAt: now);
  }

  Future<Milestone> saveMilestone(Milestone m) async {
    if (m.title.trim().isEmpty) throw const PlanStoreException('Give the milestone a title.');
    if (_projects[m.projectId] == null) throw const PlanStoreException('Choose a project for the milestone.');
    final existing = _milestones[m.id];
    final next = m.copyWith(title: m.title.trim(), updatedAt: clock());
    _milestones[m.id] = next;
    await _put('m:${m.id}', next.toJson());
    // Linked tasks of another project are unlinked when a milestone moves.
    if (existing != null && existing.projectId != next.projectId) {
      for (final t in tasksOfMilestone(m.id)) {
        final nt = t.copyWith(clearMilestone: true);
        _tasks[t.id] = nt;
        await _put('t:${t.id}', nt.toJson());
      }
    }
    await _log(EntityKind.milestone, m.id, next.title, existing == null ? 'Created' : 'Updated');
    notifyListeners();
    return next;
  }

  Future<void> setMilestoneDone(Milestone m, bool done) async {
    final next = done
        ? m.copyWith(completedAt: clock(), updatedAt: clock())
        : m.copyWith(clearCompleted: true, updatedAt: clock());
    _milestones[m.id] = next;
    await _put('m:${m.id}', next.toJson());
    await _log(EntityKind.milestone, m.id, m.title, done ? 'Reached' : 'Reopened');
    notifyListeners();
  }

  Future<void> deleteMilestone(Milestone m) async {
    for (final t in _tasks.values.toList()) {
      if (t.milestoneId == m.id) {
        final next = t.copyWith(clearMilestone: true);
        _tasks[t.id] = next;
        await _put('t:${t.id}', next.toJson());
      }
    }
    _milestones.remove(m.id);
    await _delete('m:${m.id}');
    await _log(EntityKind.milestone, null, m.title, 'Deleted');
    notifyListeners();
  }

  /// Links or unlinks tasks of the milestone's project.
  Future<void> setMilestoneTasks(Milestone m, Set<String> taskIds) async {
    for (final t in tasksOfProject(m.projectId)) {
      final linked = t.milestoneId == m.id;
      final want = taskIds.contains(t.id);
      if (linked == want) continue;
      final next = want ? t.copyWith(milestoneId: m.id) : t.copyWith(clearMilestone: true);
      _tasks[t.id] = next;
      await _put('t:${t.id}', next.toJson());
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Goals
  // ---------------------------------------------------------------------

  Goal draftGoal() {
    final now = clock();
    return Goal(id: newId(), title: '', createdAt: now, updatedAt: now);
  }

  Future<Goal> saveGoal(Goal g, {Set<String>? projectIds}) async {
    if (g.title.trim().isEmpty) throw const PlanStoreException('Give the goal a title.');
    final existing = _goals[g.id];
    var next = g.copyWith(title: g.title.trim(), updatedAt: clock());
    if (next.status == GoalStatus.completed && next.completedAt == null) {
      next = next.copyWith(completedAt: clock());
    } else if (next.status != GoalStatus.completed && next.completedAt != null) {
      next = next.copyWith(clearCompleted: true);
    }
    _goals[g.id] = next;
    await _put('g:${g.id}', next.toJson());
    if (projectIds != null) {
      for (final p in _projects.values.toList()) {
        final linked = p.goalId == g.id;
        final want = projectIds.contains(p.id);
        if (linked == want) continue;
        final np = want ? p.copyWith(goalId: g.id) : p.copyWith(clearGoal: true);
        _projects[p.id] = np;
        await _put('p:${p.id}', np.toJson());
      }
    }
    await _log(EntityKind.goal, g.id, next.title, existing == null ? 'Created' : 'Updated');
    notifyListeners();
    return next;
  }

  Future<void> setGoalArchived(Goal g, bool archived) async {
    final next = archived
        ? g.copyWith(archivedAt: clock(), updatedAt: clock())
        : g.copyWith(clearArchived: true, updatedAt: clock());
    _goals[g.id] = next;
    await _put('g:${g.id}', next.toJson());
    await _log(EntityKind.goal, g.id, g.title, archived ? 'Archived' : 'Restored');
    notifyListeners();
  }

  Future<void> deleteGoal(Goal g) async {
    for (final p in _projects.values.toList()) {
      if (p.goalId == g.id) {
        final np = p.copyWith(clearGoal: true);
        _projects[p.id] = np;
        await _put('p:${p.id}', np.toJson());
      }
    }
    _goals.remove(g.id);
    await _delete('g:${g.id}');
    await _log(EntityKind.goal, null, g.title, 'Deleted');
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Templates
  // ---------------------------------------------------------------------

  /// Creates a project from [t]: its sections, tasks with subtasks (dated
  /// from [start] when the template has dates) and milestones. Every record
  /// is new and belongs to this account only.
  Future<Project> createFromTemplate(
    PlanTemplate t, {
    required String name,
    required DateTime start,
    DateTime? due,
    String? category,
    Set<String>? sectionNames,
  }) async {
    final now = clock();
    final base = dateOnly(start);
    DateTime? at(int? offset) => offset == null ? null : DateTime(base.year, base.month, base.day + offset);
    final project = Project(
      id: newId(),
      name: name.trim().isEmpty ? t.name : name.trim(),
      description: t.description,
      icon: t.projectIcon,
      color: t.color.toARGB32(),
      status: ProjectStatus.planning,
      category: category ?? '',
      startDate: base,
      dueDate: due,
      templateId: t.id,
      createdAt: now,
      updatedAt: now,
      lastOpenedAt: now,
    );
    final error = validateProject(project);
    if (error != null) throw PlanStoreException(error);
    final writes = <String, Object>{'p:${project.id}': project.toJson()};
    _projects[project.id] = project;
    var position = 0;
    var sectionPos = 0;
    for (final s in t.sections) {
      if (sectionNames != null && !sectionNames.contains(s.name)) continue;
      final section = ProjectSection(id: newId(), projectId: project.id, name: s.name, position: sectionPos++);
      _sections[section.id] = section;
      writes['s:${section.id}'] = section.toJson();
      for (final tt in s.tasks) {
        final task = PlanTask(
          id: newId(),
          title: tt.title,
          projectId: project.id,
          sectionId: section.id,
          priority: tt.priority,
          dueDate: at(tt.dayOffset),
          reminderMinutes: tt.dayOffset == null ? null : _prefs.defaultReminderMinutes,
          position: position++,
          createdAt: now,
          updatedAt: now,
          lastOpenedAt: now,
        );
        _tasks[task.id] = task;
        writes['t:${task.id}'] = task.toJson();
        var subPos = 0;
        for (final sub in tt.subtasks) {
          final st = PlanTask(
            id: newId(),
            title: sub,
            projectId: project.id,
            sectionId: section.id,
            parentId: task.id,
            position: subPos++,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now,
          );
          _tasks[st.id] = st;
          writes['t:${st.id}'] = st.toJson();
        }
      }
    }
    for (final m in t.milestones) {
      final ms = Milestone(
        id: newId(),
        projectId: project.id,
        title: m.title,
        dueDate: at(m.dayOffset),
        createdAt: now,
        updatedAt: now,
      );
      _milestones[ms.id] = ms;
      writes['m:${ms.id}'] = ms.toJson();
    }
    await _requireBox.putAll({for (final e in writes.entries) e.key: jsonEncode(e.value)});
    _recentTemplates = [t.id, ..._recentTemplates.where((id) => id != t.id)].take(8).toList();
    await _put(_kRecentTemplates, _recentTemplates);
    await _log(EntityKind.project, project.id, project.name, 'Created from ${t.name}');
    notifyListeners();
    return project;
  }

  /// Saves the structure of [p] (sections, open and done tasks with their
  /// subtasks, milestones, and dates relative to the project start) as one
  /// of the person's own templates.
  Future<PlanTemplate> saveProjectAsTemplate(Project p, {required String name}) async {
    final start = p.startDate ?? dateOnly(p.createdAt);
    int? offset(DateTime? d) => d == null ? null : dateOnly(d).difference(start).inDays;
    final all = tasksOfProject(p.id).where((t) => t.parentId == null).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    TemplateTask toTemplate(PlanTask t) => TemplateTask(
      t.title,
      dayOffset: offset(t.dueDate),
      priority: t.priority,
      subtasks: [for (final s in subtasksOf(t.id)) s.title],
    );
    final sections = <TemplateSection>[
      for (final s in sectionsOf(p.id))
        TemplateSection(s.name, [for (final t in all) if (t.sectionId == s.id) toTemplate(t)]),
    ];
    final loose = [for (final t in all) if (t.sectionId == null) toTemplate(t)];
    if (loose.isNotEmpty) sections.add(TemplateSection('Tasks', loose));
    final template = PlanTemplate(
      id: 'custom_${newId()}',
      name: name.trim().isEmpty ? p.name : name.trim(),
      categoryId: 'custom',
      description: p.description.isEmpty ? 'Saved from ${p.name}.' : p.description,
      icon: p.iconData,
      projectIcon: p.icon,
      color: p.colorValue,
      sections: sections,
      milestones: [
        for (final m in milestonesOf(p.id))
          TemplateMilestone(m.title, offset(m.dueDate) ?? 0),
      ],
      custom: true,
    );
    _customTemplates[template.id] = template;
    await _put('ct:${template.id}', template.toJson());
    await _log(EntityKind.template, template.id, template.name, 'Saved as template');
    notifyListeners();
    return template;
  }

  Future<void> deleteCustomTemplate(String id) async {
    final t = _customTemplates.remove(id);
    await _delete('ct:$id');
    _favoriteTemplates.remove(id);
    await _put(_kFavTemplates, _favoriteTemplates);
    if (t != null) await _log(EntityKind.template, null, t.name, 'Deleted');
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Notifications list
  // ---------------------------------------------------------------------

  bool hasNotice(String key) =>
      _dismissedNotices.contains(key) || _notices.values.any((n) => n.key == key);

  Future<void> _rememberDismissed(Iterable<String> keys) async {
    _dismissedNotices = [..._dismissedNotices, ...keys];
    if (_dismissedNotices.length > 500) {
      _dismissedNotices = _dismissedNotices.sublist(_dismissedNotices.length - 500);
    }
    await _put(_kDismissed, _dismissedNotices);
  }

  Future<void> addNotice({
    required String key,
    required NoticeType type,
    required String title,
    required String body,
    EntityKind? targetKind,
    String? targetId,
  }) async {
    if (hasNotice(key)) return;
    final n = PlanNotice(
      id: newId(),
      key: key,
      type: type,
      title: title,
      body: body,
      targetKind: targetKind,
      targetId: targetId,
      at: clock(),
    );
    _notices[n.id] = n;
    await _put('n:${n.id}', n.toJson());
    if (_notices.length > _noticeLimit) {
      for (final old in notices.skip(_noticeLimit)) {
        _notices.remove(old.id);
        await _delete('n:${old.id}');
      }
    }
    notifyListeners();
  }

  /// Adds today's entries for due, overdue and upcoming work, once each,
  /// following the notification preferences. Run when the app opens and
  /// whenever plans change.
  Future<void> refreshNotices() async {
    if (!isOpen) return;
    final now = clock();
    final today = dayKey(now);
    if (_prefs.notifyDueToday) {
      for (final t in tasks) {
        if (!t.isDone && t.isDueOn(now) && !t.isOverdue(now)) {
          await addNotice(
            key: 'due:${t.id}:$today',
            type: NoticeType.dueToday,
            title: 'Due today: ${t.title}',
            body: _context(t),
            targetKind: EntityKind.task,
            targetId: t.id,
          );
        }
      }
    }
    if (_prefs.notifyOverdue) {
      for (final t in tasks) {
        if (t.isOverdue(now)) {
          await addNotice(
            key: 'overdue:${t.id}:$today',
            type: NoticeType.overdue,
            title: 'Overdue: ${t.title}',
            body: _context(t),
            targetKind: EntityKind.task,
            targetId: t.id,
          );
        }
      }
    }
    if (_prefs.notifyReminders) {
      // Reminders that went off on the device since yesterday are listed
      // here too, so a dismissed system notification is not lost.
      for (final t in tasks) {
        final at = t.reminderAt;
        if (t.isDone || at == null || at.isAfter(now)) continue;
        if (now.difference(at) > const Duration(hours: 24)) continue;
        await addNotice(
          key: 'reminder:${t.id}:${at.toIso8601String()}',
          type: NoticeType.reminder,
          title: 'Reminder: ${t.title}',
          body: _context(t),
          targetKind: EntityKind.task,
          targetId: t.id,
        );
      }
    }
    if (_prefs.notifyMilestones) {
      for (final m in upcomingMilestones(days: _prefs.milestoneLeadDays)) {
        final days = dateOnly(m.dueDate!).difference(dateOnly(now)).inDays;
        await addNotice(
          key: 'milestone:${m.id}:${dayKey(m.dueDate)}',
          type: NoticeType.milestone,
          title: days < 0
              ? 'Milestone passed: ${m.title}'
              : days == 0
              ? 'Milestone today: ${m.title}'
              : 'Milestone in $days ${days == 1 ? 'day' : 'days'}: ${m.title}',
          body: _projects[m.projectId]?.name ?? '',
          targetKind: EntityKind.milestone,
          targetId: m.id,
        );
      }
    }
  }

  String _context(PlanTask t) {
    final p = _projects[t.projectId];
    return p == null ? 'No project' : p.name;
  }

  Future<void> markNoticeRead(PlanNotice n) async {
    final next = n.markRead();
    _notices[n.id] = next;
    await _put('n:${n.id}', next.toJson());
    notifyListeners();
  }

  Future<void> markAllNoticesRead() async {
    for (final n in _notices.values.toList()) {
      if (n.read) continue;
      final next = n.markRead();
      _notices[n.id] = next;
      await _put('n:${n.id}', next.toJson());
    }
    notifyListeners();
  }

  Future<void> dismissNotice(PlanNotice n) async {
    _notices.remove(n.id);
    await _rememberDismissed([n.key]);
    await _delete('n:${n.id}');
    notifyListeners();
  }

  /// Clears the list. A cleared alert is not listed again (an overdue task
  /// comes back the next day, under a new key).
  Future<void> clearNotices() async {
    await _rememberDismissed([for (final n in _notices.values) n.key]);
    for (final id in _notices.keys.toList()) {
      await _delete('n:$id');
    }
    _notices.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Whole-store operations (backup, restore, clear)
  // ---------------------------------------------------------------------

  /// Everything in the store as stored, keyed like the box.
  Map<String, Object?> snapshot() {
    final box = _requireBox;
    final out = <String, Object?>{};
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        out['$key'] = jsonDecode(raw);
      } catch (_) {
        // Unreadable entries are not carried into a backup.
      }
    }
    return out;
  }

  /// Replaces everything with [entries] (already validated). The current
  /// data is kept in memory and written back if the replacement fails, so a
  /// failed restore leaves the person's plans as they were.
  Future<void> replaceAll(Map<String, Object?> entries) async {
    final box = _requireBox;
    final before = {for (final k in box.keys) '$k': box.get(k)!};
    try {
      await box.clear();
      await box.putAll({for (final e in entries.entries) e.key: jsonEncode(e.value)});
    } catch (e) {
      await box.clear();
      await box.putAll(before);
      _clearMemory();
      _load(box);
      notifyListeners();
      throw PlanStoreException('The restore could not be completed, so nothing was changed. ($e)');
    }
    _clearMemory();
    _load(box);
    notifyListeners();
  }

  /// Adds [entries] whose keys are not already present. Returns how many
  /// were added.
  Future<int> mergeIn(Map<String, Object?> entries) async {
    final box = _requireBox;
    final fresh = <String, String>{};
    for (final e in entries.entries) {
      if (e.key.startsWith('meta:') || box.containsKey(e.key)) continue;
      fresh[e.key] = jsonEncode(e.value);
    }
    await box.putAll(fresh);
    for (final e in fresh.entries) {
      _apply(e.key, jsonDecode(e.value));
    }
    notifyListeners();
    return fresh.length;
  }

  /// Deletes every plan, task, goal and setting of this account on this
  /// device.
  Future<void> clearAll() async {
    await _requireBox.clear();
    _clearMemory();
    notifyListeners();
  }

  /// Deletes this account's box from the device (used after the account
  /// itself is deleted).
  static Future<void> deleteScope(String scope) async {
    await Hive.deleteBoxFromDisk(boxNameFor(scope));
  }

  // --- counts for the profile and storage screens ---

  int get storedEntryCount => _box?.length ?? 0;
}
