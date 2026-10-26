import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omni_plan/app/app.dart';
import 'package:omni_plan/core/backend/supabase_config.dart';
import 'package:omni_plan/data/plan_store.dart';
import 'package:omni_plan/features/pro/billing_service.dart';
import 'package:omni_plan/services/reminder_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The shared Omni Apps project: the same identity as Omni Docs, Omni Tools
  // and Omni Account. Plans themselves stay on this device.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  SupabaseConfig.initialized = true;
  await Hive.initFlutter();
  await ReminderService.instance.init();
  // Google Play answers in the background; the app stays usable meanwhile.
  unawaited(_startBilling());
  runApp(OmniPlanApp(store: PlanStore()));
}

Future<void> _startBilling() async {
  try {
    // Pro follows the signed-in account: a different account never inherits
    // another one's purchase.
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      unawaited(BillingService.instance.onUserChanged());
    });
    await BillingService.instance.init();
  } catch (_) {
    // No store on this device: the app simply stays on the free plan.
  }
}
