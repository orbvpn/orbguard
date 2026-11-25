/// The plan card on the Me tab: the plan the person is on, and for a free
/// account the two ways forward. Earn a credit is glass; Go unlimited is the
/// tab's one lime action.
///
/// The plan name comes from the account's real subscription. No price shows
/// here: prices come only from the store, on the plans sheet.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/pressable.dart';
import '../../providers/account_provider.dart';
import '../../providers/scan_credit_provider.dart';
import '../scan_credits/credits_sheet.dart';
import 'credit_balance.dart';
import 'login_sheet.dart';
import 'plans_sheet.dart';

class PlanCard extends StatelessWidget {
  const PlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();
    final ScanCreditProvider credits = context.watch<ScanCreditProvider>();

    final List<Widget> children;
    if (account.hasPremium) {
      children = [
        _Head(
          title: '${account.subscriptionLabel} plan',
          chip: _Chip(
            label: 'Unlimited checks',
            fill: AppColors.accentPill,
            ink: Brand.limeInk,
          ),
        ),
        const _Line('Also unlocks OrbVPN and OrbBrowser premium.'),
      ];
    } else if (account.isLoggedIn) {
      final bool known = credits.balanceKnown;
      final bool empty = known && credits.balance < 1;
      children = [
        _Head(
          title: 'Free plan',
          chip: _Chip(
            label: known ? scanCredits(credits.balance) : 'Scan credits',
            fill: empty ? Brand.amberPill : Brand.hairline,
            ink: empty ? Brand.amberInk : Brand.text2,
            onTap: () => showCreditsSheet(context),
          ),
        ),
        const _Line('Each check you start uses one credit.'),
        _Buttons(
          glass: 'Earn a credit',
          onGlass: () => showCreditsSheet(context),
        ),
      ];
    } else {
      children = [
        const _Head(title: 'Free plan'),
        const _Line('Sign in to get scan credits, or go unlimited.'),
        _Buttons(glass: 'Sign in', onGlass: () => showLoginSheet(context)),
      ];
    }

    return FetchCreditBalance(
      child: BrandGlass(
        radius: GlassTheme.radiusLarge,
        elevated: false,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.title, this.chip});

  final String title;
  final Widget? chip;

  @override
  Widget build(BuildContext context) {
    final Widget? chip = this.chip;
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: BrandText.heading(size: 18, color: Brand.text)
                  .copyWith(height: Brand.displayHeight(1.22))),
        ),
        if (chip != null) ...[const SizedBox(width: 10), chip],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.fill,
    required this.ink,
    this.onTap,
  });

  final String label;
  final Color fill;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(Brand.rPill);
    final Widget pill = Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, borderRadius: radius),
      child: Text(label, style: BrandText.title(size: 12, color: ink)),
    );
    if (onTap == null) return pill;
    // A press target as tall as a finger, the pill drawn inside it.
    return Pressable(
      onTap: onTap,
      radius: radius,
      child: SizedBox(height: 44, child: Center(child: pill)),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: BrandText.body(size: 13.5, color: Brand.text2)
          .copyWith(height: Brand.bodyHeight(1.45)));
}

/// The glass action, then Go unlimited in lime. Side by side when they both
/// fit whole; stacked on a screen too narrow for that.
class _Buttons extends StatelessWidget {
  const _Buttons({required this.glass, required this.onGlass});

  final String glass;
  final VoidCallback onGlass;

  static const EdgeInsets _pad =
      EdgeInsets.symmetric(horizontal: 10, vertical: 11);

  @override
  Widget build(BuildContext context) {
    final Widget left =
        BrandButton.secondary(label: glass, onPressed: onGlass, padding: _pad);
    final Widget right = BrandButton(
        label: 'Go unlimited',
        onPressed: () => showPlansSheet(context),
        padding: _pad);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 220) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 10), right],
        );
      }
      return Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      );
    });
  }
}
