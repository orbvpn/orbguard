import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/account_provider.dart';
import '../account/login_screen.dart';

/// Phase 3.5 — the transparent pricing screen.
///
/// This screen's whole pitch IS its honesty, so the copy is held to a strict
/// bar: no countdown timers, no fake "was $X now $Y" strikethroughs, no "N
/// people are viewing this", no pre-checked upsells, no fine-print
/// auto-renew traps, no urgency/guilt language. Every plan states its real
/// monthly price and its real yearly price; the yearly price is always shown
/// as the honest effective-per-month figure — never a fabricated "% off".
/// A "N months free" claim is only ever shown when the arithmetic is
/// EXACTLY true (see [_Plan.freeMonthsIfExact]).
///
/// UI-only placeholder: plans are a small in-Dart model ([_Plan]); choosing
/// one calls [onSelectPlan]. No StoreKit / Google Billing is wired up here —
/// the parent screen hooks up the real purchase flow later.
class PricingScreen extends StatefulWidget {
  /// Called when the user taps any plan's choose-button (Free, Guard or
  /// Guard+). This screen does no real purchase, so which plan was tapped is
  /// used only locally (to word the placeholder confirmation) — the
  /// callback itself carries no argument. When null, tapping a plan shows a
  /// SnackBar acknowledging the tap instead of a no-op, so the placeholder
  /// state is never silent.
  final VoidCallback? onSelectPlan;

  const PricingScreen({super.key, this.onSelectPlan});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

enum _BillingCycle { monthly, yearly }

/// A single pricing tier. Fields are plain data so the whole model is
/// `const` — no live pricing/store lookups happen on this screen.
class _Plan {
  final String name;
  final String icon;
  final String tagline;

  /// Real monthly price, USD. 0 for the free tier.
  final double monthlyPrice;

  /// Real price billed once a year, USD. 0 for the free tier.
  final double yearlyPrice;

  /// The tier this plan builds on, for an honest "Everything in X, plus:"
  /// lead-in. Null for the base (free) tier.
  final String? inheritsFrom;

  /// NEW protections this tier adds over [inheritsFrom] (or, for the base
  /// tier, its full feature set).
  final List<String> features;

  /// Protections this tier honestly does NOT include — stated plainly
  /// rather than left for the user to assume.
  final List<String> excluded;

  final bool recommended;

  const _Plan({
    required this.name,
    required this.icon,
    required this.tagline,
    required this.monthlyPrice,
    required this.yearlyPrice,
    this.inheritsFrom,
    required this.features,
    this.excluded = const [],
    this.recommended = false,
  });

  bool get isFree => monthlyPrice <= 0 && yearlyPrice <= 0;

  /// Real effective per-month price when billed yearly, rounded to the
  /// nearest cent via integer-cents math (avoids floating-point display
  /// artifacts like "$8.324999...").
  double get effectiveMonthlyWhenYearly {
    final yearlyCents = (yearlyPrice * 100).round();
    final perMonthCents = (yearlyCents / 12).round();
    return perMonthCents / 100;
  }

  /// Whole months "free" vs. paying monthly — computed with exact integer
  /// cents so this is only ever non-null when the saving is EXACTLY that
  /// many whole months' worth (never an approximation or a rounded claim).
  int? get freeMonthsIfExact {
    final monthlyCents = (monthlyPrice * 100).round();
    if (monthlyCents <= 0) return null;
    final yearlyCents = (yearlyPrice * 100).round();
    final savedCents = monthlyCents * 12 - yearlyCents;
    if (savedCents <= 0) return null;
    if (savedCents % monthlyCents != 0) return null;
    return savedCents ~/ monthlyCents;
  }
}

String _money(double v) => '\$${v.toStringAsFixed(2)}';

class _PricingScreenState extends State<PricingScreen> {
  _BillingCycle _cycle = _BillingCycle.monthly;

