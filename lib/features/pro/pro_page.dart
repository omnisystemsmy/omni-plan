import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:omni_plan/core/theme/omni_design_tokens.dart';
import 'package:omni_plan/features/pro/billing_service.dart';
import 'package:omni_plan/features/pro/plan_service.dart';
import 'package:omni_plan/features/pro/purchase_verifier.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pro offer screen: a bright hero, what you get, and plan cards to pick from.
/// The layout, sizes and behaviour follow the Omni Tools "My plan" page.
class ProPage extends StatefulWidget {
  /// The feature the person was trying to use, when they came from a gate.
  final ProCapability? source;

  final BillingService? billing;
  final PlanService? plan;

  const ProPage({super.key, this.source, this.billing, this.plan});

  @override
  State<ProPage> createState() => _ProPageState();
}

class _ProPageState extends State<ProPage> with SingleTickerProviderStateMixin {
  ProPlanKind _selected = ProPlanKind.yearly;
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  PlanService get _plan => widget.plan ?? PlanService.instance;
  BillingService get _billing => widget.billing ?? BillingService.instance;

  @override
  void initState() {
    super.initState();
    _billing.addListener(_onBilling);
    _plan.addListener(_onBilling);
    if (!_billing.ready && !_billing.loading) _billing.refreshProducts();
    _billing.refreshEntitlement();
    _billing.retryPending();
    if (!WidgetsBinding.instance.disableAnimations) {
      _shine.repeat(reverse: true);
    }
  }

  void _onBilling() {
    if (!mounted) return;
    setState(() {});
    final err = _billing.lastError;
    if (err != null) {
      _billing.clearError();
      _toast(err);
    }
  }

