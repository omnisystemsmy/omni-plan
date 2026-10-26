import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/domain/rules.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// CSV and PDF files made from the stored plans. Neither is a backup: they
/// leave out relationships and settings (see `BackupService`).
class ExportService {
  const ExportService._();

  static const List<String> csvColumns = [
    'Title',
    'Description',
    'Project',
    'Section',
    'Parent task',
    'Status',
    'Priority',
    'Start date',
    'Due date',
    'Due time',
    'Estimate (min)',
    'Tags',
    'Checklist',
    'Repeat',
    'Milestone',
    'Completed at',
    'Notes',
  ];

  static String _cell(Object? v) {
    final s = '${v ?? ''}';
    if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  /// One row per task (subtasks included, archived ones left out unless
  /// [includeArchived]). Dates are ISO (yyyy-MM-dd) so spreadsheets read them.
  static String tasksCsv(PlanStore store, {String? projectId, bool includeArchived = false}) {
    final tasks = (projectId == null
            ? (includeArchived ? store.allTasks : store.tasks)
            : store.tasksOfProject(projectId, includeArchived: includeArchived))
        .toList()
      ..sort((a, b) => compareTasks(a, b, TaskSort.dueDate));
    final b = StringBuffer()..writeln(csvColumns.map(_cell).join(','));
    for (final t in tasks) {
      final m = t.dueMinutes;
      b.writeln([
        t.title,
        t.description,
        store.project(t.projectId)?.name ?? '',
        store.section(t.sectionId)?.name ?? '',
        store.task(t.parentId)?.title ?? '',
        t.status.label,
        t.priority.label,
        dayKey(t.startDate) ?? '',
        dayKey(t.dueDate) ?? '',
        m == null ? '' : '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
        t.estimateMinutes ?? '',
        t.tags.join('; '),
        t.checklist.map((c) => '${c.done ? '[x]' : '[ ]'} ${c.title}').join('; '),
        t.recurrence?.summary ?? '',
        store.milestone(t.milestoneId)?.title ?? '',
        t.completedAt?.toIso8601String() ?? '',
        t.notes,
      ].map(_cell).join(','));
    }
    return b.toString();
  }

  static Future<Directory> _exportDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/omni_plan_exports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String safeName(String s) {
    final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? 'Omni Plan' : (cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned);
  }

  static Future<File> writeFile(String name, List<int> bytes, {Directory? dir}) async {
    final d = dir ?? await _exportDir();
    final file = File('${d.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    if (await file.length() != bytes.length) {
      throw const FileSystemException('The file was not written completely.');
    }
    return file;
  }

  static Future<File> writeCsv(String baseName, String csv, {Directory? dir}) {
    // A byte-order mark makes Excel open UTF-8 text correctly.
    final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];
    return writeFile('${safeName(baseName)}.csv', bytes, dir: dir);
  }

  // --- PDF ---

  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> _pdfTheme() async {
    final cached = _theme;
    if (cached != null) return cached;
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    return _theme = pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static const _teal = PdfColor.fromInt(0xFF0B7F86);
  static const _muted = PdfColor.fromInt(0xFF5F6368);
  static const _line = PdfColor.fromInt(0xFFE1E7EB);

  static pw.Widget _heading(String t) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(t.toUpperCase(), style: pw.TextStyle(color: _teal, fontSize: 9, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
  );

  static pw.Widget _bar(Progress p) {
    final f = p.fraction ?? 0;
    return pw.Container(
      height: 6,
      decoration: pw.BoxDecoration(color: _line, borderRadius: pw.BorderRadius.circular(3)),
      child: pw.Row(
        children: [
          if (f > 0)
            pw.Expanded(
              flex: (f * 1000).round(),
              child: pw.Container(decoration: pw.BoxDecoration(color: _teal, borderRadius: pw.BorderRadius.circular(3))),
            ),
          if (f < 1) pw.Expanded(flex: ((1 - f) * 1000).round(), child: pw.SizedBox()),
        ],
      ),
    );
  }

  static pw.Widget _kv(String k, String v) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 110, child: pw.Text(k, style: const pw.TextStyle(color: _muted, fontSize: 9))),
        pw.Expanded(child: pw.Text(v, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
      ],
    ),
  );

