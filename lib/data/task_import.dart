import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';

/// RFC 4180 CSV: quoted fields, doubled quotes, newlines inside quotes, and
/// a leading byte-order mark. Also accepts ";" as separator when the header
/// uses it (spreadsheets in some regions save that way).
List<List<String>> parseCsv(String input) {
  var text = input.startsWith('﻿') ? input.substring(1) : input;
  final firstLine = text.split('\n').first;
  final sep = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? ';' : ',';
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == sep) {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
  return rows;
}

/// The task fields a column can fill.
enum ImportField {
  title('Title', ['title', 'task', 'name', 'task name', 'subject']),
  description('Description', ['description', 'details']),
  project('Project', ['project', 'project name', 'list']),
  dueDate('Due date', ['due date', 'due', 'deadline', 'date']),
  dueTime('Due time', ['due time', 'time']),
  startDate('Start date', ['start date', 'start']),
  priority('Priority', ['priority']),
  status('Status', ['status', 'state']),
  tags('Tags', ['tags', 'labels', 'tag']),
  notes('Notes', ['notes', 'note', 'comments']);

  final String label;
  final List<String> aliases;
  const ImportField(this.label, this.aliases);
}

class ImportRow {
  final int line;
  final PlanTask? task;
  final String? projectName;
  final List<String> problems;
  final bool duplicate;

  const ImportRow({required this.line, this.task, this.projectName, this.problems = const [], this.duplicate = false});

  bool get ok => task != null && problems.isEmpty;
}

class ImportPlan {
  final List<ImportRow> rows;
  final Set<String> newProjects;

  const ImportPlan(this.rows, this.newProjects);

  int get valid => rows.where((r) => r.ok && !r.duplicate).length;
  int get invalid => rows.where((r) => !r.ok).length;
  int get duplicates => rows.where((r) => r.ok && r.duplicate).length;
}

class ImportResult {
  final int created;
  final int skipped;
  final int projectsCreated;
  const ImportResult(this.created, this.skipped, this.projectsCreated);
}

/// Guesses which column fills which field from the header names.
Map<ImportField, int> guessMapping(List<String> header) {
  final out = <ImportField, int>{};
  final normal = [for (final h in header) h.trim().toLowerCase()];
  for (final f in ImportField.values) {
    for (final (i, h) in normal.indexed) {
      if (out.containsValue(i)) continue;
      if (f.aliases.contains(h)) {
        out[f] = i;
        break;
      }
    }
  }
  return out;
}

DateTime? parseImportDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return dateOnly(iso);
  // d/m/y or d-m-y or d.m.y (day first, as in Malaysia and most regions).
  final m = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$').firstMatch(s);
  if (m != null) {
    final d = int.parse(m[1]!), mo = int.parse(m[2]!);
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, mo, d);
    return date.month == mo ? date : null;
  }
  return null;
}

int? parseImportTime(String raw) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})\s*([aApP][mM])?$').firstMatch(raw.trim());
  if (m == null) return null;
  var h = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  final ap = m[3]?.toLowerCase();
  if (ap == 'pm' && h < 12) h += 12;
  if (ap == 'am' && h == 12) h = 0;
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

Priority? parseImportPriority(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty || s == '—' || s == 'none' || s == 'no priority') return Priority.none;
  for (final p in Priority.values) {
    if (p.name == s || p.label.toLowerCase() == s) return p;
  }
  return switch (s) {
    '1' || 'p1' || 'critical' => Priority.urgent,
    '2' || 'p2' => Priority.high,
    '3' || 'p3' || 'normal' => Priority.medium,
    '4' || 'p4' => Priority.low,
    _ => null,
  };
}

TaskStatus? parseImportStatus(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return TaskStatus.todo;
  for (final t in TaskStatus.values) {
    if (t.name.toLowerCase() == s || t.label.toLowerCase() == s) return t;
  }
  return switch (s) {
    'done' || 'complete' || 'completed' || 'yes' || 'x' || 'true' => TaskStatus.done,
    'open' || 'not started' || 'todo' || 'to-do' || 'no' || 'false' => TaskStatus.todo,
    'doing' || 'started' || 'in-progress' => TaskStatus.inProgress,
    'paused' || 'blocked' || 'waiting' => TaskStatus.onHold,
    _ => null,
  };
}

