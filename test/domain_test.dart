import 'package:flutter_test/flutter_test.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/rules.dart';
import 'package:omni_plan/features/templates/template_models.dart';

PlanTask task(String id, {DateTime? due, int? minutes, TaskStatus status = TaskStatus.todo, String? parent}) {
  final now = DateTime(2026, 10, 1);
  return PlanTask(
    id: id,
    title: 'Task $id',
    dueDate: due,
    dueMinutes: minutes,
    status: status,
    parentId: parent,
    createdAt: now,
    updatedAt: now,
    lastOpenedAt: now,
  );
}

void main() {
  group('Recurrence', () {
    test('daily with interval', () {
      const r = Recurrence(frequency: RecurrenceFrequency.daily, interval: 3);
      expect(r.next(DateTime(2026, 10, 30)), DateTime(2026, 11, 2));
    });

    test('weekly on chosen weekdays takes the next chosen day', () {
      // Monday 26 Oct 2026; repeat Mon, Wed, Fri.
      const r = Recurrence(frequency: RecurrenceFrequency.weekly, weekdays: [1, 3, 5]);
      expect(r.next(DateTime(2026, 10, 26)), DateTime(2026, 10, 28));
      expect(r.next(DateTime(2026, 10, 30)), DateTime(2026, 11, 2));
    });

    test('every two weeks on Monday skips a week', () {
      const r = Recurrence(frequency: RecurrenceFrequency.weekly, interval: 2, weekdays: [1]);
      expect(r.next(DateTime(2026, 10, 26)), DateTime(2026, 11, 9));
    });

    test('monthly keeps the end of the month', () {
      const r = Recurrence(frequency: RecurrenceFrequency.monthly);
      expect(r.next(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
    });

    test('ends after the end date', () {
      final r = Recurrence(frequency: RecurrenceFrequency.weekly, endDate: DateTime(2026, 11, 1));
      expect(r.next(DateTime(2026, 10, 26)), isNull);
    });

    test('round-trips through JSON', () {
      final r = Recurrence(frequency: RecurrenceFrequency.weekly, interval: 2, weekdays: const [2, 4], endDate: DateTime(2027, 1, 1));
      final back = Recurrence.fromJson(r.toJson())!;
      expect(back.summary, r.summary);
      expect(back.endDate, DateTime(2027, 1, 1));
    });
  });

  group('Progress', () {
    test('no tasks means no percentage', () {
      final p = progressOf(const []);
      expect(p.fraction, isNull);
      expect(p.percent, isNull);
      expect(p.label, 'No tasks yet');
    });

    test('counts done tasks out of all, ignoring archived', () {
      final now = DateTime(2026, 10, 1);
      final p = progressOf([
        task('a', status: TaskStatus.done),
        task('b'),
        task('c', status: TaskStatus.inProgress),
        task('d', status: TaskStatus.done).copyWith(archivedAt: now),
      ]);
      expect(p.done, 1);
      expect(p.total, 3);
      expect(p.percent, 33);
    });
  });

  test('dependency cycles are detected', () {
    final graph = {
      'a': ['b'],
      'b': ['c'],
      'c': <String>[],
    };
    expect(wouldCreateCycle('c', 'a', graph), isTrue);
    expect(wouldCreateCycle('a', 'c', graph), isFalse);
    expect(wouldCreateCycle('a', 'a', graph), isTrue);
  });

  group('Task filter', () {
    final now = DateTime(2026, 10, 26, 12);
    final tasks = [
      task('today', due: DateTime(2026, 10, 26)),
      task('late', due: DateTime(2026, 10, 20)),
      task('lateToday', due: DateTime(2026, 10, 26), minutes: 9 * 60),
      task('soon', due: DateTime(2026, 10, 30)),
      task('far', due: DateTime(2026, 12, 1)),
      task('none'),
      task('done', due: DateTime(2026, 10, 26), status: TaskStatus.done),
      task('sub', due: DateTime(2026, 10, 26), parent: 'today'),
    ];
    List<String> ids(TaskQuick q) => [for (final t in tasks) if (TaskFilter(quick: q).matches(t, now)) t.id];

    test('overdue honours due time', () {
      expect(ids(TaskQuick.overdue), ['late', 'lateToday']);
    });
    test('today includes overdue and subtasks due today', () {
      expect(ids(TaskQuick.today), ['today', 'late', 'lateToday', 'sub']);
    });
    test('upcoming is the next seven days after today', () {
      expect(ids(TaskQuick.upcoming), ['soon']);
    });
    test('all hides done tasks and subtasks', () {
      expect(ids(TaskQuick.all), ['today', 'late', 'lateToday', 'soon', 'far', 'none']);
    });
    test('completed', () {
      expect(ids(TaskQuick.completed), ['done']);
    });
  });

  test('template task lines parse offsets, priority and subtasks', () {
    final t = TemplateTask.parse('Write report @14 !high > Outline; Draft; Edit');
    expect(t.title, 'Write report');
    expect(t.dayOffset, 14);
    expect(t.priority, Priority.high);
    expect(t.subtasks, ['Outline', 'Draft', 'Edit']);
    expect(TemplateTask.parse('Prepare @-3').dayOffset, -3);
  });

  test('task JSON keeps every field', () {
    final now = DateTime(2026, 10, 1);
    final t = PlanTask(
      id: 'x',
      title: 'Full',
      description: 'd',
      projectId: 'p',
      priority: Priority.urgent,
      status: TaskStatus.onHold,
      dueDate: DateTime(2026, 11, 3),
      dueMinutes: 615,
      estimateMinutes: 90,
      tags: const ['a', 'b'],
      checklist: const [ChecklistItem(id: 'c', title: 'Check', done: true)],
      recurrence: const Recurrence(frequency: RecurrenceFrequency.daily),
      reminderMinutes: 15,
      dependsOn: const ['y'],
      createdAt: now,
      updatedAt: now,
      lastOpenedAt: now,
    );
    final back = PlanTask.fromJson(t.toJson());
    expect(back.toJson(), t.toJson());
    expect(back.reminderAt, DateTime(2026, 11, 3, 10, 0));
  });
}