  @override
  void dispose() {
    _billing.removeListener(_onBilling);
    _plan.removeListener(_onBilling);
    _shine.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _subscribe() async {
    HapticFeedback.mediumImpact();
    if (!_billing.ready) {
      // Look again, in case Play was not ready when the page opened.
      if (!_billing.loading) await _billing.refreshProducts();
      if (!mounted) return;
      if (!_billing.ready) {
        _toast(_billing.problemMessage);
        return;
      }
    }
    final outcome = await _billing.buy(_selected);
    if (outcome == PurchaseOutcome.signInRequired && mounted) {
      _toast('Sign in with your Omni account to buy Pro. Guests cannot.');
      return;
    }
    if (outcome == PurchaseOutcome.failed && mounted) {
      _toast('Could not start the purchase. Please try again.');
    }
  }

  Future<void> _restore() async {
    final result = await _billing.restore();
    if (!mounted) return;
    _toast(switch (result) {
      RestoreResult.restored => 'Your purchase has been restored.',
      RestoreResult.nothingFound =>
        'No previous purchase found for this Google account.',
      RestoreResult.failed =>
        'Could not restore purchases. Check your connection and try again.',
      RestoreResult.unavailable =>
        _billing.problemMessage.isEmpty
        ? 'Google Play is not available on this device right now.'
        : _billing.problemMessage,
      RestoreResult.signInRequired =>
        'Sign in with your Omni account to restore Pro.',
    });
  }

  Future<void> _manage() async {
    final ok = await launchUrl(
      Uri.parse(
        'https://play.google.com/store/account/subscriptions'
        '?package=com.omnisystems.omniplan',
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) _toast('Open Google Play to manage your subscription.');
  }

  /// Google Play's price when it answered; the listed price until then.
  String _priceFor(ProPlanOffer o) =>
      _billing.plan(o.kind)?.price ?? o.priceText;

  bool _trialFor(ProPlanOffer o) {
    final store = _billing.plan(o.kind);
    return store != null ? store.hasTrial : o.hasTrial;
  }

  String get _ctaLabel {
    if (_plan.isPro) {
      return _plan.isLifetime ? 'You have lifetime Pro' : 'Manage subscription';
    }
    final offer = ProPricing.offerFor(_selected);
    if (_trialFor(offer)) return 'Start ${ProPricing.trialDays}-day free trial';
    return offer.kind == ProPlanKind.lifetime
        ? 'Get lifetime access'
        : 'Subscribe';
  }

  String? get _statusLine => switch (_billing.access) {
    ProAccess.purchasePending =>
      'Your payment is pending. Pro unlocks once Google Play confirms it.',
    ProAccess.verificationPending => 'Confirming your purchase…',
    ProAccess.verificationError =>
      'We could not confirm your purchase yet, so Pro stays locked. Tap '
          'Restore to check again.',
    ProAccess.expired => 'Your Pro subscription has ended.',
    _ => null,
  };

  String get _chargeNote {
    final offer = ProPricing.offerFor(_selected);
    final price = _priceFor(offer);
    switch (offer.kind) {
      case ProPlanKind.yearly:
        return _trialFor(offer)
            ? 'Free for ${ProPricing.trialDays} days, then $price per year. '
                  'Google Play reminds you before you are charged. Cancel '
                  'anytime in Google Play.'
            : '$price per year. Cancel anytime in Google Play.';
      case ProPlanKind.monthly:
        return '$price per month. Cancel anytime in Google Play.';
      case ProPlanKind.lifetime:
        return 'One payment of $price. No subscription, no renewal.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPro = _plan.isPro;
    final expiry = _plan.expiresAt;
    final benefits = proBenefits();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _Hero(shine: _shine, isPro: isPro),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        OmniDesignTokens.pageInset + 4,
                        24,
                        OmniDesignTokens.pageInset + 4,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isPro)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                expiry == null
                                    ? 'Your Pro plan is active. Thank you!'
                                    : _billing.access ==
                                          ProAccess.cancelledActive
                                    ? 'Cancelled. Pro stays until ${DateFormat('dd MMM yyyy').format(expiry)}'
                                    : 'Renews ${DateFormat('dd MMM yyyy').format(expiry)}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else if (_statusLine != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _statusLine!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (widget.source != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                'This feature is part of Omni Plan Pro.',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          for (var i = 0; i < benefits.length; i++) ...[
                            if (i == 0 ||
                                benefits[i].group != benefits[i - 1].group)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: i == 0 ? 0 : 8,
                                  bottom: 12,
                                ),
                                child: Text(
                                  benefits[i].group.toUpperCase(),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                            _BenefitRow(benefit: benefits[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _PurchaseBar(
                isPro: isPro,
                selected: _selected,
                onSelect: (k) => setState(() => _selected = k),
                ctaLabel: _ctaLabel,
                note: isPro ? null : _chargeNote,
                onCta: isPro ? (_plan.isLifetime ? null : _manage) : _subscribe,
                busy: _billing.purchasing,
                priceFor: _priceFor,
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.18),
              ),
            ),
          ),
          if (!isPro)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: TextButton(
                onPressed: _billing.purchasing ? null : _restore,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black.withValues(alpha: 0.18),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('Restore'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final Animation<double> shine;
  final bool isPro;

  const _Hero({required this.shine, required this.isPro});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, top + 56, 24, 32),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: OmniDesignTokens.deepGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(right: -60, top: -40, child: _bubble(200, 0.10)),
          Positioned(left: -50, bottom: -60, child: _bubble(160, 0.08)),
          Column(
            children: [
              AnimatedBuilder(
                animation: shine,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(shine.value);
                  return Container(
                    width: 108,
                    height: 108,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.16),
                      boxShadow: [
                        BoxShadow(
                          color: OmniDesignTokens.accentAmber.withValues(
                            alpha: 0.25 + 0.30 * t,
                          ),
                          blurRadius: 24 + 22 * t,
                          spreadRadius: 2 + 6 * t,
                        ),
                      ],
                    ),
                    child: Transform.scale(
                      scale: 1 + 0.06 * t,
                      child: ShaderMask(
                        shaderCallback: (rect) => const LinearGradient(
                          colors: [Color(0xFFFFE08A), Color(0xFFF2A413)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(rect),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          size: 64,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Text(
                'Omni Plan Pro',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isPro
                    ? 'You have everything unlocked'
                    : 'Import more, automate more',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bubble(double size, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );
}

class _BenefitRow extends StatelessWidget {
  final ProBenefit benefit;

  const _BenefitRow({required this.benefit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Icon(benefit.icon, color: cs.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benefit.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  benefit.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_rounded,
              color: cs.primary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseBar extends StatelessWidget {
  final bool isPro;
  final ProPlanKind selected;
  final ValueChanged<ProPlanKind> onSelect;
  final String ctaLabel;
  final String? note;
  final VoidCallback? onCta;
  final bool busy;
  final String Function(ProPlanOffer) priceFor;

  const _PurchaseBar({
    required this.isPro,
    required this.selected,
    required this.onSelect,
    required this.ctaLabel,
    required this.note,
    required this.onCta,
    required this.busy,
    required this.priceFor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: isLight
            ? const [
                BoxShadow(
                  color: Color(0x1F202124),
                  blurRadius: 24,
                  offset: Offset(0, -6),
                ),
              ]
            : null,
        border: isLight
            ? null
            : Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            OmniDesignTokens.pageInset,
            16,
            OmniDesignTokens.pageInset,
            10,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isPro) ...[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < ProPricing.offers.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _PlanTile(
                            offer: ProPricing.offers[i],
                            price: priceFor(ProPricing.offers[i]),
                            selected: selected == ProPricing.offers[i].kind,
                            onTap: () => onSelect(ProPricing.offers[i].kind),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: busy ? null : onCta,
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(ctaLabel),
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 8),
                Text(
                  note!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  final ProPlanOffer offer;
  final String price;
  final bool selected;
  final VoidCallback onTap;

  const _PlanTile({
    required this.offer,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isYearly = offer.kind == ProPlanKind.yearly;
    final isLifetime = offer.kind == ProPlanKind.lifetime;
    const amber = OmniDesignTokens.accentAmber;

    final perMonth = isYearly
        ? 'RM${ProPricing.yearlyPerMonth.toStringAsFixed(2)}/mo'
        : (isLifetime ? 'pay once' : 'billed monthly');

    final tile = InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: OmniDesignTokens.mediumMotion,
        padding: const EdgeInsets.fromLTRB(10, 18, 10, 14),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.08)
              : theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? cs.primary : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              offer.label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (isYearly)
              Text(
                'RM${(ProPricing.monthly.price * 12).toStringAsFixed(0)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                ),
              )
            else
              const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                price,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: selected ? cs.primary : null,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              perMonth,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    String? badge;
    Color? badgeColor;
    if (isYearly) {
      badge = 'Save ${ProPricing.yearlySavingsPercent}%';
      badgeColor = cs.primary;
    } else if (isLifetime) {
      badge = 'Best deal';
      badgeColor = amber;
    }

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        tile,
        if (badge != null)
          Positioned(
            top: -10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(
                    OmniDesignTokens.radiusPill,
                  ),
                ),
                child: Text(
                  badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
