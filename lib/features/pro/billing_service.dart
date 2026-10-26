import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_plan/features/pro/plan_service.dart';
import 'package:omni_plan/features/pro/purchase_verifier.dart';
import 'package:omni_plan/features/pro/store_gateway.dart';

/// What Play told us about a plan: the real localised price and trial.
class StorePlan {
  final ProPlanKind kind;
  final StoreProduct product;
  const StorePlan(this.kind, this.product);

  String get price => product.price;
  bool get hasTrial => product.hasTrial;
}

/// Why the plans cannot be bought right now.
enum StoreProblem {
  none,

  /// Play Billing does not answer: no Play Store, no Google account, or old Play services.
  billingUnavailable,

  /// Play answered but the product query failed.
  queryFailed,

  /// Play answered but some products are not there (not active, not in this track or region).
  productsMissing,
}

enum PurchaseOutcome { started, unavailable, signInRequired, cancelled, failed }

enum RestoreResult {
  restored,
  nothingFound,
  failed,
  unavailable,
  signInRequired,
}

/// The last confirmed purchase, kept on the device so Pro works offline. The
/// store is asked again at every launch and is the source of truth.
abstract class EntitlementStore {
  /// The account the saved entitlement belongs to. It is used only when the
  /// same account is signed in again.
  Future<String?> cachedUserId();
  Future<void> setCachedUserId(String? id);
  Future<bool> cancelled();
  Future<void> setCancelled(bool value);
  Future<bool> lifetime();
  Future<void> setLifetime(bool value);
  Future<DateTime?> proUntil();
  Future<void> setProUntil(DateTime? value);
  Future<DateTime?> lastVerified();
  Future<void> setLastVerified(DateTime value);
  Future<String?> lastCelebrated();
  Future<void> setLastCelebrated(String id);
}

class SecureEntitlementStore implements EntitlementStore {
  static const _s = FlutterSecureStorage();
  static const _kLifetime = 'pro_lifetime';
  static const _kUntil = 'pro_until';
  static const _kVerified = 'pro_last_verified';
  static const _kCelebrated = 'pro_last_celebrated';
  static const _kUser = 'pro_user';
  static const _kCancelled = 'pro_cancelled';

  @override
  Future<String?> cachedUserId() => _s.read(key: _kUser);

  @override
  Future<void> setCachedUserId(String? id) => id == null
      ? _s.delete(key: _kUser)
      : _s.write(key: _kUser, value: id);

  @override
  Future<bool> cancelled() async => await _s.read(key: _kCancelled) == '1';

  @override
  Future<void> setCancelled(bool v) => v
      ? _s.write(key: _kCancelled, value: '1')
      : _s.delete(key: _kCancelled);

  Future<int?> _int(String k) async =>
      int.tryParse(await _s.read(key: k) ?? '');

  @override
  Future<bool> lifetime() async => await _s.read(key: _kLifetime) == '1';

  @override
  Future<void> setLifetime(bool v) =>
      v ? _s.write(key: _kLifetime, value: '1') : _s.delete(key: _kLifetime);

