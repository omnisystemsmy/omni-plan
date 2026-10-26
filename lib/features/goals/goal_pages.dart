import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_form_kit.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/core/widgets/omni_plan_fields.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:provider/provider.dart';

enum _GoalFilter {
  active('Active'),
  completed('Completed'),
  overdue('Overdue'),
  archived('Archived');

  final String label;
  const _GoalFilter(this.label);
}

/// Goals: intended outcomes, each with a target date and linked projects.
/// Progress is the tasks of the linked projects (see `PlanStore.goalProgress`).
class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  _GoalFilter _filter = _GoalFilter.active;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final now = DateTime.now();
    final q = _query.trim().toLowerCase();
    final source = _filter == _GoalFilter.archived ? store.archivedGoals : store.goals;
    final list = [
      for (final g in source)
        if ((q.isEmpty || '${g.title} ${g.description} ${g.category}'.toLowerCase().contains(q)) &&
            switch (_filter) {
              _GoalFilter.active => g.status == GoalStatus.active,
              _GoalFilter.completed => g.status == GoalStatus.completed,
              _GoalFilter.overdue => g.isOverdue(now),
              _GoalFilter.archived => true,
            })
          g,
    ];
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: omniListAppBar(context, 'Goals'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: OmniDesignTokens.primary,
        foregroundColor: Colors.white,
        onPressed: () => newGoal(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New goal'),
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: 96 + bottom),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 4, OmniDesignTokens.pageInset, 12),
            child: OmniSearchField(hintText: 'Search goals...', onChanged: (v) => setState(() => _query = v)),
          ),
          OmniFilterChips<_GoalFilter>(
            items: [for (final f in _GoalFilter.values) (value: f, label: f.label, icon: null)],
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: OmniEmptyState(
                icon: Icons.flag_outlined,
                title: store.goals.isEmpty && _filter != _GoalFilter.archived ? 'No goals yet' : 'No goals here',
                message: 'A goal is an outcome you are working towards. Link projects to it to track progress.',
                actionLabel: 'New goal',
                onAction: () => newGoal(context),
              ),
            ),
          for (final g in list)
            Padding(
              padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 10),
              child: GoalCard(goal: g),
            ),
        ],
      ),
    );
  }
}

class GoalCard extends StatelessWidget {
  final Goal goal;
  const GoalCard({super.key, required this.goal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final progress = store.goalProgress(goal.id);
    final projects = store.projectsOfGoal(goal.id);
    final overdue = goal.isOverdue(DateTime.now());
    return OmniSurfaceCard(
      onTap: () => openGoal(context, goal),
      semanticLabel: '${goal.title}, ${goal.status.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const OmniIconTile(icon: Icons.flag_rounded, color: OmniDesignTokens.categoryNfc, size: 42, iconSize: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      [
                        if (goal.targetDate != null) 'Target ${fmt.date(goal.targetDate!)}',
                        '${projects.length} ${projects.length == 1 ? 'project' : 'projects'}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: overdue ? theme.colorScheme.error : null),
                    ),
                  ],
                ),
              ),
              OmniStatusPill(
                label: overdue ? 'Overdue' : goal.status.label,
                color: overdue ? theme.colorScheme.error : goal.status.color,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (progress.total == 0)
            Text(projects.isEmpty ? 'Link a project to track progress' : 'No tasks in the linked projects yet',
                style: theme.textTheme.bodySmall)
          else ...[
            Row(
              children: [
                Expanded(child: Text(progress.label, style: theme.textTheme.bodySmall)),
                Text('${progress.percent}%', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            OmniProgressBar(fraction: progress.fraction, color: OmniDesignTokens.categoryNfc),
          ],
        ],
      ),
    );
  }
}

class GoalEditorPage extends StatefulWidget {
  final String? goalId;
  const GoalEditorPage({super.key, this.goalId});

  @override
  State<GoalEditorPage> createState() => _GoalEditorPageState();
}

