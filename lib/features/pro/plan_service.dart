import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:omni_plan/features/pro/purchase_verifier.dart' show ProAccess;

/// What the person has paid for, as last confirmed by the store.
class UserPlan {
  final bool isPro;

  /// When a subscription runs out. Null for a lifetime plan.
  final DateTime? proExpiresAt;

  const UserPlan({required this.isPro, this.proExpiresAt});

  const UserPlan.free() : isPro = false, proExpiresAt = null;
  const UserPlan.pro({DateTime? expiresAt})
    : isPro = true,
      proExpiresAt = expiresAt;

  bool get isExpired =>
      isPro && proExpiresAt != null && proExpiresAt!.isBefore(DateTime.now());
  bool get isActive => isPro && !isExpired;
  bool get isLifetime => isActive && proExpiresAt == null;
}

/// One place to ask "is this person Pro?". Only the billing layer changes it.
class PlanService extends ChangeNotifier {
  PlanService();
  static final PlanService instance = PlanService();

  UserPlan _plan = const UserPlan.free();
  ProAccess _access = ProAccess.free;

  UserPlan get plan => _plan;
  bool get isPro => _plan.isActive;
  bool get isLifetime => _plan.isLifetime;
  DateTime? get expiresAt => _plan.proExpiresAt;

  /// Why the person is, or is not, Pro right now.
  ProAccess get access => _access;

  /// Only the billing layer calls this, with what the server verified.
  void setPlan(UserPlan plan, {ProAccess? access}) {
    _plan = plan;
    _access = access ?? (plan.isPro ? ProAccess.proActive : ProAccess.free);
    notifyListeners();
  }
}

enum ProPlanKind { yearly, monthly, lifetime }

class ProPlanOffer {
  final ProPlanKind kind;
  final String label;
  final double price;
  final String period;
  final bool hasTrial;

  const ProPlanOffer(
    this.kind,
    this.label,
    this.price,
    this.period, {
    this.hasTrial = false,
  });

  String get priceText => 'RM${price.toStringAsFixed(2)}';
}

/// The listed prices, as in Omni Tools. The store's own price is shown instead
/// whenever Google Play has answered.
class ProPricing {
  static const int trialDays = 7;
  static const monthly = ProPlanOffer(
    ProPlanKind.monthly,
    'Monthly',
    9.90,
    '/ month',
  );
  static const yearly = ProPlanOffer(
    ProPlanKind.yearly,
    'Yearly',
    79.90,
    '/ year',
    hasTrial: true,
  );
  static const lifetime = ProPlanOffer(
    ProPlanKind.lifetime,
    'Lifetime',
    149.00,
    'one-time',
  );

  static const offers = [yearly, monthly, lifetime];

  static double get yearlyPerMonth => yearly.price / 12;

  static int get yearlySavingsPercent =>
      (((monthly.price * 12 - yearly.price) / (monthly.price * 12)) * 100)
          .round();

  static ProPlanOffer offerFor(ProPlanKind k) =>
      offers.firstWhere((o) => o.kind == k);
}

/// What only Pro may do. A capability is added here only when it exists in
/// the app and is checked where it is used. The stable id of each one is in
/// [proFeatures]. Planning itself (tasks, projects, templates, calendar,
/// reminders, goals, reports on screen, backup and restore) is free.
enum ProCapability {
  /// Importing tasks from a CSV file.
  csvImport,

  /// Exporting tasks and project data as CSV files.
  csvExport,

  /// Project and planning reports as PDF files.
  pdfReports,

  /// Saving a project as a reusable template of your own.
  customTemplates,
}

class ProLimits {
  const ProLimits._();

  /// Rows read from one CSV import.
  static const int importRows = 5000;
}

/// Whether a feature can be offered today.
enum ProFeatureStatus {
  /// Built, working and enforced: shown on the Pro page.
  available,

  /// Built but switched off: not shown.
  disabled,

  /// Not built yet: never shown as a benefit.
  planned,

  /// Cannot be built on the current architecture.
  unsupported,
}

/// One row of the Pro page, and the check that stands behind it.
class ProFeature {
  /// Stable identifier of the entitlement.
  final String id;
  final ProCapability? capability;
  final String category;
  final String title;
  final String detail;
  final IconData icon;
  final ProFeatureStatus status;

  const ProFeature({
    required this.id,
    required this.category,
    required this.title,
    required this.detail,
    required this.icon,
    this.capability,
    this.status = ProFeatureStatus.available,
  });
}

/// The single list behind the Pro page and the entitlement checks. Order is
/// the order of the page.
final List<ProFeature> proFeatures = [
  ProFeature(
    id: 'plan_csv_import',
    capability: ProCapability.csvImport,
    category: 'Data',
    title: 'Import tasks from CSV',
    detail:
        'Bring in up to ${NumberFormat.decimalPattern().format(ProLimits.importRows)} tasks from a spreadsheet, with column mapping and checks',
    icon: Icons.upload_file_outlined,
  ),
  const ProFeature(
    id: 'plan_csv_export',
    capability: ProCapability.csvExport,
    category: 'Data',
    title: 'CSV export',
    detail: 'Export all tasks, or one project, to a spreadsheet file',
    icon: Icons.table_view_outlined,
  ),
  const ProFeature(
    id: 'plan_pdf_reports',
    capability: ProCapability.pdfReports,
    category: 'Reports',
    title: 'PDF reports',
    detail: 'Share project and progress reports as PDF files',
    icon: Icons.picture_as_pdf_outlined,
  ),
  const ProFeature(
    id: 'plan_custom_templates',
    capability: ProCapability.customTemplates,
    category: 'Templates',
    title: 'Your own templates',
    detail: 'Save any project as a template and reuse it',
    icon: Icons.bookmark_add_outlined,
  ),

  // --- Not built yet, so never shown as a benefit ---
  const ProFeature(
    id: 'plan_cloud_sync',
    category: 'Data',
    title: 'Sync across devices',
    detail: 'Plans on all your devices',
    icon: Icons.sync_rounded,
    status: ProFeatureStatus.planned,
  ),
  const ProFeature(
    id: 'plan_collaboration',
    category: 'Teams',
    title: 'Shared projects',
    detail: 'Plan together with other people',
    icon: Icons.group_outlined,
    status: ProFeatureStatus.planned,
  ),
];

/// The stable entitlement identifier for [c].
String proFeatureId(ProCapability c) =>
    proFeatures.firstWhere((f) => f.capability == c).id;

class ProBenefit {
  final IconData icon;
  final String title;
  final String detail;
  final String group;

  const ProBenefit(this.icon, this.title, this.detail, {this.group = ''});
}

/// What the Pro page lists: only features that are built and working.
List<ProBenefit> proBenefits() => [
  for (final f in proFeatures)
    if (f.status == ProFeatureStatus.available)
      ProBenefit(f.icon, f.title, f.detail, group: f.category),
];
