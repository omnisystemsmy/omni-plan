import 'package:flutter/material.dart';
import 'package:omni_plan/app/navigation.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/core/widgets/omni_mobile_components.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/data/import_page.dart';
import 'package:omni_plan/features/templates/template_library.dart';
import 'package:provider/provider.dart';

/// "Create new": the sheet behind the centre button, in the Omni Docs
/// "New document" sheet layout.
Future<void> showCreateSheet(BuildContext context) {
  final hasProjects = context.read<PlanStore>().projects.isNotEmpty;
  void go(BuildContext sheet, Future<void> Function() action) {
    Navigator.pop(sheet);
    action();
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => OmniBottomSheetScaffold(
      title: 'Create new',
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: Flexible(
        child: SingleChildScrollView(
          child: Column(
            children: [
              OmniMenuRow(
                icon: Icons.add_task_rounded,
                iconColor: OmniDesignTokens.primary,
                useTile: true,
                title: 'New task',
                subtitle: 'Only a title is needed',
                onTap: () => go(sheet, () => newTask(context)),
              ),
              OmniMenuRow(
                icon: Icons.create_new_folder_rounded,
                iconColor: OmniDesignTokens.categoryConverters,
                useTile: true,
                title: 'New project',
                subtitle: 'Blank, or start from a template',
                onTap: () => go(sheet, () => newProject(context)),
              ),
              OmniMenuRow(
                icon: Icons.flag_rounded,
                iconColor: OmniDesignTokens.categoryNfc,
                useTile: true,
                title: 'New goal',
                subtitle: 'An outcome with a target date',
                onTap: () => go(sheet, () => newGoal(context)),
              ),
              OmniMenuRow(
                icon: Icons.outlined_flag_rounded,
                iconColor: OmniDesignTokens.categoryText,
                useTile: true,
                title: 'New milestone',
                subtitle: hasProjects ? 'A checkpoint in a project' : 'Create a project first',
                enabled: hasProjects,
                onTap: () => go(sheet, () => newMilestone(context)),
              ),
              OmniMenuRow(
                icon: Icons.repeat_rounded,
                iconColor: OmniDesignTokens.categoryCalculator,
                useTile: true,
                title: 'New recurring task',
                subtitle: 'Repeats daily, weekly, monthly or yearly',
                onTap: () => go(sheet, () => newTask(context, recurring: true, dueDate: DateTime.now())),
              ),
              OmniMenuRow(
                icon: Icons.dashboard_customize_rounded,
                iconColor: OmniDesignTokens.categoryBusiness,
                useTile: true,
                title: 'Use a template',
                subtitle: '${TemplateLibrary.templateCount} ready-made plans',
                onTap: () => go(sheet, () => openTemplates(context)),
              ),
              OmniMenuRow(
                icon: Icons.upload_file_rounded,
                iconColor: OmniDesignTokens.categoryFiles,
                useTile: true,
                title: 'Import tasks',
                subtitle: 'From a CSV file',
                trailing: const OmniProBadge(),
                onTap: () => go(sheet, () => openImport(context)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