class _GoalEditorPageState extends State<GoalEditorPage> {
  late Goal _g;
  late final bool _isNew;
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  Set<String> _projects = {};
  bool _saving = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final store = context.read<PlanStore>();
    final existing = store.goal(widget.goalId);
    _isNew = existing == null;
    _g = existing ?? store.draftGoal();
    _title.text = _g.title;
    _description.text = _g.description;
    _notes.text = _g.notes;
    _projects = {for (final p in store.projectsOfGoal(_g.id)) p.id};
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = 'Give the goal a title.');
      return;
    }
    setState(() => _saving = true);
    final store = context.read<PlanStore>();
    Goal? saved;
    final ok = await runPlanAction(
      context,
      () async => saved = await store.saveGoal(
        _g.copyWith(title: _title.text, description: _description.text.trim(), notes: _notes.text.trim()),
        projectIds: _projects,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, _isNew ? saved : null);
      showPlanSnack(context, _isNew ? 'Goal created' : 'Changes saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: omniListAppBar(context, _isNew ? 'New goal' : 'Edit goal'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 24),
        children: [
          OmniFormSection(
            title: 'Goal',
            children: [
              TextField(
                controller: _title,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Goal title *', errorText: _titleError),
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
              ),
              OmniTextArea(label: 'Description', controller: _description, minLines: 3, hint: 'What does success look like?'),
              DropdownButtonFormField<String>(
                initialValue: planCategories.contains(_g.category) ? _g.category : '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('No category')),
                  for (final c in planCategories) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _g = _g.copyWith(category: v ?? '')),
              ),
              OmniTapField(
                label: 'Target date',
                value: _g.targetDate == null ? null : fmt.date(_g.targetDate!),
                icon: Icons.calendar_today_rounded,
                onTap: () async {
                  final d = await pickDate(context, _g.targetDate);
                  if (d != null) setState(() => _g = _g.copyWith(targetDate: d));
                },
                onClear: () => setState(() => _g = _g.copyWith(clearTarget: true)),
              ),
              OmniSegmented<GoalStatus>(
                label: 'Status',
                options: [for (final s in GoalStatus.values) OmniOption(s, s.label)],
                value: _g.status,
                onChanged: (s) => setState(() => _g = _g.copyWith(status: s)),
              ),
            ],
          ),
          OmniFormSection(
            title: 'Linked projects',
            children: [
              if (store.projects.isEmpty)
                Text('No projects yet. Create a project and link it here later.', style: Theme.of(context).textTheme.bodySmall),
              for (final p in store.projects)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _projects.contains(p.id),
                  title: Text(p.name),
                  subtitle: p.goalId != null && p.goalId != _g.id
                      ? Text('Now linked to "${store.goal(p.goalId)?.title ?? 'another goal'}"')
                      : null,
                  onChanged: (v) => setState(() => v == true ? _projects.add(p.id) : _projects.remove(p.id)),
                ),
            ],
          ),
          OmniFormSection(
            title: 'Notes',
            collapsible: true,
            initiallyOpen: _g.notes.isNotEmpty,
            children: [OmniTextArea(label: 'Notes', controller: _notes)],
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12 + bottom),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_isNew ? 'Create goal' : 'Save changes'),
          ),
        ),
      ),
    );
  }
}

class GoalDetailPage extends StatelessWidget {
  final String goalId;
  const GoalDetailPage({super.key, required this.goalId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final g = store.goal(goalId);
    if (g == null) {
      return Scaffold(
        appBar: omniListAppBar(context, 'Goal'),
        body: const OmniEmptyState(icon: Icons.search_off_rounded, title: 'This goal no longer exists', message: 'It was deleted.'),
      );
    }
    final fmt = PlanFormat(store.prefs);
    final projects = store.projectsOfGoal(g.id);
    final milestones = [for (final p in projects) ...store.milestonesOf(p.id)];
    final history = store.activity.where((a) => a.entityId == g.id).take(10).toList();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
        centerTitle: true,
        title: Text('Goal', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Edit goal',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GoalEditorPage(goalId: g.id))),
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'archive') {
                await store.setGoalArchived(g, !g.isArchived);
              } else if (v == 'delete') {
                final ok = await confirmAction(
                  context,
                  title: 'Delete goal?',
                  message: '"${g.title}" is deleted. Linked projects are kept and simply unlinked.',
                  confirmLabel: 'Delete',
                );
                if (ok && context.mounted) {
                  await store.deleteGoal(g);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'archive', child: Text(g.isArchived ? 'Restore' : 'Archive')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 24 + bottom),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
            child: GoalCard(goal: g),
          ),
          if (g.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 16, OmniDesignTokens.pageInset, 0),
              child: Text(g.description, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            ),
          if (g.completedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 0),
              child: Text('Completed ${fmt.date(g.completedAt!)}', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: OmniDesignTokens.sectionGap),
          OmniListSection(
            title: 'Linked projects',
            children: [
              if (projects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
                  child: Text('Edit the goal to link projects.', style: theme.textTheme.bodySmall),
                ),
              for (final p in projects)
                Padding(
                  padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 10),
                  child: ProjectCard(project: p, onTap: () => openProject(context, p)),
                ),
            ],
          ),
          if (milestones.isNotEmpty) ...[
            const SizedBox(height: 8),
            OmniListSection(
              title: 'Milestones',
              children: [for (final m in milestones) MilestoneRow(milestone: m, onTap: () => openMilestone(context, m))],
            ),
          ],
          if (g.notes.isNotEmpty) ...[
            const SizedBox(height: OmniDesignTokens.sectionGap),
            const OmniListSection(title: 'Notes', children: []),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
              child: Text(g.notes, style: theme.textTheme.bodyMedium),
            ),
          ],
          if (history.isNotEmpty) ...[
            const SizedBox(height: OmniDesignTokens.sectionGap),
            const OmniListSection(title: 'History', children: []),
            for (final a in history)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset, vertical: 3),
                child: Text('${a.action} · ${fmt.dateTime(a.at)}', style: theme.textTheme.bodySmall),
              ),
          ],
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12 + bottom),
        child: SizedBox(
          height: 52,
          child: g.status == GoalStatus.completed
              ? OutlinedButton.icon(
                  onPressed: () => store.saveGoal(g.copyWith(status: GoalStatus.active)),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Mark as active'),
                )
              : FilledButton.icon(
                  onPressed: () => store.saveGoal(g.copyWith(status: GoalStatus.completed)),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Mark goal achieved'),
                ),
        ),
      ),
    );
  }
}
