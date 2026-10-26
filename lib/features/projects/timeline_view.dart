import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:provider/provider.dart';

/// A Gantt-style timeline of one project: each dated task is a bar from its
/// start date (or its due date when it has no start) to its due date,
/// grouped by section, with milestones as flags and a line for today.
class ProjectTimeline extends StatefulWidget {
  final Project project;

  const ProjectTimeline({super.key, required this.project});

  @override
  State<ProjectTimeline> createState() => _ProjectTimelineState();
}

class _ProjectTimelineState extends State<ProjectTimeline> {
  double _dayWidth = 22;
  static const double _labelWidth = 132;
  static const double _rowHeight = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final p = widget.project;
    final tasks = store.tasksOfProject(p.id).where((t) => !t.isSubtask).toList();
    final dated = tasks.where((t) => t.dueDate != null || t.startDate != null).toList();
    final undated = tasks.where((t) => t.dueDate == null && t.startDate == null).toList();
    final milestones = store.milestonesOf(p.id).where((m) => m.dueDate != null).toList();
    final bottom = MediaQuery.paddingOf(context).bottom;

    if (dated.isEmpty && milestones.isEmpty) {
      return OmniEmptyState(
        icon: Icons.view_timeline_outlined,
        title: 'Nothing on the timeline yet',
        message: 'Give tasks a start or due date and they appear here as bars.',
        actionLabel: 'Add a task',
        onAction: () => newTask(context, projectId: p.id),
      );
    }

    DateTime startOf(PlanTask t) => dateOnly(t.startDate ?? t.dueDate!);
    DateTime endOf(PlanTask t) => dateOnly(t.dueDate ?? t.startDate!);
    final today = dateOnly(DateTime.now());
    final points = <DateTime>[
      for (final t in dated) ...[startOf(t), endOf(t)],
      for (final m in milestones) dateOnly(m.dueDate!),
      ?p.startDate,
      ?p.dueDate,
    ];
    var first = points.reduce((a, b) => a.isBefore(b) ? a : b);
    var last = points.reduce((a, b) => a.isAfter(b) ? a : b);
    first = first.subtract(const Duration(days: 2));
    last = last.add(const Duration(days: 3));
    // Use UTC days for counting so daylight-saving changes never shift a bar.
    int dayIndex(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
    final days = dayIndex(last) + 1;
    final width = days * _dayWidth;

    // Rows: sections in order, then tasks without a section.
    final rows = <(String?, PlanTask?)>[];
    for (final s in store.sectionsOf(p.id)) {
      final inSection = dated.where((t) => t.sectionId == s.id).toList()..sort((a, b) => startOf(a).compareTo(startOf(b)));
      if (inSection.isEmpty) continue;
      rows.add((s.name, null));
      rows.addAll([for (final t in inSection) (null, t)]);
    }
    final loose = dated.where((t) => store.section(t.sectionId) == null).toList()..sort((a, b) => startOf(a).compareTo(startOf(b)));
    if (loose.isNotEmpty) {
      if (rows.isNotEmpty) rows.add(('Other tasks', null));
      rows.addAll([for (final t in loose) (null, t)]);
    }

    Widget barFor(PlanTask t) {
      final s = dayIndex(startOf(t));
      final e = math.max(s, dayIndex(endOf(t)));
      final overdue = t.isOverdue(DateTime.now());
      final color = t.isDone
          ? OmniDesignTokens.success
          : overdue
          ? theme.colorScheme.error
          : p.colorValue;
      return Positioned(
        left: s * _dayWidth + 2,
        top: 9,
        width: (e - s + 1) * _dayWidth - 4,
        height: _rowHeight - 18,
        child: Tooltip(
          message: '${t.title}\n${fmt.date(startOf(t))} – ${fmt.date(endOf(t))} · ${t.status.label}',
          child: InkWell(
            onTap: () => openTask(context, t),
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: t.isDone ? 0.55 : 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      );
    }

    final months = <(int, String)>[];
    for (var d = first; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
      if (d == first || d.day == 1) months.add((dayIndex(d), PlanFormat.monthYear(d)));
    }

    final chart = SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month and day scale.
          SizedBox(
            height: 40,
            child: Stack(
              children: [
                for (final (i, label) in months)
                  Positioned(
                    left: i * _dayWidth + 4,
                    top: 0,
                    child: Text(label, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                for (var i = 0; i < days; i++)
                  Positioned(
                    left: i * _dayWidth,
                    top: 20,
                    width: _dayWidth,
                    child: Center(
                      child: Text(
                        '${DateTime(first.year, first.month, first.day + i).day}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: DateTime(first.year, first.month, first.day + i) == today ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                          fontWeight: DateTime(first.year, first.month, first.day + i) == today ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (milestones.isNotEmpty)
            SizedBox(
              height: 28,
              child: Stack(
                children: [
                  for (final m in milestones)
                    Positioned(
                      left: dayIndex(m.dueDate!) * _dayWidth + _dayWidth / 2 - 9,
                      top: 4,
                      child: Tooltip(
                        message: '${m.title} · ${fmt.date(m.dueDate!)}',
                        child: InkWell(
                          onTap: () => openMilestone(context, m),
                          child: Icon(Icons.flag_rounded, size: 18, color: m.isDone ? OmniDesignTokens.success : OmniDesignTokens.categoryNfc),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          for (final (header, task) in rows)
            SizedBox(
              height: header != null ? 30 : _rowHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor, width: 0.5))),
                    ),
                  ),
                  if (task != null) barFor(task),
                ],
              ),
            ),
        ],
      ),
    );

    final labels = SizedBox(
      width: _labelWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          if (milestones.isNotEmpty)
            SizedBox(height: 28, child: Align(alignment: Alignment.centerLeft, child: Text('Milestones', style: theme.textTheme.labelSmall))),
          for (final (header, task) in rows)
            SizedBox(
              height: header != null ? 30 : _rowHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: header != null
                    ? Text(header, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant))
                    : InkWell(
                        onTap: () => openTask(context, task),
                        child: Text(
                          task!.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: task.isDone ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );

    final todayIndex = dayIndex(today);
    return ListView(
      padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 12, 0, 24 + bottom),
      children: [
        Row(
          children: [
            Expanded(child: Text('Tap a bar to open the task.', style: theme.textTheme.bodySmall)),
            IconButton(
              tooltip: 'Zoom out',
              onPressed: _dayWidth > 10 ? () => setState(() => _dayWidth -= 4) : null,
              icon: const Icon(Icons.zoom_out_rounded),
            ),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: _dayWidth < 46 ? () => setState(() => _dayWidth += 4) : null,
              icon: const Icon(Icons.zoom_in_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labels,
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Stack(
                  children: [
                    chart,
                    if (todayIndex >= 0 && todayIndex < days)
                      Positioned(
                        left: todayIndex * _dayWidth + _dayWidth / 2,
                        top: 36,
                        bottom: 0,
                        child: Container(width: 2, color: theme.colorScheme.primary.withValues(alpha: 0.6)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (undated.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16, right: OmniDesignTokens.pageInset),
            child: Text(
              '${undated.length} ${undated.length == 1 ? 'task has' : 'tasks have'} no dates and are not shown.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
