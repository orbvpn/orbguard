// lib/widgets/premium/premium_gate.dart
//
// Premium gating for OrbGuard. The decided model: a valid subscription unlocks
// EVERYTHING — the free tier is basic, on-demand scanning; a subscriber gets
// the ad-free experience, the Pro/expert console, deeper & unlimited scans and
// remote control/camera. The one gating key is [AccountProvider.hasPremium]
// (isLoggedIn && subscriptionValid).
//
// [PremiumGate.ensure] is the single call sites make before running a premium
// action: it returns true when the user is entitled, otherwise it presents an
// honest upsell sheet (it never silently no-ops) and returns false. The upsell
// adapts to WHY access is denied — sign in when logged out, or see plans when
// signed in without a live subscription. [PremiumBadge] is a small lock pill
// for gated tiles.

import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/sheet_panel.dart';
import '../../providers/account_provider.dart';
import '../../utils/amazon_build.dart';
import '../sale/login_sheet.dart';
import '../sale/plans_sheet.dart';

/// Namespace for the app's premium gate. Not instantiable — use the statics.
class PremiumGate {
  const PremiumGate._();

  /// Returns true when [account] is entitled to premium ([hasPremium]).
  /// Otherwise it presents an upsell sheet explaining that [feature] is a
  /// premium feature and returns false — the caller MUST NOT run the gated
  /// action when this returns false.
  ///
  /// The sheet's primary action depends on why access is denied:
  ///  • logged out                     → opens the sign-in sheet (an OrbVPN
  ///    subscription rides on the account, so signing in comes first);
  ///  • signed in, no live subscription → opens the plans sheet.
  static bool ensure(
    BuildContext context,
    AccountProvider account, {
    String? feature,
  }) {
    if (account.hasPremium) return true;
    _presentUpsell(context, account, feature: feature);
    return false;
  }

  static void _presentUpsell(
    BuildContext context,
    AccountProvider account, {
    String? feature,
  }) {
    final loggedIn = account.isLoggedIn;
    // The Amazon build sells nothing and shows no ads: the sheet says what
    // the feature needs, and signs in an account that already has it.
    final amazon = isAmazonBuild(context);
    final cs = Theme.of(context).colorScheme;
    final what = (feature == null || feature.isEmpty)
        ? 'This feature'
        : feature;

    final String closing;
    if (amazon) {
      closing = loggedIn
          ? 'This account has no Premium yet.'
          : 'Already have Premium? Sign in and it works here too.';
    } else {
      closing = loggedIn
          ? "You're signed in. Choose a plan to subscribe."
          : 'Sign in with your OrbVPN account to subscribe.';
    }

    showAppSheet(
      context,
      child: SheetPanel(
        title: 'Premium feature',
        titleIcon: DuotoneIcon(
          AppIcons.lockKeyhole,
          color: AppColors.accentInk,
          size: 24,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              amazon
                  ? '$what is part of OrbGuard Premium, along with:'
                  : '$what is part of OrbGuard premium. A subscription '
                      'unlocks it, along with everything else.',
              style: BrandText.body(color: cs.onSurfaceVariant, size: 14.5),
            ),
            const SizedBox(height: 16),
            if (!amazon) const _Benefit('Ad-free: no watching ads for credits'),
            const _Benefit(
              'Expert (Pro) console: threat intel & enterprise tools',
            ),
            const _Benefit('Deeper, unlimited scans'),
            const _Benefit('Remote control & camera for a lost device'),
            const SizedBox(height: 12),
            Text(
              closing,
              style: BrandText.body(color: cs.onSurfaceVariant, size: 13),
            ),
          ],
        ),
        // Signed in to the Amazon build there is nothing to do but close.
        secondaryLabel: amazon && loggedIn ? null : 'Not now',
        primaryLabel: loggedIn ? (amazon ? 'Got it' : 'See plans') : 'Sign in',
        onPrimary: () {
          if (!context.mounted) return;
          if (!loggedIn) {
            showLoginSheet(context);
          } else if (!amazon) {
            showPlansSheet(context);
          }
        },
      ),
    );
  }
}

/// A single upsell benefit row — a lime check + one plain-language line.
class _Benefit extends StatelessWidget {
  final String text;
  const _Benefit(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DuotoneIcon(
            AppIcons.checkCircle,
            size: 17,
            color: AppColors.accentInk,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: BrandText.body(color: cs.onSurface, size: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small "premium" lock pill for a gated tile. Follows the kit's chip rule
/// (accent pill fill + accent ink) so only the badge takes the accent — the
/// rest of the tile stays neutral.
class PremiumBadge extends StatelessWidget {
  /// Short uppercase label; defaults to "PREMIUM".
  final String label;
  const PremiumBadge({super.key, this.label = 'PREMIUM'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentPill,
        borderRadius: BorderRadius.circular(Brand.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(
            AppIcons.lockKeyhole,
            size: 12,
            color: AppColors.accentInk,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: BrandText.label(color: AppColors.accentInk, size: 10.5),
          ),
        ],
      ),
    );
  }
}
