import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_plan/features/pro/billing_service.dart';
import 'package:omni_plan/features/pro/plan_service.dart';
import 'package:omni_plan/features/pro/purchase_verifier.dart';
import 'package:omni_plan/features/pro/store_gateway.dart';

class _Gateway implements StoreGateway {
  final controller = StreamController<List<StorePurchase>>.broadcast();
  final completed = <String>[];
  String? boughtWithUser;

  @override
  Stream<List<StorePurchase>> get purchases => controller.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<StoreProduct>> products(Set<String> ids) async => [
    for (final id in ids) StoreProduct(id, 'RM1', id == ProductIds.yearly),
  ];
  @override
  Set<String> get missingIds => {};
  @override
  String? get lastProblem => null;
  @override
  Future<bool> buy(StoreProduct product, {String? userId}) async {
    boughtWithUser = userId;
    return true;
  }

  @override
  Future<void> restore() async {}
  @override
  Future<void> complete(StorePurchase p) async => completed.add(p.productId);
}

StorePurchase _purchase(String id, {StorePurchaseStatus s = StorePurchaseStatus.purchased}) =>
    StorePurchase(productId: id, status: s, purchaseId: 'o-$id', token: 'tok-$id', pendingComplete: true);

void main() {
  test('product ids match Play Console', () {
    expect(ProductIds.all, {'omni_plan_pro_yearly', 'omni_plan_pro_monthly', 'omni_plan_pro_lifetime'});
  });

  test('a Play purchase grants Pro, is acknowledged, and survives a restart', () async {
    final gateway = _Gateway();
    final store = MemoryEntitlementStore();
    final plans = PlanService();
    final billing = BillingService(
      gateway: gateway,
      store: store,
      plans: plans,
      verifier: PlayDevicePurchaseVerifier(store),
      restoreWait: Duration.zero,
    );
    await billing.init();
    expect(billing.ready, isTrue);
    expect(plans.isPro, isFalse);

    expect(await billing.buy(ProPlanKind.yearly), PurchaseOutcome.started);
    gateway.controller.add([_purchase(ProductIds.yearly)]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(plans.isPro, isTrue);
    expect(plans.isLifetime, isFalse);
    expect(gateway.completed, [ProductIds.yearly]);
    expect(billing.celebrations.value, 1);

    // New launch: cached Pro is available straight away.
    final plans2 = PlanService();
    final again = BillingService(
      gateway: _Gateway(),
      store: store,
      plans: plans2,
      verifier: PlayDevicePurchaseVerifier(store),
      restoreWait: Duration.zero,
    );
    await again.init();
    expect(plans2.isPro, isTrue);
  });

  test('lifetime is kept; a lapsed subscription is dropped', () async {
    final store = MemoryEntitlementStore();
    final plans = PlanService();
    final gateway = _Gateway();
    final billing = BillingService(
      gateway: gateway,
      store: store,
      plans: plans,
      verifier: PlayDevicePurchaseVerifier(store),
      restoreWait: Duration.zero,
    );
    await billing.init();
    gateway.controller.add([_purchase(ProductIds.lifetime)]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(plans.isLifetime, isTrue);

    final stale = MemoryEntitlementStore()
      ..user = 'device'
      ..until = DateTime.now().add(const Duration(days: 20))
      ..verified = DateTime.now().subtract(const Duration(days: 5));
    final plans2 = PlanService();
    final b2 = BillingService(
      gateway: _Gateway(),
      store: stale,
      plans: plans2,
      verifier: PlayDevicePurchaseVerifier(stale),
      restoreWait: Duration.zero,
    );
    await b2.init();
    expect(plans2.isPro, isFalse);
  });
}
