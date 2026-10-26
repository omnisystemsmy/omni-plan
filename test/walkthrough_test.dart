import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_plan/app/app.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/domain/models.dart';
import 'package:omni_plan/features/profile/profile_tab.dart';
import 'package:omni_plan/features/shared/plan_widgets.dart';
import 'package:omni_plan/features/templates/template_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_env.dart';

/// Walks the app the way a person does, on sample data, and fails on any
/// framework error (red screen) along the way.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPoppins);

  Future<void> frames(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n * 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  void ok(WidgetTester tester, String step) {
    final e = tester.takeException();
    if (e != null) fail('Step "$step" raised: $e');
  }

  Future<void> tapText(WidgetTester tester, String text, {int index = 0, bool last = false}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'missing "$text"');
    await tester.tap(last ? f.last : f.at(index), warnIfMissed: false);
    await frames(tester);
  }

  testWidgets('walk through the main flows', (tester) async {
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
      final p = await store.createFromTemplate(TemplateLibrary.byId('assignment_tracker')!,
          name: 'Assignment Tracker', start: now.subtract(const Duration(days: 2)));
      final t = store.tasksOfProject(p.id);
      await store.setTaskDone(t[0], true);
      await store.setTaskDone(t[1], true);
      await store.saveProject(store.project(p.id)!.copyWith(status: ProjectStatus.inProgress));
      await store.saveTask(store.draftTask().copyWith(title: 'Loose task'));
    });
    addTearDown(() async => tester.runAsync(env.dispose));
    await tester.pumpWidget(OmniPlanApp(store: store));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await frames(tester);
    ok(tester, 'start');

    // My Tasks: every filter and view.
    await tapText(tester, 'My Tasks', last: true);
    for (final label in ['Today', 'Upcoming', 'Overdue']) {
      await tapText(tester, label);
      ok(tester, 'filter $label');
    }
    for (final view in ['Board', 'Agenda', 'List']) {
      await tapText(tester, view);
      ok(tester, 'view $view');
    }

    // Complete a task from the list, then open it.
    await tapText(tester, 'All');
    await tester.tap(find.byType(TaskCheck).first, warnIfMissed: false);
    await frames(tester);
    ok(tester, 'complete task');
    await tester.drag(find.text('Overdue'), const Offset(-400, 0));
    await frames(tester);
    await tapText(tester, 'Completed');
    await tester.tap(find.byType(TaskRow).first, warnIfMissed: false);
    await frames(tester);
    ok(tester, 'open task');
    await tapText(tester, 'Reopen task');
    ok(tester, 'reopen');
    await tester.tap(find.byTooltip('Edit task'));
    await frames(tester);
    ok(tester, 'task editor');
    await tapText(tester, 'Save changes');
    ok(tester, 'save task');
    await tester.pageBack();
    await frames(tester);
    ok(tester, 'back from task');

    // Projects: open, visit every tab.
    await tapText(tester, 'Projects', last: true);
    await tapText(tester, 'Assignment Tracker');
    ok(tester, 'open project');
    for (final tab in ['Tasks', 'Board', 'Calendar', 'Timeline', 'Milestones', 'Notes', 'Reports', 'Overview']) {
      await tapText(tester, tab);
      ok(tester, 'project tab $tab');
    }

    // Edit the project and mark it completed.
    await tester.tap(find.byTooltip('More options').first);
    await frames(tester);
    await tapText(tester, 'Edit project');
    ok(tester, 'project editor');
    await tapText(tester, 'Completed');
    await tapText(tester, 'Save changes');
    ok(tester, 'save project');

    // Archive it (pop + snackbar), undo, then leave.
    await tester.tap(find.byTooltip('More options').first);
    await frames(tester);
    await tapText(tester, 'Archive');
    ok(tester, 'archive project');
    await tapText(tester, 'Undo');
    ok(tester, 'undo archive');
    await frames(tester, 20);
    ok(tester, 'after undo');

    // New project from the + sheet, via a template.
    await tester.tap(find.byTooltip('Create new'));
    await frames(tester);
    await tapText(tester, 'Use a template');
    await tapText(tester, 'General Project Plan');
    await tapText(tester, 'Use this template');
    await tapText(tester, 'Create plan');
    ok(tester, 'create from template');
    await frames(tester, 12);
    await tester.pageBack();
    await frames(tester);
    ok(tester, 'back after template');
    await tester.pageBack();
    await frames(tester);
    ok(tester, 'back to home');

    // A project created by hand: pop + push + snackbar at once.
    await tester.tap(find.byTooltip('Create new'));
    await frames(tester);
    await tapText(tester, 'New project', last: true);
    await tapText(tester, 'Blank project');
    await tester.enterText(find.widgetWithText(TextField, 'Project name *'), 'Mobile app development');
    await tapText(tester, 'Create project');
    ok(tester, 'create project by hand');
    await frames(tester, 12);
    await tester.pageBack();
    await frames(tester);
    ok(tester, 'back after new project');

    // Notifications: open one, which opens its task.
    await tester.tap(find.byIcon(Icons.notifications_none_rounded), warnIfMissed: false);
    await frames(tester);
    ok(tester, 'notifications');
    final notice = find.textContaining('Due today');
    if (notice.evaluate().isNotEmpty) {
      await tester.tap(notice.first, warnIfMissed: false);
      await frames(tester);
      ok(tester, 'open notification target');
      await tester.pageBack();
      await frames(tester);
    }
    await tester.pageBack();
    await frames(tester);
    ok(tester, 'back from notifications');

    // Profile: every row, then dark mode on and off.
    await tapText(tester, 'Profile', last: true);
    final profileList = find.descendant(of: find.byType(ProfileTab), matching: find.byType(Scrollable)).first;
    for (final row in ['History', 'Favorites', 'Archive', 'Backup and restore', 'Settings', 'Notifications', 'Data and privacy', 'Planning defaults', 'Help & Support', 'About']) {
      await tester.scrollUntilVisible(find.text(row), 200, scrollable: profileList);
      await frames(tester, 2);
      await tapText(tester, row);
      ok(tester, 'profile row ');
      if (row == 'Settings') {
        await tester.tap(find.byType(Switch).last, warnIfMissed: false);
        await frames(tester);
        ok(tester, 'dark mode switch');
        await tester.tap(find.byType(Switch).last, warnIfMissed: false);
        await frames(tester);
        ok(tester, 'dark mode off');
      }
      await tester.pageBack();
      await frames(tester);
      ok(tester, 'back from ');
    }
    await tapText(tester, 'Home', last: true);

    // And a goal.
    await tester.tap(find.byTooltip('Create new'));
    await frames(tester);
    await tapText(tester, 'New goal', last: true);
    await tester.enterText(find.widgetWithText(TextField, 'Goal title *'), 'Ship the app');
    await tapText(tester, 'Create goal');
    ok(tester, 'create goal');
    await frames(tester, 12);
  });
}