/// Checks every row and builds the tasks to create, without saving.
/// A row is a duplicate when a task with the same title, due date and
/// project already exists (or appears earlier in the file).
ImportPlan planImport(
  PlanStore store,
  List<List<String>> rows,
  Map<ImportField, int> mapping, {
  bool createProjects = true,
  int maxRows = 5000,
}) {
  final now = DateTime.now();
  final byName = {for (final p in store.projects) p.name.trim().toLowerCase(): p};
  final seen = <String>{
    for (final t in store.tasks) '${t.title.trim().toLowerCase()}|${dayKey(t.dueDate)}|${t.projectId}',
  };
  final newProjects = <String>{};
  final out = <ImportRow>[];
  String cell(List<String> r, ImportField f) {
    final i = mapping[f];
    return i == null || i >= r.length ? '' : r[i].trim();
  }

  for (final (index, r) in rows.skip(1).take(maxRows).indexed) {
    final line = index + 2;
    final problems = <String>[];
    final title = cell(r, ImportField.title);
    if (title.isEmpty) problems.add('No title');
    final dueRaw = cell(r, ImportField.dueDate);
    final due = parseImportDate(dueRaw);
    if (dueRaw.isNotEmpty && due == null) problems.add('Due date "$dueRaw" is not a date');
    final startRaw = cell(r, ImportField.startDate);
    final start = parseImportDate(startRaw);
    if (startRaw.isNotEmpty && start == null) problems.add('Start date "$startRaw" is not a date');
    final timeRaw = cell(r, ImportField.dueTime);
    final time = parseImportTime(timeRaw);
    if (timeRaw.isNotEmpty && time == null) problems.add('Time "$timeRaw" is not a time');
    final priority = parseImportPriority(cell(r, ImportField.priority));
    if (priority == null) problems.add('Unknown priority "${cell(r, ImportField.priority)}"');
    final status = parseImportStatus(cell(r, ImportField.status));
    if (status == null) problems.add('Unknown status "${cell(r, ImportField.status)}"');
    final projectName = cell(r, ImportField.project);
    final project = projectName.isEmpty ? null : byName[projectName.toLowerCase()];
    if (projectName.isNotEmpty && project == null) {
      if (createProjects) {
        newProjects.add(projectName);
      } else {
        problems.add('No project called "$projectName"');
      }
    }
    if (problems.isNotEmpty) {
      out.add(ImportRow(line: line, problems: problems));
      continue;
    }
    final projectKey = project?.id ?? (projectName.isEmpty ? null : 'new:${projectName.toLowerCase()}');
    final key = '${title.toLowerCase()}|${dayKey(due)}|$projectKey';
    final duplicate = !seen.add(key);
    final task = store.draftTask(projectId: project?.id).copyWith(
      title: title,
      description: cell(r, ImportField.description),
      notes: cell(r, ImportField.notes),
      dueDate: due,
      dueMinutes: due == null ? null : time,
      startDate: start,
      priority: priority,
      status: status,
      completedAt: status == TaskStatus.done ? now : null,
      tags: [
        for (final t in cell(r, ImportField.tags).split(RegExp(r'[;,]')))
          if (t.trim().isNotEmpty) t.trim().replaceAll('#', ''),
      ],
      clearReminder: due == null,
    );
    out.add(ImportRow(line: line, task: task, projectName: projectName.isEmpty ? null : projectName, duplicate: duplicate));
  }
  return ImportPlan(out, newProjects);
}

/// Saves the valid rows of [plan]. Duplicates are skipped unless
/// [includeDuplicates].
Future<ImportResult> runImport(PlanStore store, ImportPlan plan, {bool includeDuplicates = false}) async {
  final created = <String, String>{};
  for (final name in plan.newProjects) {
    final p = await store.saveProject(store.draftProject().copyWith(name: name, status: ProjectStatus.inProgress));
    created[name.toLowerCase()] = p.id;
  }
  var saved = 0, skipped = 0;
  for (final row in plan.rows) {
    if (!row.ok || (row.duplicate && !includeDuplicates)) {
      skipped++;
      continue;
    }
    var task = row.task!;
    if (task.projectId == null && row.projectName != null) {
      task = task.copyWith(projectId: created[row.projectName!.toLowerCase()]);
    }
    await store.saveTask(task);
    saved++;
  }
  return ImportResult(saved, skipped, created.length);
}