  static pw.Widget _taskTable(List<PlanTask> tasks, PlanFormat fmt, PlanStore store, {bool project = false}) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: _teal),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5))),
      headers: ['Task', if (project) 'Project', 'Status', 'Priority', 'Due'],
      data: [
        for (final t in tasks)
          [
            t.isSubtask ? '   – ${t.title}' : t.title,
            if (project) store.project(t.projectId)?.name ?? '—',
            t.status.label,
            t.priority == Priority.none ? '—' : t.priority.label,
            t.dueDate == null ? '—' : fmt.date(t.dueDate!),
          ],
      ],
    );
  }

  /// A project report: summary, progress, milestones, overdue work and the
  /// full task list.
  static Future<List<int>> projectReportPdf(PlanStore store, Project p, {DateTime? now}) async {
    final theme = await _pdfTheme();
    final fmt = PlanFormat(store.prefs);
    final at = now ?? DateTime.now();
    final tasks = store.tasksOfProject(p.id);
    final progress = progressOf(tasks);
    final overdue = tasks.where((t) => t.isOverdue(at)).toList();
    final milestones = store.milestonesOf(p.id);
    final byStatus = {for (final s in TaskStatus.values) s: tasks.where((t) => t.status == s).length};
    final doc = pw.Document(theme: theme, title: '${p.name} report', author: 'Omni Plan');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (c) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Omni Plan · ${fmt.date(at)} · page ${c.pageNumber} of ${c.pagesCount}',
              style: const pw.TextStyle(color: _muted, fontSize: 8)),
        ),
        build: (c) => [
          pw.Text(p.name, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          if (p.description.isNotEmpty)
            pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(p.description, style: const pw.TextStyle(color: _muted))),
          _heading('Summary'),
          _kv('Status', p.isArchived ? 'Archived (${p.status.label})' : p.status.label),
          if (p.priority != Priority.none) _kv('Priority', p.priority.label),
          if (p.category.isNotEmpty) _kv('Category', p.category),
          if (p.startDate != null) _kv('Start date', fmt.date(p.startDate!)),
          if (p.dueDate != null) _kv('Target date', fmt.date(p.dueDate!)),
          if (store.goal(p.goalId) != null) _kv('Goal', store.goal(p.goalId)!.title),
          _heading('Progress'),
          _kv('Tasks', progress.total == 0 ? 'No tasks yet' : '${progress.done} of ${progress.total} done (${progress.percent}%)'),
          if (progress.total > 0) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: _bar(progress)),
          for (final e in byStatus.entries) _kv(e.key.label, '${e.value}'),
          _kv('Overdue', '${overdue.length}'),
          if (milestones.isNotEmpty) ...[
            _heading('Milestones'),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: _teal),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: ['Milestone', 'Target date', 'State'],
              data: [
                for (final m in milestones)
                  [
                    m.title,
                    m.dueDate == null ? '—' : fmt.date(m.dueDate!),
                    m.isDone ? 'Reached' : (m.isOverdue(at) ? 'Overdue' : 'Open'),
                  ],
              ],
            ),
          ],
          if (overdue.isNotEmpty) ...[_heading('Overdue tasks'), _taskTable(overdue, fmt, store)],
          _heading('All tasks'),
          if (tasks.isEmpty) pw.Text('No tasks yet.') else _taskTable(tasks, fmt, store),
        ],
      ),
    );
    return doc.save();
  }

  /// A report across all plans for [from]..[to] (inclusive), optionally for
  /// one project.
  static Future<List<int>> overviewReportPdf(
    PlanStore store, {
    required DateTime from,
    required DateTime to,
    String? projectId,
  }) async {
    final theme = await _pdfTheme();
    final fmt = PlanFormat(store.prefs);
    final now = DateTime.now();
    final stats = ReportStats.compute(store, from: from, to: to, projectId: projectId, now: now);
    final doc = pw.Document(theme: theme, title: 'Planning report', author: 'Omni Plan');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (c) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Omni Plan · page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(color: _muted, fontSize: 8)),
        ),
        build: (c) => [
          pw.Text('Planning report', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Text(
            '${fmt.date(from)} – ${fmt.date(to)}${projectId == null ? '' : ' · ${store.project(projectId)?.name ?? ''}'}',
            style: const pw.TextStyle(color: _muted),
          ),
          _heading('Tasks'),
          _kv('Completed in period', '${stats.completedInRange}'),
          _kv('Open now', '${stats.open}'),
          _kv('Overdue now', '${stats.overdue}'),
          _kv('Due in period', '${stats.dueInRange}'),
          _heading('By status'),
          for (final e in stats.byStatus.entries) _kv(e.key.label, '${e.value}'),
          _heading('By priority (open)'),
          for (final e in stats.byPriority.entries) _kv(e.key.label, '${e.value}'),
          if (stats.projects.isNotEmpty) ...[
            _heading('Projects'),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: _teal),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: ['Project', 'Status', 'Done', 'Progress', 'Target'],
              data: [
                for (final (p, pr) in stats.projects)
                  [
                    p.name,
                    p.status.label,
                    pr.total == 0 ? '—' : '${pr.done}/${pr.total}',
                    pr.percent == null ? '—' : '${pr.percent}%',
                    p.dueDate == null ? '—' : fmt.date(p.dueDate!),
                  ],
              ],
            ),
          ],
          _heading('Completed per week'),
          for (final (week, n) in stats.weekly) _kv('Week of ${fmt.date(week)}', '$n'),
        ],
      ),
    );
    return doc.save();
  }
}

