import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/export_service.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/pro/plan_service.dart';
import 'package:omni_plan/features/pro/pro_gate.dart';
import 'package:omni_plan/features/reports/charts.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/shared/share_file.dart';
import 'package:omni_plan/features/tasks/task_pickers.dart';
import 'package:provider/provider.dart';

enum ReportRange {
  week('Last 7 days', 7),
  month('Last 30 days', 30),
  quarter('Last 90 days', 90),
  year('Last 12 months', 365);

  final String label;
  final int days;
  const ReportRange(this.label, this.days);
}

/// Planning reports across all projects, or one. Every figure is counted
/// from stored tasks; nothing is estimated or scored.
class ReportsPage extends StatefulWidget {
  final String? projectId;

  const ReportsPage({super.key, this.projectId});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportRange _range = ReportRange.month;
  late String? _projectId = widget.projectId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    return Scaffold(
      appBar: omniListAppBar(context, 'Reports'),
      body: ReportsView(
        range: _range,
        projectId: _projectId,
        onRange: (r) => setState(() => _range = r),
        onProject: widget.projectId != null
            ? null
            : () async {
                final picked = await pickOption<String>(
                  context,
                  title: 'Project',
                  icon: Icons.folder_outlined,
                  noneLabel: 'All projects',
                  current: _projectId,
                  options: [for (final p in store.projects) (p.id, p.name)],
                );
                if (picked != null) setState(() => _projectId = picked.value);
              },
      ),
    );
  }
}

/// The report body, also used inside a project's Reports tab.
class ReportsView extends StatelessWidget {
  final ReportRange range;
  final String? projectId;
  final ValueChanged<ReportRange> onRange;
  final VoidCallback? onProject;
  final bool embedded;

  const ReportsView({
    super.key,
    required this.range,
    required this.projectId,
    required this.onRange,
    this.onProject,
    this.embedded = false,
  });

  Future<void> _exportPdf(BuildContext context, DateTime from, DateTime to) async {
    if (!await ProGate.ensure(context, ProCapability.pdfReports) || !context.mounted) return;
    final store = context.read<PlanStore>();
    final project = store.project(projectId);
    await shareGeneratedFile(
      context,
      () async => ExportService.writeFile(
        '${ExportService.safeName(project == null ? 'Planning report' : '${project.name} report')}.pdf',
        project != null && embedded
            ? await ExportService.projectReportPdf(store, project)
            : await ExportService.overviewReportPdf(store, from: from, to: to, projectId: projectId),
      ),
      mimeType: 'application/pdf',
      doneMessage: 'Report shared',
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    if (!await ProGate.ensure(context, ProCapability.csvExport) || !context.mounted) return;
    final store = context.read<PlanStore>();
    final project = store.project(projectId);
    await shareGeneratedFile(
      context,
      () => ExportService.writeCsv(
        project == null ? 'Omni Plan tasks' : '${project.name} tasks',
        ExportService.tasksCsv(store, projectId: projectId),
      ),
      mimeType: 'text/csv',
      doneMessage: 'Tasks exported',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final now = DateTime.now();
    final to = dateOnly(now);
    final from = to.subtract(Duration(days: range.days - 1));
    final stats = ReportStats.compute(store, from: from, to: to, projectId: projectId, now: now);
    final project = store.project(projectId);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final total = stats.byStatus.values.fold<int>(0, (a, b) => a + b);
    // Weekly bars for up to 13 weeks; longer ranges show months.
    final useMonths = range.days > 100;
    final weekly = stats.weekly.length > 13 ? stats.weekly.sublist(stats.weekly.length - 13) : stats.weekly;

    return ListView(
      padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, embedded ? 12 : 4, OmniDesignTokens.pageInset, 24 + bottom),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in ReportRange.values)
              ChoiceChip(label: Text(r.label), selected: r == range, onSelected: (_) => onRange(r)),
            if (onProject != null)
              ActionChip(
                avatar: const Icon(Icons.folder_outlined, size: 18),
                label: Text(project?.name ?? 'All projects'),
                onPressed: onProject,
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (total == 0)
          OmniInlineEmpty(
            icon: Icons.insights_rounded,
            title: 'Not enough data yet',
            message: 'Reports fill in as you add and complete tasks.',
            onTap: () => newTask(context, projectId: projectId),
          )
        else ...[
          OmniSurfaceCard(
            child: Row(
              children: [
                Expanded(child: StatNumber(value: '${stats.completedInRange}', label: 'Completed')),
                Expanded(child: StatNumber(value: '${stats.open}', label: 'Remaining')),
                Expanded(child: StatNumber(value: '${stats.overdue}', label: 'Overdue')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (useMonths)
            ChartCard(
              title: 'Completed per month',
              subtitle: range.label,
              child: ColumnChart(
                items: [for (final (m, n) in stats.monthly) (PlanFormat.monthYear(m).substring(0, 3), n)],
              ),
            )
          else ...[
            ChartCard(
              title: 'Completed per week',
              subtitle: 'Week starting Monday · ${range.label}',
              child: ColumnChart(items: [for (final (w, n) in weekly) (PlanFormat.dayMonth(w), n)]),
            ),
            ChartCard(
              title: 'Planned versus done',
              subtitle: 'Tasks due each week, and tasks completed that week',
              child: PairedColumnChart(
                firstLabel: 'Due',
                secondLabel: 'Done',
                items: [
                  for (final (w, planned, done) in stats.plannedVsDone.length > 13
                      ? stats.plannedVsDone.sublist(stats.plannedVsDone.length - 13)
                      : stats.plannedVsDone)
                    (PlanFormat.dayMonth(w), planned, done),
                ],
              ),
            ),
          ],
          ChartCard(
            title: 'Tasks by status',
            subtitle: '$total tasks',
            child: BreakdownBars(
              items: [for (final e in stats.byStatus.entries) (e.key.label, e.value, e.key.icon)],
            ),
          ),
          ChartCard(
            title: 'Open tasks by priority',
            subtitle: '${stats.open} open',
            child: BreakdownBars(
              items: [for (final e in stats.byPriority.entries) (e.key.label, e.value, Icons.flag_outlined)],
            ),
          ),
          if (stats.milestones.total > 0)
            ChartCard(
              title: 'Milestones',
              subtitle: stats.milestones.label,
              child: OmniProgressBar(fraction: stats.milestones.fraction, height: 10),
            ),
          if (projectId == null && stats.projects.isNotEmpty)
            ChartCard(
              title: 'Project progress',
              subtitle: 'Done tasks out of all tasks in each project',
              child: Column(
                children: [
                  for (final (p, pr) in stats.projects)
                    InkWell(
                      onTap: () => openProject(context, p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(p.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                                Text(pr.percent == null ? 'No tasks' : '${pr.percent}%', style: theme.textTheme.bodySmall),
                              ],
                            ),
                            const SizedBox(height: 4),
                            OmniProgressBar(fraction: pr.fraction, color: p.colorValue),
                            if (p.dueDate != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('Target ${fmt.date(p.dueDate!)}', style: theme.textTheme.bodySmall),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _exportCsv(context),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Export CSV'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => _exportPdf(context, from, to),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF report'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'CSV and PDF exports are Omni Pro features. They are not backups: use Backup and restore in Profile to keep everything.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
