import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:omni_plan/features/pro/plan_service.dart';

/// Google Play product ids of Omni Plan, as created in Play Console. Same
/// structure as Omni Tools (yearly + monthly subscriptions with a 7-day free
/// trial offer on yearly, and a one-time lifetime product).
class ProductIds {
  /// The seven-day free-trial offer attached to the yearly subscription.
  static const trialOfferId = 'yearly-free-trial';

  static const yearly = 'omni_plan_pro_yearly';
  static const monthly = 'omni_plan_pro_monthly';
  static const lifetime = 'omni_plan_pro_lifetime';

  static const all = {yearly, monthly, lifetime};

  static String forKind(ProPlanKind k) => switch (k) {
    ProPlanKind.yearly => yearly,
    ProPlanKind.monthly => monthly,
    ProPlanKind.lifetime => lifetime,
  };
}

/// What the store told us about one product.
class StoreProduct {
  final String id;

  /// The price the person will pay (after any free trial).
  final String price;
  final bool hasTrial;

  /// The Play offer this product is bought with (null for the base plan).
  final String? offerId;
  final Object? raw;
  const StoreProduct(this.id, this.price, this.hasTrial, [this.raw, this.offerId]);
}

enum StorePurchaseStatus { pending, purchased, restored, error, canceled }

class StorePurchase {
  final String productId;
  final StorePurchaseStatus status;
  final String? purchaseId;

  /// The purchase token Google Play issued. Only the server can say what it is worth.
  final String? token;
  final String? errorCode;
  final String? errorMessage;
  final bool pendingComplete;
  final Object? raw;

  const StorePurchase({
    required this.productId,
    required this.status,
    this.purchaseId,
    this.token,
    this.errorCode,
    this.errorMessage,
    this.pendingComplete = false,
    this.raw,
  });
}

/// The store, as the billing service needs it. Google Play implements it; tests
/// use a fake one.
abstract class StoreGateway {
  Stream<List<StorePurchase>> get purchases;
  Future<bool> isAvailable();
  Future<List<StoreProduct>> products(Set<String> ids);

  /// Product ids Google Play did not return in the last query.
  Set<String> get missingIds;

  /// Play's own response code and message for the last failure, safe to log.
  String? get lastProblem;
  /// [userId] is attached to the purchase so the server can check who bought it.
  Future<bool> buy(StoreProduct product, {String? userId});
  Future<void> restore();
  Future<void> complete(StorePurchase purchase);
}

class PlayStoreGateway implements StoreGateway {
  Set<String> _missing = {};
  String? _problem;

  @override
  Set<String> get missingIds => _missing;

  @override
  String? get lastProblem => _problem;

  late final InAppPurchase _iap = InAppPurchase.instance;

  @override
  Stream<List<StorePurchase>> get purchases =>
      _iap.purchaseStream.map((list) => [for (final p in list) _convert(p)]);

  StorePurchase _convert(PurchaseDetails p) => StorePurchase(
    productId: p.productID,
    status: switch (p.status) {
      PurchaseStatus.pending => StorePurchaseStatus.pending,
      PurchaseStatus.purchased => StorePurchaseStatus.purchased,
      PurchaseStatus.restored => StorePurchaseStatus.restored,
      PurchaseStatus.error => StorePurchaseStatus.error,
      PurchaseStatus.canceled => StorePurchaseStatus.canceled,
    },
    purchaseId: p.purchaseID,
    token: p.verificationData.serverVerificationData,
    errorCode: p.error?.code,
    errorMessage: p.error?.message,
    pendingComplete: p.pendingCompletePurchase,
    raw: p,
  );

  @override
  Future<bool> isAvailable() async {
    final ok = await _iap.isAvailable();
    _problem = ok ? null : 'Play Billing is not available (no Play Store, or not signed in)';
    return ok;
  }

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async {
    final response = await _iap.queryProductDetails(ids);
    final err = response.error;
    _problem = err == null ? null : '${err.source} ${err.code}: ${err.message}';
    _missing = {
      for (final id in ids)
        if (!response.productDetails.any((d) => d.id == id)) id,
    };
    if (err != null) throw StateError(_problem!);
    final out = <StoreProduct>[];
    for (final id in ids) {
      final options = response.productDetails.where((d) => d.id == id).toList();
      if (options.isEmpty) continue;
      // The base plan is the one without an offer id.
      var chosen = options.firstWhere(
        (d) => d is GooglePlayProductDetails && _offerId(d) == null,
        orElse: () => options.first,
      );
      var trial = false;
      var price = chosen.price;
      if (id != ProductIds.lifetime) {
        // Play lists only the offers this person is eligible for, so the trial
        // is shown only when Play returned it: the seven-day free offer.
        for (final d in options) {
          if (d is! GooglePlayProductDetails) continue;
          final phases = _phases(d);
          // The offer Play lists for this person that starts free. Like Omni
          // Tools, it is recognised by its zero-price first phase; the offer id
          // `yearly-free-trial` is only logged.
          if (phases.length > 1 && phases.first.priceAmountMicros == 0) {
            chosen = d;
            trial = true;
            break;
          }
        }
        if (chosen is GooglePlayProductDetails) {
          final phases = _phases(chosen);
          if (phases.isNotEmpty) price = phases.last.formattedPrice;
        }
      }
      out.add(
        StoreProduct(
          id,
          price,
          trial,
          chosen,
          chosen is GooglePlayProductDetails ? _offerId(chosen) : null,
        ),
      );
    }
    return out;
  }

  String? _offerId(GooglePlayProductDetails d) {
    final offers = d.productDetails.subscriptionOfferDetails;
    final i = d.subscriptionIndex;
    if (offers == null || i == null || i >= offers.length) return null;
    return offers[i].offerId;
  }

  List<PricingPhaseWrapper> _phases(GooglePlayProductDetails d) {
    final offers = d.productDetails.subscriptionOfferDetails;
    final i = d.subscriptionIndex;
    if (offers == null || i == null || i >= offers.length) return const [];
    return offers[i].pricingPhases;
  }

  @override
  Future<bool> buy(StoreProduct product, {String? userId}) {
    final d = product.raw as ProductDetails;
    final param = d is GooglePlayProductDetails
        ? GooglePlayPurchaseParam(
            productDetails: d,
            offerToken: d.offerToken,
            applicationUserName: userId,
          )
        : PurchaseParam(productDetails: d, applicationUserName: userId);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(StorePurchase purchase) async {
    final raw = purchase.raw;
    if (raw is PurchaseDetails) await _iap.completePurchase(raw);
  }
}
