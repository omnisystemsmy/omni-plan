import 'package:omni_plan/features/pro/billing_service.dart' show EntitlementStore;
import 'package:omni_plan/features/pro/store_gateway.dart' show ProductIds;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a person stands with Omni Plan Pro. Only a server answer that Google
/// Play confirmed moves someone to [proActive] or [cancelledActive].
enum ProAccess {
  free,
  proActive,

  /// Paid until the date shown; it will not renew.
  cancelledActive,

  /// Google Play is still waiting for the payment (cash, bank, parental OK).
  purchasePending,

  /// A purchase was made and is being checked.
  verificationPending,
  expired,

  /// A purchase could not be confirmed. Pro stays locked.
  verificationError,
}

/// What the server concluded from Google Play's own records.
class VerifiedEntitlement {
  final ProAccess access;
  final bool lifetime;
  final DateTime? expiresAt;
  final bool trial;
  final String? productId;

  const VerifiedEntitlement({
    required this.access,
    this.lifetime = false,
    this.expiresAt,
    this.trial = false,
    this.productId,
  });

  const VerifiedEntitlement.free() : this(access: ProAccess.free);

  bool get isPro =>
      access == ProAccess.proActive || access == ProAccess.cancelledActive;

  factory VerifiedEntitlement.fromJson(Map<String, dynamic> j) {
    final access = switch (j['status']) {
      'active' => ProAccess.proActive,
      'cancelled_active' => ProAccess.cancelledActive,
      'pending' => ProAccess.purchasePending,
      'expired' => ProAccess.expired,
      _ => ProAccess.free,
    };
    final isPro = j['isPro'] == true;
    final grants =
        access == ProAccess.proActive || access == ProAccess.cancelledActive;
    // The flag and the status must agree, or nothing is granted.
    final safe = isPro && grants ? access : (grants ? ProAccess.free : access);
    return VerifiedEntitlement(
      access: safe,
      lifetime: safe == ProAccess.proActive && j['lifetime'] == true,
      expiresAt: j['expiresAt'] is String
          ? DateTime.tryParse(j['expiresAt'] as String)?.toLocal()
          : null,
      trial: j['trial'] == true,
      productId: j['productId'] as String?,
    );
  }
}

/// The server said no: the purchase is not valid, or is another account's.
class VerificationRejected implements Exception {
  final String code;
  const VerificationRejected(this.code);
  @override
  String toString() => 'VerificationRejected($code)';
}

/// The server could not be asked, or is not set up. Nothing is granted, and
/// the purchase is checked again later.
class VerificationUnavailable implements Exception {
  final String code;
  const VerificationUnavailable(this.code);
  @override
  String toString() => 'VerificationUnavailable($code)';
}

/// Asks the trusted backend what a purchase is worth.
abstract class PurchaseVerifier {
  /// The signed-in, non-guest account, or null.
  String? get userId;

  Future<VerifiedEntitlement> verify(String productId, String purchaseToken);

  /// Re-checks the account's stored purchases with Google Play.
  Future<VerifiedEntitlement> refresh();
}

class SupabasePurchaseVerifier implements PurchaseVerifier {
  const SupabasePurchaseVerifier();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  String? get userId {
    try {
      final user = _client.auth.currentUser;
      return user == null || user.isAnonymous ? null : user.id;
    } catch (_) {
      return null; // Supabase is not initialised (tests, no config)
    }
  }

  @override
  Future<VerifiedEntitlement> verify(String productId, String purchaseToken) =>
      _call({
        'action': 'verify',
        'productId': productId,
        'purchaseToken': purchaseToken,
      });

  @override
  Future<VerifiedEntitlement> refresh() => _call({'action': 'refresh'});

  Future<VerifiedEntitlement> _call(Map<String, dynamic> body) async {
    try {
      final r = await _client.functions.invoke('plan-billing', body: body);
      final data = r.data;
      if (data is Map && data['ok'] == true && data['entitlement'] is Map) {
        return VerifiedEntitlement.fromJson(
          Map<String, dynamic>.from(data['entitlement'] as Map),
        );
      }
      throw const VerificationUnavailable('bad_response');
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? '${details['error']}' : 'unavailable';
      if (e.status == 409 || e.status == 422 || e.status == 403) {
        throw VerificationRejected(code);
      }
      throw VerificationUnavailable(code);
    } on VerificationUnavailable {
      rethrow;
    } catch (_) {
      throw const VerificationUnavailable('network');
    }
  }
}

/// Grants Pro from what Google Play itself reports on this device, the same
/// way Omni Tools does: no backend is needed, the Play purchase (and the
/// purchases Play restores at every launch) is the proof.
///
/// A lifetime purchase is kept for good. A subscription is kept for 35 days
/// and renewed each time Play lists it again at launch; if Play stops listing
/// it (cancelled, refunded, expired) for more than 3 days, Pro is dropped.
class PlayDevicePurchaseVerifier implements PurchaseVerifier {
  PlayDevicePurchaseVerifier(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final EntitlementStore _store;
  final DateTime Function() _now;

  static const subscriptionGrace = Duration(days: 35);
  static const staleAfter = Duration(days: 3);

  /// Purchases belong to the Google account on the device, so a signed-in
  /// Omni account is not required; the Omni account is used when there is one.
  @override
  String? get userId {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && !user.isAnonymous) return user.id;
    } catch (_) {}
    return 'device';
  }

  @override
  Future<VerifiedEntitlement> verify(String productId, String purchaseToken) async {
    if (productId == ProductIds.lifetime) {
      return VerifiedEntitlement(
        access: ProAccess.proActive,
        lifetime: true,
        productId: productId,
      );
    }
    if (productId == ProductIds.monthly || productId == ProductIds.yearly) {
      return VerifiedEntitlement(
        access: ProAccess.proActive,
        expiresAt: _now().add(subscriptionGrace),
        productId: productId,
      );
    }
    throw const VerificationRejected('unknown_product');
  }

  @override
  Future<VerifiedEntitlement> refresh() async {
    if (await _store.lifetime()) {
      return const VerifiedEntitlement(access: ProAccess.proActive, lifetime: true);
    }
    final until = await _store.proUntil();
    if (until == null || !until.isAfter(_now())) {
      return const VerifiedEntitlement.free();
    }
    final last = await _store.lastVerified();
    if (last == null || _now().difference(last) > staleAfter) {
      return const VerifiedEntitlement.free();
    }
    return VerifiedEntitlement(access: ProAccess.proActive, expiresAt: until);
  }
}
