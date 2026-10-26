import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/core/widgets/omni_plan_fields.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/tasks/task_pickers.dart';
import 'package:provider/provider.dart';

/// Create or edit a milestone. A milestone always belongs to a project.
class MilestoneEditorPage extends StatefulWidget {
  final String? projectId;
  final String? milestoneId;

  const MilestoneEditorPage({super.key, this.projectId, this.milestoneId});

  @override
  State<MilestoneEditorPage> createState() => _MilestoneEditorPageState();
}

class _MilestoneEditorPageState extends State<MilestoneEditorPage> {
  late Milestone _m;
  late final bool _isNew;
  final _title = TextEditingController();
  final _description = TextEditingController();
  Set<String> _linked = {};
  bool _saving = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    final store = context.read<PlanStore>();
    final existing = store.milestone(widget.milestoneId);
    _isNew = existing == null;
    final projectId = widget.projectId ?? (store.activeProjects.isEmpty ? '' : store.activeProjects.first.id);
    _m = existing ?? store.draftMilestone(projectId);
    _title.text = _m.title;
    _description.text = _m.description;
    _linked = {for (final t in store.tasksOfMilestone(_m.id)) t.id};
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = 'Give the milestone a title.');
      return;
    }
    setState(() => _saving = true);
    final store = context.read<PlanStore>();
    final ok = await runPlanAction(context, () async {
      final saved = await store.saveMilestone(_m.copyWith(title: _title.text, description: _description.text.trim()));
      await store.setMilestoneTasks(saved, _linked);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context);
      showPlanSnack(context, _isNew ? 'Milestone added' : 'Changes saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final project = store.project(_m.projectId);
    final tasks = project == null ? const <PlanTask>[] : store.tasksOfProject(project.id).where((t) => !t.isSubtask).toList();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: omniListAppBar(context, _isNew ? 'New milestone' : 'Edit milestone'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 24),
        children: [
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            autofocus: _isNew,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Milestone title *', errorText: _titleError),
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
          ),
          const SizedBox(height: 12),
          OmniTapField(
            label: 'Project *',
            value: project?.name,
            icon: Icons.folder_outlined,
            errorText: project == null ? 'Choose a project' : null,
            onTap: () async {
              final picked = await pickProject(context, project?.id, allowNone: false);
              if (picked?.value != null) {
                setState(() {
                  _m = _m.copyWith(projectId: picked!.value);
                  _linked = {};
                });
              }
            },
          ),
          const SizedBox(height: 12),
          OmniTapField(
            label: 'Target date',
            value: _m.dueDate == null ? null : fmt.date(_m.dueDate!),
            icon: Icons.calendar_today_rounded,
            onTap: () async {
              final d = await pickDate(context, _m.dueDate);
              if (d != null) setState(() => _m = _m.copyWith(dueDate: d));
            },
            onClear: () => setState(() => _m = _m.copyWith(clearDue: true)),
          ),
          const SizedBox(height: 12),
          OmniTextArea(label: 'Description', controller: _description, minLines: 3),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: OmniDesignTokens.sectionGap),
            const OmniSectionHeader(title: 'Linked tasks'),
            const SizedBox(height: 4),
            Text('The milestone shows how many of these are done.', style: theme.textTheme.bodySmall),
            for (final t in tasks)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _linked.contains(t.id),
                title: Text(t.title),
                subtitle: t.dueDate == null ? null : Text(fmt.due(t)),
                onChanged: (v) => setState(() => v == true ? _linked.add(t.id) : _linked.remove(t.id)),
              ),
          ],
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12 + bottom),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _saving || project == null ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_isNew ? 'Create milestone' : 'Save changes'),
          ),
        ),
      ),
    );
  }
}

class MilestoneDetailPage extends StatelessWidget {
  final String milestoneId;

  const MilestoneDetailPage({super.key, required this.milestoneId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final m = store.milestone(milestoneId);
    if (m == null) {
      return Scaffold(
        appBar: omniListAppBar(context, 'Milestone'),
        body: const OmniEmptyState(icon: Icons.search_off_rounded, title: 'This milestone no longer exists', message: 'It was deleted.'),
      );
    }
    final fmt = PlanFormat(store.prefs);
    final project = store.project(m.projectId);
    final tasks = store.tasksOfMilestone(m.id);
    final progress = store.milestoneTaskProgress(m.id);
    final overdue = m.isOverdue(DateTime.now());
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
        centerTitle: true,
        title: Text('Milestone', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Edit milestone',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MilestoneEditorPage(milestoneId: m.id, projectId: m.projectId)),
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete milestone',
            onPressed: () async {
              final ok = await confirmAction(
                context,
                title: 'Delete milestone?',
                message: '"${m.title}" is deleted. Its linked tasks stay in the project.',
                confirmLabel: 'Delete',
              );
              if (ok && context.mounted) {
                await store.deleteMilestone(m);
                if (context.mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 24 + bottom),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
            child: OmniSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OmniIconTile(
                        icon: Icons.flag_rounded,
                        color: m.isDone ? OmniDesignTokens.success : (project?.colorValue ?? OmniDesignTokens.categoryNfc),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(m.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OmniStatusPill(
                        label: m.isDone ? 'Reached' : (overdue ? 'Overdue' : 'Open'),
                        color: m.isDone ? OmniDesignTokens.success : (overdue ? theme.colorScheme.error : theme.colorScheme.primary),
                      ),
                      if (m.dueDate != null) OmniStatusPill(label: fmt.date(m.dueDate!), icon: Icons.event_rounded, color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                  if (m.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(m.description, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                  ],
                  if (project != null) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => openProject(context, project),
                      child: Text('Project: ${project.name}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: OmniDesignTokens.sectionGap),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset),
            child: OmniSectionHeader(title: tasks.isEmpty ? 'Linked tasks' : 'Linked tasks · ${progress.label}'),
          ),
          if (tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 6, OmniDesignTokens.pageInset, 4),
              child: OmniProgressBar(fraction: progress.fraction),
            ),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: OmniDesignTokens.pageInset, vertical: 4),
              child: Text('No tasks are linked. Edit the milestone to link tasks of the project.', style: theme.textTheme.bodySmall),
            ),
          for (final t in tasks) TaskRow(task: t, showProject: false, onTap: () => openTask(context, t)),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12 + bottom),
        child: SizedBox(
          height: 52,
          child: m.isDone
              ? OutlinedButton.icon(
                  onPressed: () => store.setMilestoneDone(m, false),
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Mark as not reached'),
                )
              : FilledButton.icon(
                  onPressed: () => store.setMilestoneDone(m, true),
                  icon: const Icon(Icons.flag_rounded),
                  label: const Text('Mark as reached'),
                ),
        ),
      ),
    );
  }
}
