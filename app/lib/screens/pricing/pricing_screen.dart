import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/account_provider.dart';
import '../../services/iap/iap_service.dart';
import '../account/login_screen.dart';
import '../legal/legal_screen.dart';

/// The transparent pricing screen — now wired to real in-app purchases.
///
/// This screen's whole pitch IS its honesty, so the copy is held to a strict
/// bar: no countdown timers, no fake "was $X now $Y" strikethroughs, no "N
/// people are viewing this", no pre-checked upsells, no fine-print
/// auto-renew traps, no urgency/guilt language. Prices are NEVER hardcoded —
/// they are read live from the App Store / Play Store (localized to the user's
/// region and currency) via [IapService]. The yearly "N months free" claim is
/// only ever shown when the arithmetic is EXACTLY true (see [_effectiveYearly]).
///
/// Three paid tiers map onto the shared OrbVPN account plans (a purchase here
/// unlocks BOTH OrbGuard and OrbVPN):
///   Guard          → orbguard_basic_*   (→ orb_basic)
///   Guard+         → orbguard_premium_* (→ orb_premium)   [recommended]
///   Guard Ultimate → orbguard_ultimate_*(→ orb_family)
class PricingScreen extends StatefulWidget {
  /// Optional hook invoked after a purchase is verified and the entitlement is
  /// granted — e.g. to dismiss a paywall sheet. Never used to fake a purchase.
  final VoidCallback? onPurchased;

  const PricingScreen({super.key, this.onPurchased});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

enum _BillingCycle { monthly, yearly }

/// A single purchasable protection tier. Prices live in the store — this model
/// carries only the product ids and the (honest, additive) marketing copy.
class _GuardTier {
  final String name;
  final String icon;
  final String tagline;

  /// Store product ids for each billing cycle.
  final String monthlyId;
  final String yearlyId;

  /// The tier this builds on, for an honest "Everything in X, plus:" lead-in.
  final String? inheritsFrom;

  /// NEW protections this tier adds over [inheritsFrom].
  final List<String> features;

  final bool recommended;

  const _GuardTier({
    required this.name,
    required this.icon,
    required this.tagline,
    required this.monthlyId,
    required this.yearlyId,
    this.inheritsFrom,
    required this.features,
    this.recommended = false,
  });

  String productIdFor(_BillingCycle cycle) =>
      cycle == _BillingCycle.monthly ? monthlyId : yearlyId;
}

class _PricingScreenState extends State<PricingScreen> {
  _BillingCycle _cycle = _BillingCycle.monthly;
  StreamSubscription<IapResult>? _resultsSub;

