import 'package:flutter/material.dart';
import 'package:omni_plan/app/shell/shell_controller.dart';
import 'package:omni_plan/app/workspace.dart';
import 'package:omni_plan/auth/auth_gate.dart';
import 'package:omni_plan/core/app_info.dart';
import 'package:omni_plan/core/backend/supabase_config.dart';
import 'package:omni_plan/core/theme/app_themes.dart';
import 'package:omni_plan/core/theme/theme_provider.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/pro/billing_service.dart';
import 'package:omni_plan/features/pro/pro_celebration.dart';
import 'package:omni_plan/services/reminder_service.dart';
import 'package:provider/provider.dart';

/// Root widget. The plan store is opened for the signed-in account by
/// [PlanWorkspace]; before that it is empty.
class OmniPlanApp extends StatefulWidget {
  final PlanStore store;

  /// Account scope used when the app runs without Supabase (widget tests).
  final String localScope;

  const OmniPlanApp({super.key, required this.store, this.localScope = 'local'});

  @override
  State<OmniPlanApp> createState() => _OmniPlanAppState();
}

class _OmniPlanAppState extends State<OmniPlanApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlanStore>.value(value: widget.store),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..init()),
        ChangeNotifierProvider(create: (_) => ShellController()),
        ChangeNotifierProvider<ReminderService>.value(value: ReminderService.instance),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themes, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          builder: (context, child) => ProCelebrationHost(
            navigatorKey: _navigatorKey,
            celebrations: BillingService.instance.celebrations,
            // No Hero flights between pages. A SnackBar and a floating
            // button are Heroes; shown while a page opens or closes they were
            // flown between the two pages, and in debug builds that failed
            // with "'_dependents.isEmpty': is not true".
            child: HeroControllerScope.none(child: child ?? const SizedBox.shrink()),
          ),
          title: AppInfo.name,
          debugShowCheckedModeBanner: false,
          themeMode: themes.themeMode,
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          // Widget tests can build the local workspace without running
          // main(). A real app launch always initializes Supabase first.
          home: SupabaseConfig.initialized
              ? const AuthGate()
              : PlanWorkspace(scope: widget.localScope),
        ),
      ),
    );
  }
}