/// Numbers behind the Reports page and the PDF overview, all computed from
/// stored tasks.
class ReportStats {
  final int completedInRange;
  final int dueInRange;
  final int open;
  final int overdue;
  final Map<TaskStatus, int> byStatus;
  final Map<Priority, int> byPriority;
  final List<(Project, Progress)> projects;

  /// (Monday of the week, tasks completed that week), oldest first.
  final List<(DateTime, int)> weekly;

  /// (first day of the month, tasks completed), oldest first.
  final List<(DateTime, int)> monthly;
  final Progress milestones;

  /// Planned (due) vs completed per week, for the planned-versus-actual chart.
  final List<(DateTime, int, int)> plannedVsDone;

  const ReportStats({
    required this.completedInRange,
    required this.dueInRange,
    required this.open,
    required this.overdue,
    required this.byStatus,
    required this.byPriority,
    required this.projects,
    required this.weekly,
    required this.monthly,
    required this.milestones,
    required this.plannedVsDone,
  });

  static DateTime mondayOf(DateTime d) => dateOnly(d).subtract(Duration(days: d.weekday - 1));

  static ReportStats compute(
    PlanStore store, {
    required DateTime from,
    required DateTime to,
    String? projectId,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final start = dateOnly(from);
    final end = dateOnly(to).add(const Duration(days: 1));
    bool inRange(DateTime? d) => d != null && !d.isBefore(start) && d.isBefore(end);
    final tasks = [
      for (final t in store.tasks)
        if (projectId == null || t.projectId == projectId) t,
    ];
    final completed = tasks.where((t) => t.isDone && inRange(t.completedAt)).toList();
    final weeks = <DateTime, int>{};
    final planned = <DateTime, int>{};
    for (var w = mondayOf(start); w.isBefore(end); w = DateTime(w.year, w.month, w.day + 7)) {
      weeks[w] = 0;
      planned[w] = 0;
    }
    for (final t in completed) {
      final w = mondayOf(t.completedAt!);
      weeks[w] = (weeks[w] ?? 0) + 1;
    }
    for (final t in tasks) {
      if (inRange(t.dueDate)) {
        final w = mondayOf(t.dueDate!);
        planned[w] = (planned[w] ?? 0) + 1;
      }
    }
    final months = <DateTime, int>{};
    for (var m = DateTime(start.year, start.month); m.isBefore(end); m = DateTime(m.year, m.month + 1)) {
      months[m] = 0;
    }
    for (final t in completed) {
      final m = DateTime(t.completedAt!.year, t.completedAt!.month);
      months[m] = (months[m] ?? 0) + 1;
    }
    final projects = [
      for (final p in store.projects)
        if (projectId == null || p.id == projectId) (p, store.projectProgress(p.id)),
    ]..sort((a, b) => a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase()));
    final milestones = [
      for (final m in store.milestones)
        if (projectId == null || m.projectId == projectId) m,
    ];
    final open = tasks.where((t) => !t.isDone).toList();
    return ReportStats(
      completedInRange: completed.length,
      dueInRange: tasks.where((t) => inRange(t.dueDate)).length,
      open: open.length,
      overdue: open.where((t) => t.isOverdue(at)).length,
      byStatus: {for (final s in TaskStatus.values) s: tasks.where((t) => t.status == s).length},
      byPriority: {for (final p in Priority.values.reversed) p: open.where((t) => t.priority == p).length},
      projects: projects,
      weekly: [for (final e in weeks.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) (e.key, e.value)],
      monthly: [for (final e in months.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) (e.key, e.value)],
      milestones: milestoneProgress(milestones),
      plannedVsDone: [
        for (final w in (weeks.keys.toList()..sort())) (w, planned[w] ?? 0, weeks[w] ?? 0),
      ],
    );
  }
}
