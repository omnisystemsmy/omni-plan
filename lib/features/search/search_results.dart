import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/templates/catalogue_data.dart';
import 'package:omni_plan/features/templates/template_library.dart';
import 'package:omni_plan/features/templates/template_models.dart';
import 'package:omni_plan/features/templates/template_sheets.dart';
import 'package:provider/provider.dart';

/// Everything that matches [query]: tasks (title, description, notes, tags),
/// projects (name, description, notes), goals, milestones and templates,
/// grouped by kind. Archived records are left out.
class SearchHits {
  final List<PlanTask> tasks;
  final List<Project> projects;
  final List<Goal> goals;
  final List<Milestone> milestones;
  final List<PlanTemplate> templates;

  const SearchHits(this.tasks, this.projects, this.goals, this.milestones, this.templates);

  bool get isEmpty =>
      tasks.isEmpty && projects.isEmpty && goals.isEmpty && milestones.isEmpty && templates.isEmpty;

  static SearchHits of(PlanStore store, String query) {
    final q = query.trim().toLowerCase();
    bool has(List<String> parts) => parts.join(' ').toLowerCase().contains(q);
    return SearchHits(
      [
        for (final t in store.tasks)
          if (has([t.title, t.description, t.notes, ...t.tags])) t,
      ]..sort((a, b) => (a.isDone ? 1 : 0).compareTo(b.isDone ? 1 : 0)),
      [
        for (final p in store.projects)
          if (has([p.name, p.description, p.notes, p.category])) p,
      ],
      [
        for (final g in store.goals)
          if (has([g.title, g.description, g.notes])) g,
      ],
      [
        for (final m in store.milestones)
          if (has([m.title, m.description])) m,
      ],
      TemplateLibrary.search(query, store.customTemplates),
    );
  }
}

class SearchResultsList extends StatelessWidget {
  final String query;

  const SearchResultsList({super.key, required this.query});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final hits = SearchHits.of(store, query);
    final fmt = PlanFormat(store.prefs);
    if (hits.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 48),
        child: OmniEmptyState(
          icon: Icons.search_off_rounded,
          title: 'Nothing found',
          message: 'Try a different word. Search covers tasks, projects, goals, milestones and templates.',
        ),
      );
    }
    const limit = 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hits.tasks.isNotEmpty) ...[
          GroupHeader('Tasks', count: hits.tasks.length),
          for (final t in hits.tasks.take(limit))
            TaskRow(task: t, onTap: () => openTask(context, t)),
        ],
        if (hits.projects.isNotEmpty) ...[
          GroupHeader('Projects', count: hits.projects.length),
          for (final p in hits.projects.take(limit))
            OmniMenuRow(
              icon: p.iconData,
              iconColor: p.colorValue,
              useTile: true,
              title: p.name,
              subtitle: '${p.status.label} · ${store.projectProgress(p.id).label}',
              onTap: () => openProject(context, p),
            ),
        ],
        if (hits.goals.isNotEmpty) ...[
          GroupHeader('Goals', count: hits.goals.length),
          for (final g in hits.goals.take(limit))
            OmniMenuRow(
              icon: Icons.flag_rounded,
              iconColor: OmniDesignTokens.categoryNfc,
              useTile: true,
              title: g.title,
              subtitle: g.targetDate == null ? g.status.label : '${g.status.label} · ${fmt.date(g.targetDate!)}',
              onTap: () => openGoal(context, g),
            ),
        ],
        if (hits.milestones.isNotEmpty) ...[
          GroupHeader('Milestones', count: hits.milestones.length),
          for (final m in hits.milestones.take(limit))
            MilestoneRow(milestone: m, onTap: () => openMilestone(context, m)),
        ],
        if (hits.templates.isNotEmpty) ...[
          GroupHeader('Templates', count: hits.templates.length),
          for (final t in hits.templates.take(limit))
            OmniMenuRow(
              icon: t.icon,
              iconColor: t.color,
              useTile: true,
              title: t.name,
              subtitle: categoryById(t.categoryId).name,
              onTap: () => showTemplateDetailSheet(context, t),
            ),
        ],
      ],
    );
  }
}
