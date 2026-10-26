import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omni_plan/app/app.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/templates/template_library.dart';
import 'package:omni_plan/services/reminder_service.dart';

/// Development preview: the app without Supabase (no sign-in, no Pro
/// checks), on a separate "preview" data scope with one sample project.
/// Run with `flutter run -t lib/main_preview.dart`. Release builds use
/// `lib/main.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await ReminderService.instance.init();
  final store = PlanStore();
  await store.open('preview');
  if (store.allProjects.isEmpty) {
    final now = DateTime.now();
    final p = await store.createFromTemplate(
      TemplateLibrary.byId('general_project_plan')!,
      name: 'Customer Portal Upgrade',
      start: now.subtract(const Duration(days: 3)),
      due: now.add(const Duration(days: 57)),
      category: 'Project Management',
    );
    final tasks = store.tasksOfProject(p.id);
    await store.setTaskDone(tasks[0], true);
    await store.setTaskDone(tasks[1], true);
    await store.saveProject(store.project(p.id)!.copyWith(status: ProjectStatus.inProgress));
    await store.createFromTemplate(
      TemplateLibrary.byId('semester_planner')!,
      name: 'Semester 2',
      start: now,
      category: 'Academic',
    );
  }
  runApp(OmniPlanApp(store: store, localScope: 'preview'));
}
