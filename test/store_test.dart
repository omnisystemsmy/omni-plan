import 'package:flutter_test/flutter_test.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/templates/template_library.dart';

import 'test_env.dart';

void main() {
  late TestEnv env;
  late PlanStore store;

  setUp(() async {
    env = await TestEnv.create();
    store = await env.store('user-a');
  });

  tearDown(() async {
    await store.close();
    await env.dispose();
  });

  Future<Project> project(String name) => store.saveProject(store.draftProject().copyWith(name: name));
  Future<PlanTask> addTask(String title, {String? projectId, String? parentId, DateTime? due}) => store.saveTask(
    store.draftTask(projectId: projectId, parentId: parentId, dueDate: due).copyWith(title: title),
  );

  test('a task needs only a title, and persists across reopening', () async {
    final t = await addTask('Buy milk');
    expect(store.tasks.single.title, 'Buy milk');
    await store.close();
    store = await env.store('user-a');
    expect(store.task(t.id)?.title, 'Buy milk');
  });

  test('validation rejects empty titles and start after due', () async {
    expect(() => store.saveTask(store.draftTask()), throwsA(isA<PlanStoreException>()));
    final bad = store.draftTask().copyWith(title: 'x', startDate: DateTime(2026, 11, 2), dueDate: DateTime(2026, 11, 1));
    expect(() => store.saveTask(bad), throwsA(isA<PlanStoreException>()));
  });

  test('accounts on the same device never see each other\'s plans', () async {
    await addTask('A task of user A');
    final other = await env.store('user-b');
    expect(other.tasks, isEmpty);
    await other.close();
  });

  test('completing a repeating task creates the next occurrence', () async {
    final t = await store.saveTask(store.draftTask(dueDate: DateTime(2026, 10, 26)).copyWith(
      title: 'Weekly review',
      recurrence: const Recurrence(frequency: RecurrenceFrequency.weekly),
      checklist: const [ChecklistItem(id: 'c1', title: 'Inbox zero', done: true)],
    ));
    final next = await store.setTaskDone(t, true);
    expect(next, isNotNull);
    expect(next!.dueDate, DateTime(2026, 11, 2));
    expect(next.isDone, isFalse);
    expect(next.checklist.single.done, isFalse);
    expect(store.task(t.id)!.isDone, isTrue);
    expect(store.task(t.id)!.recurrence, isNull);
  });

  test('project progress follows task status', () async {
    final p = await project('Launch');
    final a = await addTask('A', projectId: p.id);
    await addTask('B', projectId: p.id);
    expect(store.projectProgress(p.id).percent, 0);
    await store.setTaskDone(a, true);
    expect(store.projectProgress(p.id).percent, 50);
  });

  test('archiving a task archives its subtasks; restoring brings them back', () async {
    final parent = await addTask('Parent');
    await addTask('Child', parentId: parent.id);
    await store.archiveTask(parent);
    expect(store.tasks, isEmpty);
    expect(store.archivedTasks.map((t) => t.title), ['Parent']);
    await store.restoreTask(parent);
    expect(store.tasks.length, 2);
  });

  test('deleting a task deletes subtasks and clears dependencies on it', () async {
    final p = await project('P');
    final a = await addTask('A', projectId: p.id);
    final b = await addTask('B', projectId: p.id);
    await addTask('A child', parentId: a.id);
    await store.addDependency(b, a);
    expect(store.isBlocked(store.task(b.id)!), isTrue);
    await store.deleteTask(a);
    expect(store.tasks.map((t) => t.title), ['B']);
    expect(store.task(b.id)!.dependsOn, isEmpty);
  });

  test('dependency cycles and cross-project links are refused', () async {
    final p = await project('P');
    final q = await project('Q');
    final a = await addTask('A', projectId: p.id);
    final b = await addTask('B', projectId: p.id);
    final c = await addTask('C', projectId: q.id);
    await store.addDependency(b, a);
    expect(() => store.addDependency(store.task(a.id)!, store.task(b.id)!), throwsA(isA<PlanStoreException>()));
    expect(() => store.addDependency(store.task(a.id)!, c), throwsA(isA<PlanStoreException>()));
  });

  test('deleting a project can keep its tasks', () async {
    final p = await project('Old');
    await addTask('Keep me', projectId: p.id);
    await store.addSection(p.id, 'Phase 1');
    await store.deleteProject(p, ProjectDeleteMode.keepTasks);
    expect(store.projects, isEmpty);
    expect(store.tasks.single.projectId, isNull);
    expect(store.sectionsOf(p.id), isEmpty);
  });

  test('deleting a project can delete its tasks', () async {
    final p = await project('Old');
    await addTask('Go', projectId: p.id);
    await store.deleteProject(p, ProjectDeleteMode.deleteTasks);
    expect(store.allTasks, isEmpty);
  });

  test('archiving a project hides its tasks until restored', () async {
    final p = await project('Hidden');
    await addTask('Inside', projectId: p.id);
    await store.archiveProject(p);
    expect(store.tasks, isEmpty);
    await store.restoreProject(p);
    expect(store.tasks.single.title, 'Inside');
  });

  test('duplicating a project copies structure and remaps links', () async {
    final p = await project('Source');
    final s = await store.addSection(p.id, 'Phase');
    final a = await store.saveTask(store.draftTask(projectId: p.id, sectionId: s.id).copyWith(title: 'A'));
    final b = await addTask('B', projectId: p.id);
    await store.addDependency(b, a);
    await store.setTaskDone(a, true);
    final copy = await store.duplicateProject(p);
    final tasks = store.tasksOfProject(copy.id);
    expect(tasks.length, 2);
    expect(tasks.every((t) => !t.isDone), isTrue);
    final copiedA = tasks.firstWhere((t) => t.title == 'A');
    final copiedB = tasks.firstWhere((t) => t.title == 'B');
    expect(copiedB.dependsOn, [copiedA.id]);
    expect(store.section(copiedA.sectionId)!.projectId, copy.id);
  });

  test('changing project dates never moves tasks unless asked', () async {
    final p = await store.saveProject(store.draftProject().copyWith(name: 'P', startDate: DateTime(2026, 10, 1)));
    final t = await addTask('Dated', projectId: p.id, due: DateTime(2026, 10, 10));
    await store.saveProject(p.copyWith(startDate: DateTime(2026, 10, 5)));
    expect(store.task(t.id)!.dueDate, DateTime(2026, 10, 10));
    await store.shiftProjectDates(p, 4);
    expect(store.task(t.id)!.dueDate, DateTime(2026, 10, 14));
  });

  test('a template creates editable records dated from the start', () async {
    final t = TemplateLibrary.byId('assignment_tracker')!;
    final p = await store.createFromTemplate(t, name: 'Essay', start: DateTime(2026, 11, 1));
    expect(p.name, 'Essay');
    expect(store.sectionsOf(p.id).length, t.sections.length);
    expect(store.tasksOfProject(p.id).length, t.taskCount);
    final submit = store.tasksOfProject(p.id).firstWhere((x) => x.title == 'Submit assignment');
    expect(submit.dueDate, DateTime(2026, 11, 15));
    expect(store.milestonesOf(p.id).length, t.milestones.length);
    expect(store.recentTemplates.first, t.id);
  });

  test('saving a project as a template reproduces its structure', () async {
    final t = TemplateLibrary.byId('kanban_project')!;
    final p = await store.createFromTemplate(t, name: 'Board', start: DateTime(2026, 11, 1));
    final custom = await store.saveProjectAsTemplate(p, name: 'My board');
    expect(custom.topLevelTaskCount, t.topLevelTaskCount);
    final again = await store.createFromTemplate(custom, name: 'Again', start: DateTime(2026, 12, 1));
    expect(store.tasksOfProject(again.id).length, store.tasksOfProject(p.id).length);
  });

  test('notifications are listed once, and cleared ones do not return', () async {
    store.clock = () => DateTime(2026, 10, 26, 10);
    await addTask('Late', due: DateTime(2026, 10, 20));
    await store.refreshNotices();
    await store.refreshNotices();
    expect(store.notices.where((n) => n.type == NoticeType.overdue).length, 1);
    await store.clearNotices();
    await store.refreshNotices();
    expect(store.notices, isEmpty);
  });

  test('preferences persist and feed new tasks', () async {
    await store.updatePrefs(store.prefs.copyWith(defaultPriority: Priority.high, defaultReminderMinutes: 30));
    await store.close();
    store = await env.store('user-a');
    final d = store.draftTask(dueDate: DateTime(2026, 11, 1));
    expect(d.priority, Priority.high);
    expect(d.reminderMinutes, 30);
  });

  test('goal progress counts the tasks of linked projects', () async {
    final p = await project('Fitness');
    final g = await store.saveGoal(store.draftGoal().copyWith(title: 'Run 10k'), projectIds: {p.id});
    final a = await addTask('Run 5k', projectId: p.id);
    await addTask('Run 10k', projectId: p.id);
    await store.setTaskDone(a, true);
    expect(store.goalProgress(g.id).percent, 50);
    await store.deleteGoal(g);
    expect(store.project(p.id)!.goalId, isNull);
  });
}
