import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_plan/app/app.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/profile/profile_tab.dart';
import 'package:omni_plan/features/tasks/task_editor_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_env.dart';

/// The search bar glow never stops animating, so pumpAndSettle would wait
/// forever; advance time by hand instead.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPoppins);

  Future<PlanStore> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late PlanStore store;
    late TestEnv env;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      store = await memoryStore();
    });
    addTearDown(() async => tester.runAsync(env.dispose));
    await tester.pumpWidget(OmniPlanApp(store: store));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle(tester);
    return store;
  }

  testWidgets('home shows the greeting, overview and navigation', (tester) async {
    await pumpApp(tester);
    // Pages never fly Heroes (SnackBar, FAB) between each other.
    expect(HeroControllerScope.maybeOf(tester.element(find.byType(Scaffold).first)), isNull);
    // The logo is the black artwork on the light theme.
    final logo = tester.widget<Image>(find.descendant(of: find.byType(AppBar), matching: find.byType(Image)).first);
    expect((logo.image as AssetImage).assetName, 'assets/images/omni plan logo (black) no bg.png');
    expect(find.text('What would you like to plan today?'), findsOneWidget);
    expect(find.text("Today's overview"), findsOneWidget);
    for (final label in ['Home', 'My Tasks', 'New', 'Projects', 'Profile']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('a task is created from the New button with only a title', (tester) async {
    final store = await pumpApp(tester);
    await tester.tap(find.byTooltip('Create new'));
    await settle(tester);
    await tester.tap(find.text('New task'));
    await settle(tester);
    expect(find.byType(TaskEditorPage), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Task title *'), 'Call the venue');
    await tester.tap(find.text('Save task'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(store.tasks.single.title, 'Call the venue');
  });

  testWidgets('the profile page has the Omni Docs sections', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Profile').last);
    await settle(tester);
    expect(find.text('Omni Pro'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('About'),
      300,
      scrollable: find.descendant(of: find.byType(ProfileTab), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Help & Support'), findsOneWidget);
  });

  testWidgets('New project offers blank or template, and template lets you browse and pick', (tester) async {
    final store = await pumpApp(tester);
    await tester.tap(find.text('Projects').last);
    await settle(tester);
    await tester.tap(find.text('New project').first);
    await settle(tester);
    expect(find.text('Blank project'), findsOneWidget);
    expect(find.text('From a template'), findsOneWidget);
    await tester.tap(find.text('From a template'));
    await settle(tester);
    expect(find.text('Search templates...'), findsOneWidget);
    await tester.tap(find.text('Weekly Planner').first);
    await settle(tester);
    await tester.tap(find.text('Use this template'));
    await settle(tester);
    await tester.tap(find.text('Create plan'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    expect(store.projects.single.name, 'Weekly Planner');
    await tester.pump(const Duration(seconds: 2)); // let the reminder debounce finish
  });

  testWidgets('a template creates a project that opens on its tasks', (tester) async {
    final store = await pumpApp(tester);
    await tester.tap(find.byTooltip('Create new'));
    await settle(tester);
    await tester.tap(find.text('Use a template'));
    await settle(tester);
    await tester.tap(find.text('General Project Plan').first);
    await settle(tester);
    await tester.tap(find.text('Use this template'));
    await settle(tester);
    await tester.tap(find.text('Create plan'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
    expect(store.projects.single.name, 'General Project Plan');
    expect(find.text('Initiation · 3'), findsOneWidget);
  });
}