  // Honest, additive tiers: each plan's `features` lists only what it adds
  // on top of `inheritsFrom` — Guard+ includes everything in Guard, which
  // includes everything in Free. `excluded` says plainly what a tier does
  // NOT (yet) cover, rather than leaving it ambiguous.
  static const List<_Plan> _plans = [
    _Plan(
      name: 'Free',
      icon: AppIcons.shield,
      tagline: 'See the basics, on demand.',
      monthlyPrice: 0,
      yearlyPrice: 0,
      features: [
        'One-tap spyware & stalkerware checkup',
        'Scam link & QR code checker',
        'Privacy permission report',
        '1 device',
      ],
      excluded: [
        'Automatic, always-on monitoring',
        'Dark-web identity monitoring',
      ],
    ),
    _Plan(
      name: 'Guard',
      icon: AppIcons.shieldCheck,
      tagline: 'Always-on protection for one person.',
      monthlyPrice: 4.99,
      yearlyPrice: 49.90,
      inheritsFrom: 'Free',
      features: [
        'Automatic, always-on spyware & stalkerware monitoring',
        'Full scam shield — texts, links, QR codes & scam calls',
        'Hidden VPN & proxy detection',
        'Secure call check before sensitive calls',
        'Up to 3 devices',
      ],
      excluded: [
        'Dark-web identity monitoring',
      ],
      recommended: true,
    ),
    _Plan(
      name: 'Guard+',
      icon: AppIcons.shieldStar,
      tagline: 'Full coverage for you and your family.',
      monthlyPrice: 9.99,
      yearlyPrice: 99.90,
      inheritsFrom: 'Guard',
      features: [
        'Dark-web & identity breach monitoring',
        'Up to 5 devices',
        'Priority alerts & support',
      ],
    ),
  ];

  void _choosePlan(BuildContext context, _Plan plan) {
    if (widget.onSelectPlan != null) {
      widget.onSelectPlan!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${plan.name} selected. No purchase was made — checkout '
          "isn't wired up yet.",
        ),
      ),
    );
  }

  /// Best-effort match of an OrbNet subscription tier string to one of the
  /// local marketing plans, so a subscriber's plan can be badged "Current".
  /// Returns null when the tier doesn't clearly name a paid plan — the honest
  /// default (we never guess a plan the user may not actually be on); the
  /// "You're subscribed" banner still states the real tier either way.
  static String? _matchPlan(String? tier) {
    if (tier == null) return null;
    final t = tier.toLowerCase();
    for (final p in _plans) {
      if (p.isFree) continue;
      final n = p.name.toLowerCase();
      if (t == n || t.contains(n)) return p.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Reflect the real account/subscription state — the screen must never
    // imply a fresh purchase to someone who's already subscribed.
    final account = context.watch<AccountProvider>();
    final subscribed = account.isLoggedIn && account.subscriptionValid;
    final currentPlan =
        subscribed ? _matchPlan(account.subscriptionTier) : null;

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
            'Three honest plans. Upgrade, downgrade, or cancel whenever you want.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 15),
          ),
          const SizedBox(height: 16),
          _AccountStateBanner(account: account),
          const SizedBox(height: 16),
          _CycleToggle(
            cycle: _cycle,
            onChanged: (c) => setState(() => _cycle = c),
          ),
          const SizedBox(height: 20),
          for (final plan in _plans) ...[
            _PlanCard(
              plan: plan,
              cycle: _cycle,
              subscribed: subscribed,
              isCurrent: currentPlan != null && plan.name == currentPlan,
              onSelect: () => _choosePlan(context, plan),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 4),
          const _PromiseBand(),
        ],
      ),
    );
  }
}