  @override
  Future<DateTime?> proUntil() async {
    final ms = await _int(_kUntil);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> setProUntil(DateTime? v) => v == null
      ? _s.delete(key: _kUntil)
      : _s.write(key: _kUntil, value: '${v.millisecondsSinceEpoch}');

  @override
  Future<DateTime?> lastVerified() async {
    final ms = await _int(_kVerified);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> setLastVerified(DateTime v) =>
      _s.write(key: _kVerified, value: '${v.millisecondsSinceEpoch}');

  @override
  Future<String?> lastCelebrated() => _s.read(key: _kCelebrated);

  @override
  Future<void> setLastCelebrated(String id) =>
      _s.write(key: _kCelebrated, value: id);
}

class MemoryEntitlementStore implements EntitlementStore {
  bool life = false;
  DateTime? until;
  DateTime? verified;
  String? celebrated;
  String? user;
  bool cancelledFlag = false;

  @override
  Future<String?> cachedUserId() async => user;
  @override
  Future<void> setCachedUserId(String? id) async => user = id;
  @override
  Future<bool> cancelled() async => cancelledFlag;
  @override
  Future<void> setCancelled(bool v) async => cancelledFlag = v;
  @override
  Future<bool> lifetime() async => life;
  @override
  Future<void> setLifetime(bool v) async => life = v;
  @override
  Future<DateTime?> proUntil() async => until;
  @override
  Future<void> setProUntil(DateTime? v) async => until = v;
  @override
  Future<DateTime?> lastVerified() async => verified;
  @override
  Future<void> setLastVerified(DateTime v) async => verified = v;
  @override
  Future<String?> lastCelebrated() async => celebrated;
  @override
  Future<void> setLastCelebrated(String id) async => celebrated = id;
}

/// Connects the app to Google Play Billing. Pro is granted only from what the
/// trusted backend verified with Google Play, never from the purchase callback
/// alone. The device keeps a copy of the last verified answer, for the same
/// account only, so Pro opens without a network; the next launch asks again.
class BillingService extends ChangeNotifier {
  BillingService({
    required StoreGateway gateway,
    PurchaseVerifier? verifier,
    EntitlementStore? store,
    PlanService? plans,
    this.restoreWait = const Duration(seconds: 4),
    DateTime Function()? now,
    // ignore: prefer_initializing_formals
  }) : _gateway = gateway,
       _verifier =
           verifier ??
           PlayDevicePurchaseVerifier(store ?? SecureEntitlementStore()),
       _store = store ?? SecureEntitlementStore(),
       _plans = plans ?? PlanService.instance,
       _now = now ?? DateTime.now;

  static BillingService? _instance;
  static BillingService get instance =>
      _instance ??= BillingService(gateway: PlayStoreGateway());

  final StoreGateway _gateway;
  final PurchaseVerifier _verifier;
  final EntitlementStore _store;
  final PlanService _plans;
  final DateTime Function() _now;
  final Duration restoreWait;

  /// True while a purchase was paid for but not yet verified. It is not
  /// acknowledged, so Play delivers it again at every start and on [retryPending].
  bool _unverified = false;
  StoreProblem _problem = StoreProblem.none;

  StreamSubscription<List<StorePurchase>>? _sub;
  bool _storeAvailable = false;
  bool _loading = false;
  bool _purchasing = false;
  bool _restoreFound = false;
  String? _lastError;
  String? _userId;
  final Map<ProPlanKind, StorePlan> _plansByKind = {};

  /// Purchase tokens being verified right now, and ones already settled in
  /// this run, so a repeated callback is handled once.
  final Set<String> _inFlight = {};
  final Set<String> _settled = {};

  /// Bumped when a new purchase is verified, so the app can celebrate.
  final ValueNotifier<int> celebrations = ValueNotifier(0);

  PlanService get plans => _plans;
  ProAccess get access => _plans.access;
  bool get storeAvailable => _storeAvailable;
  bool get loading => _loading;
  bool get purchasing => _purchasing;
  String? get lastError => _lastError;
  StoreProblem get problem => _problem;

  /// A message for the person that says which part failed.
  String get problemMessage => switch (_problem) {
    StoreProblem.billingUnavailable =>
      'Google Play billing is not available on this device. Use a device '
          'with the Google Play Store, signed in to a Google account, and '
          'install Omni Plan from Google Play.',
    StoreProblem.queryFailed =>
      'Google Play could not load the plans. Check your connection and try '
          'again.',
    StoreProblem.productsMissing =>
      'These plans are not available from Google Play yet. Please try again '
          'later.',
    StoreProblem.none => '',
  };

  void _log(String message) => debugPrint('[OmniBilling] $message');

  bool get signedIn => _verifier.userId != null;
  StorePlan? plan(ProPlanKind k) => _plansByKind[k];

  /// True when the store answered and every product exists.
  bool get ready =>
      _storeAvailable && ProPlanKind.values.every(_plansByKind.containsKey);

  void clearError() => _lastError = null;

  /// Call once at start-up. Safe when the store is unavailable (emulator, no
  /// products yet): the app simply stays on what was last verified.
  Future<void> init() async {
    _userId = _verifier.userId;
    await _loadCachedEntitlement();
    _sub ??= _gateway.purchases.listen(
      _onPurchases,
      onError: (Object e) {
        _lastError = 'The store could not be reached.';
        _purchasing = false;
        notifyListeners();
      },
    );
    await refreshProducts();
    if (_storeAvailable && _userId != null) {
      try {
        await _gateway.restore();
      } catch (_) {}
    }
    await refreshEntitlement();
  }

  /// Call when the signed-in account changes. The previous account's Pro is
  /// dropped at once, and the new account's is read from the server.
  Future<void> onUserChanged() async {
    final id = _verifier.userId;
    if (id == _userId) return;
    _userId = id;
    _settled.clear();
    _inFlight.clear();
    _lastError = null;
    _purchasing = false;
    _plans.setPlan(const UserPlan.free());
    await _clearCache();
    notifyListeners();
    if (id == null) return;
    await _loadCachedEntitlement();
    if (_storeAvailable) {
      try {
        await _gateway.restore();
      } catch (_) {}
    }
    await refreshEntitlement();
  }

  Future<void> refreshProducts() async {
    _loading = true;
    notifyListeners();
    _problem = StoreProblem.none;
    try {
      _storeAvailable = await _gateway.isAvailable();
      _log('billing available: $_storeAvailable');
      if (!_storeAvailable) {
        _problem = StoreProblem.billingUnavailable;
        _log('unavailable: ${_gateway.lastProblem}');
      } else {
        final found = await _gateway.products(ProductIds.all);
        _plansByKind.clear();
        for (final kind in ProPlanKind.values) {
          final id = ProductIds.forKind(kind);
          for (final p in found) {
            if (p.id == id) _plansByKind[kind] = StorePlan(kind, p);
          }
        }
        for (final p in found) {
          _log(
            'product ${p.id}: price=${p.price} trial=${p.hasTrial} '
            'offer=${p.offerId ?? 'base'}',
          );
        }
        final missing = _gateway.missingIds;
        if (missing.isNotEmpty) {
          _problem = StoreProblem.productsMissing;
          _log('missing products: ${missing.join(', ')}');
        }
      }
    } catch (e, st) {
      // The query failed: Play is there, but did not give the products.
      _problem = _storeAvailable
          ? StoreProblem.queryFailed
          : StoreProblem.billingUnavailable;
      _log('product query failed: ${_gateway.lastProblem ?? e.runtimeType}\n$e\n$st');
      _plansByKind.clear();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Asks the server what the signed-in account is entitled to right now.
  /// When the server cannot be reached the last verified answer stays.
  Future<void> refreshEntitlement() async {
    if (_userId == null) return;
    final asked = _userId;
    try {
      final e = await _verifier.refresh();
      if (_userId != asked) return; // the account changed meanwhile
      await _apply(e);
      _log('entitlement refreshed: ${e.access.name}');
    } on VerificationRejected {
      if (_userId == asked) await _apply(const VerifiedEntitlement.free());
    } on VerificationUnavailable catch (u) {
      _log('entitlement refresh unavailable: ${u.code}');
    }
    notifyListeners();
  }

  // --- purchase ---

  Future<PurchaseOutcome> buy(ProPlanKind kind) async {
    final plan = _plansByKind[kind];
    if (!_storeAvailable || plan == null) return PurchaseOutcome.unavailable;
    final user = _verifier.userId;
    if (user == null) return PurchaseOutcome.signInRequired;
    _userId = user;
    _lastError = null;
    _purchasing = true;
    notifyListeners();
    try {
      final started = await _gateway.buy(plan.product, userId: user);
      _log('purchase launch ${plan.product.id}: started=$started');
      if (!started) {
        _purchasing = false;
        notifyListeners();
        return PurchaseOutcome.failed;
      }
      return PurchaseOutcome.started;
    } catch (_) {
      _lastError = 'The purchase could not be started. Please try again.';
      _purchasing = false;
      notifyListeners();
      return PurchaseOutcome.failed;
    }
  }

  /// Asks the store for the person's earlier purchases, has the server check
  /// them, and says what it found.
  Future<RestoreResult> restore() async {
    if (_verifier.userId == null) return RestoreResult.signInRequired;
    if (!_storeAvailable || !ready) {
      // The first answer may still be on its way, or was a miss: ask again.
      if (!_loading) await refreshProducts();
    }
    if (!_storeAvailable) return RestoreResult.unavailable;
    _lastError = null;
    _restoreFound = false;
    _purchasing = true;
    notifyListeners();
    try {
      await _gateway.restore();
    } catch (_) {
      _purchasing = false;
      notifyListeners();
      return RestoreResult.failed;
    }
    // The store reports what it found on its stream; give it a moment.
    if (restoreWait > Duration.zero) await Future<void>.delayed(restoreWait);
    await Future<void>.delayed(Duration.zero);
    await refreshEntitlement();
    _purchasing = false;
    notifyListeners();
    if (_restoreFound || _plans.isPro) return RestoreResult.restored;
    return _lastError != null
        ? RestoreResult.failed
        : RestoreResult.nothingFound;
  }

  Future<void> _onPurchases(List<StorePurchase> purchases) async {
    for (final p in purchases) {
      if (!ProductIds.all.contains(p.productId)) {
        // A cancelled or failed purchase can arrive with no product id.
        if (p.status == StorePurchaseStatus.canceled ||
            p.status == StorePurchaseStatus.error) {
          _purchasing = false;
        }
        continue;
      }
      _log('purchase update: ${p.productId} ${p.status.name}');
      switch (p.status) {
        case StorePurchaseStatus.pending:
          // Paid for later (cash, bank, approval): nothing is unlocked.
          _purchasing = false;
          if (!_plans.isPro) {
            _plans.setPlan(
              const UserPlan.free(),
              access: ProAccess.purchasePending,
            );
          }
        case StorePurchaseStatus.error:
          _purchasing = false;
          final code = (p.errorCode ?? '').toLowerCase();
          final message = p.errorMessage ?? '';
          if (message.toLowerCase().contains('already owned') ||
              code.contains('owned')) {
            // Already on this Google account: check it with the server.
            _lastError = null;
            unawaited(_gateway.restore().catchError((_) {}));
          } else {
            _log('purchase error: $code');
            _lastError = message.isEmpty
                ? 'The purchase could not be completed.'
                : message;
          }
        case StorePurchaseStatus.canceled:
          _purchasing = false;
        case StorePurchaseStatus.purchased:
        case StorePurchaseStatus.restored:
          await _verify(p);
      }
    }
    notifyListeners();
  }

  /// Sends one purchase to the server. The purchase is completed (so Google
  /// Play stops redelivering it) only after the server accepted it.
  Future<void> _verify(StorePurchase p) async {
    final token = p.token;
    final user = _verifier.userId;
    if (token == null || token.isEmpty || user == null) {
      // Signed out or a guest: keep the purchase for when an account is in use.
      _purchasing = false;
      return;
    }
    if (_settled.contains(token) || !_inFlight.add(token)) {
      _purchasing = false; // a repeated callback for the same purchase
      return;
    }
    final fresh = p.status == StorePurchaseStatus.purchased;
    final wasPro = _plans.isPro;
    try {
      if (!wasPro) {
        _plans.setPlan(
          const UserPlan.free(),
          access: ProAccess.verificationPending,
        );
      }
      notifyListeners();
      final e = await _verifier.verify(p.productId, token);
      if (_verifier.userId != user) return; // the account changed meanwhile
      _restoreFound = true;
      await _apply(e);
      _unverified = false;
      _log('verified: ${e.access.name}');
      if (e.isPro) {
        _settled.add(token);
        if (p.pendingComplete) {
          try {
            await _gateway.complete(p);
          } catch (_) {}
        }
        if (fresh && !wasPro) {
          final key = p.purchaseId ?? token;
          final last = await _store.lastCelebrated();
          if (last != key) {
            await _store.setLastCelebrated(key);
            celebrations.value++;
          }
        }
      }
    } on VerificationRejected catch (r) {
      _log('verification rejected: ${r.code}');
      _lastError = r.code == 'owned_by_another_account'
          ? 'This purchase belongs to a different Omni account.'
          : 'Google Play could not confirm this purchase.';
      if (!_plans.isPro) {
        _plans.setPlan(
          const UserPlan.free(),
          access: ProAccess.verificationError,
        );
      }
    } on VerificationUnavailable catch (u) {
      _log('verification unavailable: ${u.code}');
      _unverified = true;
      _lastError =
          'Your purchase could not be confirmed yet. It will be checked '
          'again when you open Omni Plan, and you will not be charged twice.';
      if (!_plans.isPro) {
        _plans.setPlan(
          const UserPlan.free(),
          access: ProAccess.verificationError,
        );
      }
    } finally {
      _inFlight.remove(token);
      _purchasing = false;
    }
  }

  /// Asks Play to deliver a paid but unverified purchase again. Called when the
  /// Pro page opens and by Restore.
  Future<void> retryPending() async {
    if (!_unverified || !_storeAvailable) return;
    _log('retrying an unverified purchase');
    try {
      await _gateway.restore();
    } catch (_) {}
  }

  // --- entitlement ---

  Future<void> _apply(VerifiedEntitlement e) async {
    await _store.setCachedUserId(_userId);
    await _store.setLifetime(e.isPro && e.lifetime);
    await _store.setCancelled(e.access == ProAccess.cancelledActive);
    await _store.setProUntil(e.isPro && !e.lifetime ? e.expiresAt : null);
    await _store.setLastVerified(_now());
    if (!e.isPro) {
      _plans.setPlan(const UserPlan.free(), access: e.access);
    } else if (e.lifetime) {
      _plans.setPlan(const UserPlan.pro(), access: e.access);
    } else {
      _plans.setPlan(UserPlan.pro(expiresAt: e.expiresAt), access: e.access);
    }
  }

  Future<void> _loadCachedEntitlement() async {
    // A saved answer belongs to one account; it is never lent to another.
    if (_userId == null || await _store.cachedUserId() != _userId) {
      await _clearCache();
      _plans.setPlan(const UserPlan.free());
      return;
    }
    final cancelled = await _store.cancelled();
    final until = await _store.proUntil();
    if (await _store.lifetime()) {
      _plans.setPlan(const UserPlan.pro(), access: ProAccess.proActive);
    } else if (until != null && until.isAfter(_now())) {
      _plans.setPlan(
        UserPlan.pro(expiresAt: until),
        access: cancelled ? ProAccess.cancelledActive : ProAccess.proActive,
      );
    } else {
      _plans.setPlan(const UserPlan.free());
    }
  }

  Future<void> _clearCache() async {
    await _store.setCachedUserId(null);
    await _store.setLifetime(false);
    await _store.setProUntil(null);
    await _store.setCancelled(false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    celebrations.dispose();
    super.dispose();
  }
}
