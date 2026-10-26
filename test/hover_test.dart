import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_plan/app/app.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/templates/template_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_env.dart';

/// With a mouse (the emulator, a desktop) tooltips appear on hover. Pages
/// must be able to change while one is showing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPoppins);

  Future<void> frames(WidgetTester tester, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('pages change while a tooltip is showing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    late PlanStore store;
    late TestEnv env;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      store = await memoryStore();
      await store.createFromTemplate(TemplateLibrary.byId('assignment_tracker')!,
          name: 'Assignment Tracker', start: DateTime.now());
    });
    addTearDown(() async => tester.runAsync(env.dispose));
    await tester.pumpWidget(OmniPlanApp(store: store));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await frames(tester);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    Future<void> hoverAndTap(Finder f) async {
      await mouse.moveTo(tester.getCenter(f.first));
      await frames(tester, 25); // tooltip shows after its wait duration
      await mouse.down(tester.getCenter(f.first));
      await mouse.up();
      await frames(tester, 25);
      expect(tester.takeException(), isNull);
    }

    await hoverAndTap(find.byIcon(Icons.notifications_none_rounded));
    await tester.pageBack();
    await frames(tester);
    expect(tester.takeException(), isNull);

    await hoverAndTap(find.byTooltip('Create new'));
    await frames(tester);
    await mouse.moveTo(const Offset(200, 100));
    await tester.tapAt(const Offset(200, 60));
    await frames(tester);
    expect(tester.takeException(), isNull);

    // Open a project, hover its menu, and go back with the tooltip showing.
    await tester.tap(find.text('Projects').last);
    await frames(tester);
    await tester.tap(find.text('Assignment Tracker'));
    await frames(tester);
    await mouse.moveTo(tester.getCenter(find.byTooltip('More options').first));
    await frames(tester, 25);
    await tester.pageBack();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
}