  // Honest, additive tiers: each lists only what it ADDS on top of
  // `inheritsFrom`. Device counts are stated relatively (never a specific
  // number we can't guarantee for a given region/plan); the exact device limit
  // for the account is shown in Settings after purchase.
  // Every claim below is store-review-audited: it must name something the app
  // actually ships TODAY (Apple 2.3.1 / Play misleading-claims). Do not add a
  // feature bullet before the feature is wired end-to-end. ("Scam calls" and
  // "priority support" were removed for exactly that reason; "always-on" was
  // softened because iOS background scanning is launch/resume-based.)
  static const List<_GuardTier> _tiers = [
    _GuardTier(
      name: 'Guard',
      icon: AppIcons.shieldCheck,
      tagline: 'Everyday protection for one person.',
      monthlyId: OrbGuardProductIds.basicMonthly,
      yearlyId: OrbGuardProductIds.basicYearly,
      features: [
        'Automatic spyware & stalkerware monitoring',
        'Scam link, QR code & permission checks',
        'Hidden VPN & proxy detection',
        'Secure device checkups',
      ],
    ),
    _GuardTier(
      name: 'Guard+',
      icon: AppIcons.shieldStar,
      tagline: 'Full coverage for you and your devices.',
      monthlyId: OrbGuardProductIds.premiumMonthly,
      yearlyId: OrbGuardProductIds.premiumYearly,
      inheritsFrom: 'Guard',
      features: [
        'Full scam shield — texts, links & QR codes',
        'Secure call check before sensitive calls',
        'Cover more of your devices',
      ],
      recommended: true,
    ),
    _GuardTier(
      name: 'Guard Ultimate',
      icon: AppIcons.shieldStar,
      tagline: 'Everything, for you and your family.',
      monthlyId: OrbGuardProductIds.ultimateMonthly,
      yearlyId: OrbGuardProductIds.ultimateYearly,
      inheritsFrom: 'Guard+',
      features: [
        'Dark-web & identity breach monitoring',
        'Cover your whole family',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Surface one-shot purchase outcomes as snackbars.
    _resultsSub = IapService.instance.results.listen(_onIapResult);
  }

  @override
  void dispose() {
    _resultsSub?.cancel();
    super.dispose();
  }

  void _onIapResult(IapResult result) {
    if (!mounted) return;
    switch (result.outcome) {
      case IapOutcome.success:
        _snack("You're subscribed — premium features are unlocked.");
        widget.onPurchased?.call();
        break;
      case IapOutcome.failed:
        if (result.message != null) _snack(result.message!);
        break;
      case IapOutcome.canceled:
        // Silent — the user chose to back out.
        break;
      case IapOutcome.pending:
        _snack('Purchase pending — we\'ll finish it as soon as it clears.');
        break;
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choose(_GuardTier tier) async {
    final account = context.read<AccountProvider>();
    final iap = context.read<IapService>();
    final productId = tier.productIdFor(_cycle);

    // Receipt verification is auth-gated (a purchase grants the shared ACCOUNT
    // subscription), so a sign-in must happen first. Send the user to sign in,
    // then continue the purchase if they completed it.
    if (!account.isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (!mounted || !account.isLoggedIn) return;
    }
    await iap.buy(productId);
  }

  /// Best-effort match of the account's subscription tier string to one of the
  /// local tiers, to badge "Current". Null when it doesn't clearly name a paid
  /// tier (the honest default — we never guess a plan the user may not be on).
  static String? _matchTier(String? tier) {
    if (tier == null) return null;
    final t = tier.toLowerCase();
    // OrbVPN plan names map back to our tiers: basic→Guard, premium→Guard+,
    // family/ultimate→Guard Ultimate.
    if (t.contains('family') || t.contains('ultimate')) return 'Guard Ultimate';
    if (t.contains('premium')) return 'Guard+';
    if (t.contains('basic')) return 'Guard';
    for (final tr in _tiers) {
      if (t == tr.name.toLowerCase()) return tr.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final account = context.watch<AccountProvider>();
    final iap = context.watch<IapService>();

    final subscribed = account.isLoggedIn && account.subscriptionValid;
    final currentTier = subscribed ? _matchTier(account.subscriptionTier) : null;

    return GlassPage(
      title: 'Plans',
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Choose your protection',
              style: BrandText.h2(color: cs.onSurface, size: 26)),
          const SizedBox(height: 4),
          Text(
            'Cancel anytime. One subscription covers OrbGuard and OrbVPN.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 15),
          ),
          const SizedBox(height: 16),
          _AccountStateBanner(account: account),
          const SizedBox(height: 16),
          if (!iap.isAvailable && !iap.isLoadingProducts)
            _StoreUnavailableNotice(onRetry: () => iap.loadProducts())
          else ...[
            _CycleToggle(
              cycle: _cycle,
              onChanged: (c) => setState(() => _cycle = c),
            ),
            const SizedBox(height: 20),
            for (final tier in _tiers) ...[
              _TierCard(
                tier: tier,
                cycle: _cycle,
                monthly: iap.productFor(tier.monthlyId),
                yearly: iap.productFor(tier.yearlyId),
                loadingPrices: iap.isLoadingProducts,
                subscribed: subscribed,
                isCurrent: currentTier != null && tier.name == currentTier,
                purchasing:
                    iap.purchasingProductId == tier.productIdFor(_cycle),
                busy: iap.isBusy,
                onSelect: () => _choose(tier),
              ),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 4),
            _RestoreRow(
              busy: iap.isBusy,
              onRestore: () => iap.restore(),
            ),
          ],
          const SizedBox(height: 16),
          const _PromiseBand(),
          const SizedBox(height: 12),
          // Apple 3.1.2: Terms of Use + Privacy Policy must be reachable from
          // the subscription screen itself.
          const _LegalLinksRow(),
        ],
      ),
    );
  }
}

/// "Terms of Service · Privacy Policy" links — required on the paywall by
/// App Store subscription rules (3.1.2).
class _LegalLinksRow extends StatelessWidget {
  const _LegalLinksRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget link(String label, LegalDoc doc) => TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LegalScreen(doc: doc)),
          ),
          child: Text(label,
              style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5)),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link('Terms of Service', LegalDoc.terms),
        Text('·', style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5)),
        link('Privacy Policy', LegalDoc.privacy),
      ],
    );
  }
}

