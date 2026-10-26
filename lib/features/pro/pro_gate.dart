import 'package:flutter/material.dart';
import 'package:omni_plan/features/pro/plan_service.dart';
import 'package:omni_plan/features/pro/pro_page.dart';

/// One place to ask "may this person use a Pro feature?".
class ProGate {
  const ProGate._();

  static bool get isPro => PlanService.instance.isPro;

  /// Whether the current plan includes [capability].
  static bool has(ProCapability capability) => isPro;

  /// True for Pro. Otherwise shows the Pro page for [capability] and returns
  /// whether the person became Pro there. The caller's work in progress is not
  /// touched, because the page is opened on top of it.
  static Future<bool> ensure(
    BuildContext context,
    ProCapability capability,
  ) async {
    if (has(capability)) return true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ProPage(source: capability)),
    );
    return has(capability);
  }
}
