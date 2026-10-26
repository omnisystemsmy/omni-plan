import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_plan/data/backup_service.dart';
import 'package:omni_plan/data/export_service.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/data/task_import.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/templates/catalogue_data.dart';
import 'package:omni_plan/features/templates/template_library.dart';

import 'test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestEnv env;
  late PlanStore store;

  setUp(() async {
    env = await TestEnv.create();
    store = await env.store('backup-user');
  });

  tearDown(() async {
    await store.close();
    await env.dispose();
  });

  Future<Project> seed() async {
    final p = await store.createFromTemplate(TemplateLibrary.byId('general_project_plan')!, name: 'Launch', start: DateTime(2026, 11, 1));
    final tasks = store.tasksOfProject(p.id);
    await store.addDependency(tasks[1], tasks[0]);
    await store.saveGoal(store.draftGoal().copyWith(title: 'Ship'), projectIds: {p.id});
    await store.toggleFavoriteTemplate('weekly_planner');
    await store.updatePrefs(store.prefs.copyWith(weekStart: 7));
    return p;
  }

  group('Backup', () {
    test('a backup restores everything with its links', () async {
      final p = await seed();
      final before = store.snapshot();
      final json = BackupService.build(store);

      await store.clearAll();
      expect(store.projects, isEmpty);

      final preview = BackupService.inspect(json, store);
      expect(preview.count('projects'), 1);
      expect(preview.skipped, 0);
      expect(preview.repairedLinks, 0);
      await BackupService.restoreReplacing(preview, store);

      expect(store.snapshot(), before);
      expect(store.project(p.id)!.goalId, isNotNull);
      expect(store.tasksOfProject(p.id).any((t) => t.dependsOn.isNotEmpty), isTrue);
      expect(store.prefs.weekStart, 7);
      expect(store.isFavoriteTemplate('weekly_planner'), isTrue);
    });

    test('a changed file is refused', () async {
      await seed();
      final j = jsonDecode(BackupService.build(store)) as Map<String, dynamic>;
      final entries = j['entries'] as Map<String, dynamic>;
      final key = entries.keys.firstWhere((k) => k.startsWith('p:'));
      (entries[key] as Map<String, dynamic>)['name'] = 'Edited';
      expect(() => BackupService.inspect(jsonEncode(j), store), throwsA(isA<BackupException>()));
    });

    test('other files are refused with a clear message', () {
      expect(() => BackupService.inspect('not json', store), throwsA(isA<BackupException>()));
      expect(() => BackupService.inspect('{"format":"omni_docs_backup"}', store), throwsA(isA<BackupException>()));
      expect(
        () => BackupService.inspect('{"format":"omni_plan_backup","version":99,"entries":{}}', store),
        throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('newer version'))),
      );
    });

    test('merging keeps what is here and adds the rest', () async {
      await seed();
      final json = BackupService.build(store);
      final extra = await store.saveTask(store.draftTask().copyWith(title: 'Only here'));
      final preview = BackupService.inspect(json, store);
      final added = await BackupService.restoreMerging(preview, store);
      expect(added, 0);
      expect(store.task(extra.id), isNotNull);
    });

    test('links to records missing from the file are repaired', () async {
      final p = await seed();
      final j = jsonDecode(BackupService.build(store)) as Map<String, dynamic>;
      final entries = Map<String, dynamic>.from(j['entries'] as Map)..remove('p:${p.id}');
      j['entries'] = entries;
      j['checksum'] = BackupService.checksum(entries.cast<String, Object?>());
      final preview = BackupService.inspect(jsonEncode(j), store);
      expect(preview.repairedLinks, greaterThan(0));
      await BackupService.restoreReplacing(preview, store);
      expect(store.tasks.every((t) => t.projectId == null), isTrue);
      expect(store.milestones, isEmpty);
    });
  });

  group('CSV', () {
    test('parses quotes, commas and newlines in fields', () {
      final rows = parseCsv('﻿Title,Notes\n"Buy ""good"" milk","a, b\nc"\r\nNext,\n');
      expect(rows, [
        ['Title', 'Notes'],
        ['Buy "good" milk', 'a, b\nc'],
        ['Next', ''],
      ]);
    });

    test('an Omni Plan export imports back as the same tasks', () async {
      await seed();
      final csv = ExportService.tasksCsv(store);
      final count = store.tasks.length;
      await store.clearAll();
      final rows = parseCsv(csv);
      final mapping = guessMapping(rows.first);
      expect(mapping[ImportField.title], 0);
      expect(mapping[ImportField.dueDate], isNotNull);
      final plan = planImport(store, rows, mapping);
      expect(plan.invalid, 0);
      expect(plan.newProjects, {'Launch'});
      final result = await runImport(store, plan);
      expect(result.created, count);
      expect(store.projects.single.name, 'Launch');
    });

    test('bad rows and duplicates are reported, not imported', () async {
      await store.saveTask(store.draftTask(dueDate: DateTime(2026, 11, 5)).copyWith(title: 'Existing'));
      final rows = parseCsv('Task,Due,Priority\nExisting,2026-11-05,\n,2026-11-01,\nOdd,32/13/2026,\nFine,5/11/2026,high\n');
      final plan = planImport(store, rows, guessMapping(rows.first));
      expect(plan.duplicates, 1);
      expect(plan.invalid, 2);
      expect(plan.valid, 1);
      final fine = plan.rows.firstWhere((r) => r.ok && !r.duplicate).task!;
      expect(fine.dueDate, DateTime(2026, 11, 5));
      expect(fine.priority, Priority.high);
    });
  });

  group('Template catalogue', () {
    test('ids are unique and every category has templates', () {
      final ids = builtInTemplates.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final c in templateCategories) {
        expect(TemplateLibrary.inCategory(c.id), isNotEmpty, reason: c.name);
      }
      for (final id in featuredTemplateIds) {
        expect(TemplateLibrary.byId(id), isNotNull, reason: id);
      }
      // ignore: avoid_print
      print('Templates: ${TemplateLibrary.templateCount} across ${TemplateLibrary.categoryCount} categories');
    });

    test('every template has tasks with titles', () {
      for (final t in builtInTemplates) {
        expect(t.topLevelTaskCount, greaterThan(0), reason: t.name);
        for (final s in t.sections) {
          for (final task in s.tasks) {
            expect(task.title.trim(), isNotEmpty, reason: '${t.name} / ${s.name}');
            expect(task.title.contains('@'), isFalse, reason: task.title);
          }
        }
      }
    });

    test('every template can be used', () async {
      for (final t in builtInTemplates) {
        await store.createFromTemplate(t, name: t.name, start: DateTime(2026, 11, 1));
      }
      expect(store.projects.length, builtInTemplates.length);
    });

    test('search finds by name and keyword', () {
      expect(TemplateLibrary.search('semester').first.id, 'semester_planner');
      expect(TemplateLibrary.search('scrum').map((t) => t.id), contains('agile_sprint'));
      expect(TemplateLibrary.search('zzzz'), isEmpty);
    });
  });

  test('a project report PDF is generated from the data', () async {
    final p = await seed();
    final bytes = await ExportService.projectReportPdf(store, p);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
