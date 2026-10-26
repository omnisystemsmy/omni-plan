import 'package:flutter/material.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/templates/catalogue_data.dart';
import 'package:omni_plan/features/templates/template_models.dart';
import 'package:omni_plan/features/templates/template_setup_page.dart';
import 'package:provider/provider.dart';

/// Template description, a preview of the plan, what it includes, and a
/// clear "Use this template", in the Omni Docs template detail layout.
Future<void> showTemplateDetailSheet(BuildContext context, PlanTemplate t) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TemplateDetail(template: t, parentContext: context),
  );
}

class _TemplateDetail extends StatelessWidget {
  final PlanTemplate template;
  final BuildContext parentContext;

  const _TemplateDetail({required this.template, required this.parentContext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<PlanStore>();
    final fav = store.isFavoriteTemplate(template.id);
    final category = categoryById(template.categoryId);
    final span = template.span;

    return OmniBottomSheetScaffold(
      child: Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        OmniIconTile(icon: template.icon, color: template.color, size: 52, iconSize: 26),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(template.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                              Text(category.name, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
                          onPressed: () => store.toggleFavoriteTemplate(template.id),
                          icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: fav ? theme.colorScheme.primary : null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(template.description, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 14),
                    const OmniSectionHeader(title: 'Sample preview'),
                    const SizedBox(height: 10),
                    _Preview(template: template),
                    const SizedBox(height: 16),
                    const OmniSectionHeader(title: "What's included"),
                    const SizedBox(height: 8),
                    for (final line in [
                      '${template.sections.length} ${template.sections.length == 1 ? 'section' : 'sections'}',
                      '${template.topLevelTaskCount} tasks${template.taskCount > template.topLevelTaskCount ? ' and ${template.taskCount - template.topLevelTaskCount} subtasks' : ''}',
                      if (template.milestones.isNotEmpty) '${template.milestones.length} milestones',
                      if (template.usesDates)
                        span == null || span == 0 ? 'Dates set from the start date you choose' : 'Dates spread over about ${span + 1} days from your start date',
                      'Everything stays editable after it is created',
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(Icons.check_rounded, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
                          ],
                        ),
                      ),
                    if (template.custom) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () async {
                          final ok = await confirmAction(
                            context,
                            title: 'Delete template?',
                            message: '"${template.name}" is removed from My templates. Projects made from it are not affected.',
                            confirmLabel: 'Delete',
                          );
                          if (ok && context.mounted) {
                            await store.deleteCustomTemplate(template.id);
                            if (context.mounted) Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete this template'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    parentContext,
                    MaterialPageRoute(builder: (_) => TemplateSetupPage(template: template)),
                  );
                },
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: const Text('Use this template'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A miniature of the plan: each section with its first tasks and the
/// milestones, drawn like a project page.
class _Preview extends StatelessWidget {
  final PlanTemplate template;
  const _Preview({required this.template});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light ? OmniDesignTokens.surfaceMuted : OmniDesignTokens.darkSurface,
        borderRadius: BorderRadius.circular(OmniDesignTokens.radiusCompactCard),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in template.sections.take(4)) ...[
            Text(s.name.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(color: OmniDesignTokens.primaryDeep, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            for (final t in s.tasks.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.radio_button_unchecked_rounded, size: 14, color: muted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(t.title, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (t.dayOffset != null)
                      Text(t.dayOffset! < 0 ? '${-t.dayOffset!} d before' : 'Day ${t.dayOffset! + 1}', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                  ],
                ),
              ),
            if (s.tasks.length > 3)
              Text('+ ${s.tasks.length - 3} more', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
            const SizedBox(height: 8),
          ],
          if (template.sections.length > 4)
            Text('+ ${template.sections.length - 4} more sections', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          if (template.milestones.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in template.milestones)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.flag_rounded, size: 14, color: OmniDesignTokens.categoryNfc),
                    label: Text(m.title, style: theme.textTheme.labelSmall),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