/// Honest banner above the plans, reflecting the real account state:
///  • subscribed      → a "You're subscribed" banner naming the real tier;
///  • signed-in, free → a plain "You're on the Free plan" note;
///  • logged out      → a "Sign in to see your plan" row linking to sign-in.
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
                  Text('Your premium features are unlocked.',
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

    // Logged out — invite sign-in so the real plan can be shown.
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: DuotoneIcon('login', size: 22, color: AppColors.accentInk),
        title: Text('Sign in to see your plan',
            style: BrandText.title(color: cs.onSurface, size: 14.5)),
        subtitle: Text('Use your OrbVPN account to check your subscription',
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

/// Monthly / Yearly segmented toggle. Follows the kit's "only the active
/// item takes lime" chip rule ([AppColors.accentPill] fill + [AppColors]
/// `.accentInk` label) — the same pairing used for selected filter chips
/// elsewhere in the app, not a second competing CTA.
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
          Expanded(
              child: _segment(context, 'Monthly', _BillingCycle.monthly)),
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

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final _BillingCycle cycle;
  final VoidCallback onSelect;

  /// The account already has a live subscription — CTAs must not imply a fresh
  /// purchase.
  final bool subscribed;

  /// This is the subscriber's current plan — badge it and disable its CTA.
  final bool isCurrent;

  const _PlanCard({
    required this.plan,
    required this.cycle,
    required this.onSelect,
    this.subscribed = false,
    this.isCurrent = false,
  });

  /// The plan's action button. When the account is already subscribed the CTA
  /// never implies a fresh purchase: the current plan reads "Current plan"
  /// (disabled); any other plan reads that it's included/free (disabled). Only
  /// a non-subscriber gets an actionable "Choose …" button.
  Widget _planCta() {
    if (isCurrent) {
      return const BrandButton(label: 'Current plan', onPressed: null);
    }
    if (subscribed) {
      return BrandButton.secondary(
        label: plan.isFree ? 'Free plan' : 'Included with premium',
        onPressed: null,
      );
    }
    return plan.recommended
        ? BrandButton(label: 'Choose ${plan.name}', onPressed: onSelect)
        : BrandButton.secondary(
            label: plan.isFree ? 'Continue with Free' : 'Choose ${plan.name}',
            onPressed: onSelect,
          );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = plan.recommended ? AppColors.accentInk : cs.onSurfaceVariant;

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
                child: DuotoneIcon(plan.icon, size: 22, color: tint),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(plan.name,
                  style: BrandText.h2(color: cs.onSurface, size: 21)),
            ),
            if (isCurrent)
              GlassBadge(
                text: 'CURRENT',
                color: AppColors.accentInk,
                isDark: isDark,
                fontSize: 10.5,
              )
            else if (plan.recommended)
              GlassBadge(
                text: 'RECOMMENDED',
                color: AppColors.accentInk,
                isDark: isDark,
                fontSize: 10.5,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(plan.tagline,
            style: BrandText.body(color: cs.onSurfaceVariant, size: 14)),
        const SizedBox(height: 18),
        _PriceRow(plan: plan, cycle: cycle),
        const SizedBox(height: 18),
        if (plan.inheritsFrom != null) ...[
          Text(
            'Everything in ${plan.inheritsFrom}, plus:',
            style: BrandText.body(
              color: cs.onSurfaceVariant,
              size: 13,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final feature in plan.features) _FeatureRow(text: feature),
        if (plan.excluded.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Not included: ${plan.excluded.join(', ')}.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5),
          ),
        ],
        const SizedBox(height: 20),
        _planCta(),
      ],
    );

    if (plan.recommended) {
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
          DuotoneIcon(AppIcons.checkCircle, size: 17, color: AppColors.accentInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: BrandText.body(color: cs.onSurface, size: 14)),
          ),
        ],
      ),
    );
  }
}

/// The price block for one plan. States renewal in plain language — never a
/// fake "was/now" pair, never a manufactured percentage-off.
class _PriceRow extends StatelessWidget {
  final _Plan plan;
  final _BillingCycle cycle;
  const _PriceRow({required this.plan, required this.cycle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (plan.isFree) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('Free',
              style: BrandText.mono(
                  color: cs.onSurface, size: 30, weight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text('no card required',
              style: BrandText.body(color: cs.onSurfaceVariant, size: 13)),
        ],
      );
    }

    final monthly = cycle == _BillingCycle.monthly;
    final headline =
        monthly ? plan.monthlyPrice : plan.effectiveMonthlyWhenYearly;
    final freeMonths = plan.freeMonthsIfExact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(_money(headline),
                style: BrandText.mono(
                    color: cs.onSurface, size: 30, weight: FontWeight.w700)),
            const SizedBox(width: 4),
            Text('/mo',
                style: BrandText.mono(color: cs.onSurfaceVariant, size: 15)),
          ],
        ),
        const SizedBox(height: 4),
        if (monthly)
          Text(
            'Renews monthly at ${_money(plan.monthlyPrice)}.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5),
          )
        else ...[
          Text(
            'Billed ${_money(plan.yearlyPrice)} once a year.',
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
                  'The price you see is the price that renews. Cancel anytime, in one '
                  'tap. No hidden fees.',
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