/// Honest banner above the plans, reflecting the real account state.
class _AccountStateBanner extends StatelessWidget {
  final AccountProvider account;
  const _AccountStateBanner({required this.account});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (account.isLoggedIn && account.subscriptionValid) {
      return BrandGlass(
        padding: const EdgeInsets.all(16),
        spectrumBorder: true,
        child: Row(
          children: [
            DuotoneIcon(AppIcons.verifiedCheck,
                size: 22, color: AppColors.accentInk),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text("You're subscribed",
                            style: BrandText.title(
                                color: cs.onSurface, size: 15)),
                      ),
                      const SizedBox(width: 8),
                      GlassBadge(
                        text: account.subscriptionLabel.toUpperCase(),
                        color: AppColors.accentInk,
                        isDark: isDark,
                        fontSize: 10.5,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      'Your premium features are unlocked on OrbGuard & OrbVPN. '
                      'To change or cancel your plan, use your '
                      '${Platform.isAndroid ? 'Google Play' : 'App Store'} '
                      'subscription settings.',
                      style: BrandText.body(
                          color: cs.onSurfaceVariant, size: 13)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (account.isLoggedIn) {
      return GlassCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            DuotoneIcon(AppIcons.shield, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "You're on the Free plan. Choose a plan below to subscribe.",
                style: BrandText.body(color: cs.onSurfaceVariant, size: 13.5),
              ),
            ),
          ],
        ),
      );
    }

    // Logged out — invite sign-in so the real plan can be shown and a purchase
    // can be verified.
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: DuotoneIcon('login', size: 22, color: AppColors.accentInk),
        title: Text('Sign in to subscribe',
            style: BrandText.title(color: cs.onSurface, size: 14.5)),
        subtitle: Text('Use your OrbVPN account — one subscription covers both',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5)),
        trailing: DuotoneIcon('alt_arrow_right',
            size: 20, color: cs.onSurfaceVariant),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
      ),
    );
  }
}

/// Shown when the store can't be reached (e.g. desktop, or a store outage).
class _StoreUnavailableNotice extends StatelessWidget {
  final VoidCallback onRetry;
  const _StoreUnavailableNotice({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon(AppIcons.shield,
                  size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text('The store is unavailable',
                    style: BrandText.title(color: cs.onSurface, size: 15)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Subscriptions are purchased through the App Store or Google Play. '
            'We couldn\'t reach it just now.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 13.5),
          ),
          const SizedBox(height: 14),
          BrandButton.secondary(label: 'Try again', onPressed: onRetry),
        ],
      ),
    );
  }
}

/// Monthly / Yearly segmented toggle (only the active item takes lime).
class _CycleToggle extends StatelessWidget {
  final _BillingCycle cycle;
  final ValueChanged<_BillingCycle> onChanged;

