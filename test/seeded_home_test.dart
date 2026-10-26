import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_plan/app/app.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/templates/template_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPoppins);
  testWidgets('home with sample data responds to taps', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    late PlanStore store;
    late TestEnv env;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      store = await memoryStore();
      final now = DateTime.now();
      final p = await store.createFromTemplate(TemplateLibrary.byId('general_project_plan')!,
          name: 'Customer Portal Upgrade', start: now.subtract(const Duration(days: 3)), due: now.add(const Duration(days: 57)));
      final tasks = store.tasksOfProject(p.id);
      await store.setTaskDone(tasks[0], true);
      await store.setTaskDone(tasks[1], true);
      await store.saveProject(store.project(p.id)!.copyWith(status: ProjectStatus.inProgress));
      await store.createFromTemplate(TemplateLibrary.byId('semester_planner')!, name: 'Semester 2', start: now);
    });
    addTearDown(() async => tester.runAsync(env.dispose));
    await tester.pumpWidget(OmniPlanApp(store: store));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.tap(find.text('Profile').last);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Omni Pro'), findsOneWidget);
  });
}
