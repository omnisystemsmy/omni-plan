import 'package:flutter/material.dart';
import 'package:omni_plan/features/projects/project_detail_page.dart';
import 'package:omni_plan/core/plan_format.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_list.dart';
import 'package:omni_plan/core/widgets/omni_plan_fields.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/templates/catalogue_data.dart';
import 'package:omni_plan/features/templates/template_models.dart';
import 'package:provider/provider.dart';

/// Using a template: name the plan, choose its dates and the sections to
/// include, review the result, then create real, editable records and open
/// the new project.
class TemplateSetupPage extends StatefulWidget {
  final PlanTemplate template;
  const TemplateSetupPage({super.key, required this.template});

  @override
  State<TemplateSetupPage> createState() => _TemplateSetupPageState();
}

class _TemplateSetupPageState extends State<TemplateSetupPage> {
  late final TextEditingController _name = TextEditingController(text: widget.template.name);
  late DateTime _start = dateOnly(DateTime.now());
  DateTime? _due;
  late final Set<String> _sections = {for (final s in widget.template.sections) s.name};
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final span = widget.template.span;
    if (span != null && span > 0) _due = _start.add(Duration(days: span));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating) return;
    if (_sections.isEmpty) {
      showPlanSnack(context, 'Choose at least one section.');
      return;
    }
    setState(() => _creating = true);
    final store = context.read<PlanStore>();
    final navigator = Navigator.of(context);
    Project? project;
    final ok = await runPlanAction(context, () async {
      project = await store.createFromTemplate(
        widget.template,
        name: _name.text,
        start: _start,
        due: _due,
        category: categoryById(widget.template.categoryId).projectCategory,
        sectionNames: _sections,
      );
    });
    if (!mounted) return;
    setState(() => _creating = false);
    if (ok && project != null) {
      showPlanSnack(context, '${project!.name} is ready');
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => ProjectDetailPage(projectId: project!.id, initialTab: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fmt = PlanFormat(store.prefs);
    final t = widget.template;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final chosen = t.sections.where((s) => _sections.contains(s.name)).toList();
    final taskCount = chosen.fold<int>(0, (n, s) => n + s.tasks.length);

    return Scaffold(
      appBar: omniListAppBar(context, 'Use template'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 0, OmniDesignTokens.pageInset, 24),
        children: [
          OmniFormSection(
            title: 'Your plan',
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Project name *'),
              ),
              OmniTapField(
                label: 'Start date *',
                value: fmt.date(_start),
                icon: Icons.play_circle_outline_rounded,
                helper: t.usesDates ? 'Task and milestone dates are counted from this day.' : null,
                onTap: () async {
                  final d = await pickDate(context, _start);
                  if (d == null) return;
                  setState(() {
                    final span = t.span;
                    // Keep the suggested length when the start moves.
                    if (_due != null && span != null && span > 0) _due = d.add(Duration(days: span));
                    _start = d;
                  });
                },
              ),
              OmniTapField(
                label: 'Target completion date',
                value: _due == null ? null : fmt.date(_due!),
                icon: Icons.flag_outlined,
                onTap: () async {
                  final d = await pickDate(context, _due ?? _start, first: _start);
                  if (d != null) setState(() => _due = d);
                },
                onClear: () => setState(() => _due = null),
              ),
            ],
          ),
          OmniFormSection(
            title: 'Sections to include',
            children: [
              for (final s in t.sections)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _sections.contains(s.name),
                  title: Text(s.name),
                  subtitle: Text('${s.tasks.length} ${s.tasks.length == 1 ? 'task' : 'tasks'}'),
                  onChanged: (v) => setState(() => v == true ? _sections.add(s.name) : _sections.remove(s.name)),
                ),
            ],
          ),
          OmniFormSection(
            title: 'Review',
            children: [
              Text(
                '$taskCount tasks in ${chosen.length} sections${t.milestones.isEmpty ? '' : ', ${t.milestones.length} milestones'} will be created.',
                style: theme.textTheme.bodyMedium,
              ),
              for (final s in chosen) ...[
                Text(s.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                for (final task in s.tasks)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.radio_button_unchecked_rounded, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task.subtasks.isEmpty ? task.title : '${task.title} (${task.subtasks.length} subtasks)',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (task.dayOffset != null)
                          Text(
                            fmt.date(DateTime(_start.year, _start.month, _start.day + task.dayOffset!)),
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
              ],
              if (t.milestones.isNotEmpty) ...[
                Text('Milestones', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                for (final m in t.milestones)
                  Row(
                    children: [
                      const Icon(Icons.flag_rounded, size: 16, color: OmniDesignTokens.categoryNfc),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m.title, style: theme.textTheme.bodySmall)),
                      Text(fmt.date(DateTime(_start.year, _start.month, _start.day + m.dayOffset)), style: theme.textTheme.labelSmall),
                    ],
                  ),
              ],
            ],
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(OmniDesignTokens.pageInset, 8, OmniDesignTokens.pageInset, 12 + bottom),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _creating ? null : _create,
            icon: _creating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded),
            label: const Text('Create plan'),
          ),
        ),
      ),
    );
  }
}