  const _CycleToggle({required this.cycle, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(4),
      borderRadius: Brand.rPill,
      child: Row(
        children: [
          Expanded(child: _segment(context, 'Monthly', _BillingCycle.monthly)),
          Expanded(child: _segment(context, 'Yearly', _BillingCycle.yearly)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, _BillingCycle value) {
    final cs = Theme.of(context).colorScheme;
    final selected = cycle == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentPill : Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.rPill),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: BrandText.title(
            size: 14,
            weight: FontWeight.w600,
            color: selected ? AppColors.accentInk : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final _GuardTier tier;
  final _BillingCycle cycle;

  /// Store products for each cycle (null until loaded / if not found).
  final ProductDetails? monthly;
  final ProductDetails? yearly;
  final bool loadingPrices;

  /// The account already has a live subscription — CTAs must not imply a fresh
  /// purchase.
  final bool subscribed;

  /// This is the subscriber's current tier — badge it and disable its CTA.
  final bool isCurrent;

  /// This exact product is mid-purchase (show a spinner on its CTA).
  final bool purchasing;

  /// Any purchase/restore is in flight (disable other CTAs meanwhile).
  final bool busy;

  final VoidCallback onSelect;

  const _TierCard({
    required this.tier,
    required this.cycle,
    required this.monthly,
    required this.yearly,
    required this.loadingPrices,
    required this.onSelect,
    this.subscribed = false,
    this.isCurrent = false,
    this.purchasing = false,
    this.busy = false,
  });

  ProductDetails? get _selected =>
      cycle == _BillingCycle.monthly ? monthly : yearly;

  Widget _cta() {
    if (isCurrent) {
      return const BrandButton(label: 'Current plan', onPressed: null);
    }
    if (subscribed) {
      return BrandButton.secondary(
        label: 'Included with premium',
        onPressed: null,
      );
    }
    // Disable when the price hasn't loaded (can't purchase what we can't price)
    // or another purchase is in flight.
    final available = _selected != null;
    final enabled = available && !busy;
    final label = available ? 'Choose ${tier.name}' : 'Unavailable';
    if (tier.recommended) {
      return BrandButton(
        label: label,
        isLoading: purchasing,
        onPressed: enabled ? onSelect : null,
      );
    }
    return BrandButton.secondary(
      label: label,
      isLoading: purchasing,
      onPressed: enabled ? onSelect : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = tier.recommended ? AppColors.accentInk : cs.onSurfaceVariant;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tint.withAlpha(30),
                borderRadius: BorderRadius.circular(Brand.rSm),
              ),
              child: Center(
                child: DuotoneIcon(tier.icon, size: 22, color: tint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tier.name,
                  style: BrandText.h2(color: cs.onSurface, size: 21)),
            ),
            if (isCurrent)
              GlassBadge(
                text: 'CURRENT',
                color: AppColors.accentInk,
                isDark: isDark,
                fontSize: 10.5,
              )
            else if (tier.recommended)
              GlassBadge(
                text: 'RECOMMENDED',
                color: AppColors.accentInk,
                isDark: isDark,
                fontSize: 10.5,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(tier.tagline,
            style: BrandText.body(color: cs.onSurfaceVariant, size: 14)),
        const SizedBox(height: 18),
        _PriceRow(
          cycle: cycle,
          monthly: monthly,
          yearly: yearly,
          loading: loadingPrices,
        ),
        const SizedBox(height: 18),
        if (tier.inheritsFrom != null) ...[
          Text(
            'Everything in ${tier.inheritsFrom}, plus:',
            style: BrandText.body(
              color: cs.onSurfaceVariant,
              size: 13,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final feature in tier.features) _FeatureRow(text: feature),
        const SizedBox(height: 20),
        _cta(),
      ],
    );

    if (tier.recommended) {
      return BrandGlass(
        padding: const EdgeInsets.all(20),
        spectrumBorder: true,
        child: content,
      );
    }
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(20),
      child: content,
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String text;
  const _FeatureRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DuotoneIcon(AppIcons.checkCircle,
              size: 17, color: AppColors.accentInk),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(text, style: BrandText.body(color: cs.onSurface, size: 14)),
          ),
        ],
      ),
    );
  }
}

/// The price block for one tier — ALWAYS from the store. States renewal in
/// plain language; the yearly "N months free" note is shown only when it is
/// exactly true.
class _PriceRow extends StatelessWidget {
  final _BillingCycle cycle;
  final ProductDetails? monthly;
  final ProductDetails? yearly;
  final bool loading;

  const _PriceRow({
    required this.cycle,
    required this.monthly,
    required this.yearly,
    required this.loading,
  });

  /// Whole months "free" vs paying monthly — exact integer-cents math, so it is
  /// only ever non-null when the saving is EXACTLY that many whole months.
  int? _freeMonthsIfExact() {
    final m = monthly, y = yearly;
    if (m == null || y == null) return null;
    final monthlyCents = (m.rawPrice * 100).round();
    if (monthlyCents <= 0) return null;
    final yearlyCents = (y.rawPrice * 100).round();
    final savedCents = monthlyCents * 12 - yearlyCents;
    if (savedCents <= 0) return null;
    if (savedCents % monthlyCents != 0) return null;
    return savedCents ~/ monthlyCents;
  }

  /// Effective per-month string when billed yearly, formatted in the store's
  /// currency symbol (rounded to the cent). Null if the yearly price is unknown.
  String? _effectivePerMonth() {
    final y = yearly;
    if (y == null) return null;
    final perMonth = (y.rawPrice / 12);
    final symbol = y.currencySymbol.isNotEmpty ? y.currencySymbol : '';
    return '$symbol${perMonth.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (loading && _selected == null) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Loading price…',
              style: BrandText.body(color: cs.onSurfaceVariant, size: 13)),
        ],
      );
    }

    final product = _selected;
    if (product == null) {
      return Text('Price unavailable',
          style: BrandText.body(color: cs.onSurfaceVariant, size: 14));
    }

    final monthlyCycle = cycle == _BillingCycle.monthly;
    // Headline: the monthly price directly, or the effective /mo for yearly.
    final headline =
        monthlyCycle ? product.price : (_effectivePerMonth() ?? product.price);
    final freeMonths = _freeMonthsIfExact();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(headline,
                  style: BrandText.mono(
                      color: cs.onSurface, size: 30, weight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
            Text('/mo',
                style: BrandText.mono(color: cs.onSurfaceVariant, size: 15)),
          ],
        ),
        const SizedBox(height: 4),
        if (monthlyCycle)
          Text(
            'Renews monthly at ${product.price}.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5),
          )
        else ...[
          Text(
            'Renews yearly at ${product.price}.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5),
          ),
          if (freeMonths != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                freeMonths == 1
                    ? "That's 1 month free versus paying monthly."
                    : "That's $freeMonths months free versus paying monthly.",
                style: BrandText.body(
                  color: AppColors.accentInk,
                  size: 12.5,
                  weight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ],
    );
  }

  ProductDetails? get _selected =>
      cycle == _BillingCycle.monthly ? monthly : yearly;
}

/// "Restore purchases" — required by the App Store and useful on reinstall.
class _RestoreRow extends StatelessWidget {
  final bool busy;
  final VoidCallback onRestore;
  const _RestoreRow({required this.busy, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: TextButton(
        onPressed: busy ? null : onRestore,
        child: Text(
          'Restore purchases',
          style: BrandText.title(color: cs.onSurfaceVariant, size: 13.5),
        ),
      ),
    );
  }
}

/// The honest-pricing promise band — the screen's whole reason for being.
class _PromiseBand extends StatelessWidget {
  const _PromiseBand();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentInk.withAlpha(30),
              borderRadius: BorderRadius.circular(Brand.rSm),
            ),
            child: Center(
              child: DuotoneIcon(AppIcons.shieldCheck,
                  size: 20, color: AppColors.accentInk),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Our promise',
                    style: BrandText.title(color: cs.onSurface, size: 15)),
                const SizedBox(height: 4),
                Text(
                  'The price you see is the price that renews. Cancel anytime, in '
                  'one tap. No hidden fees.',
                  style: BrandText.body(color: cs.onSurfaceVariant, size: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
