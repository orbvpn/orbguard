// lib/widgets/scan_credits/watch_ad_sheet.dart
//
// The "earn a scan credit" sheet: shows the current balance and a single lime
// action to watch a rewarded ad. Presented via [showAppSheet] (the app's one
// iOS-style modal), styled entirely from brand tokens.
//
// HONEST STATES: while a network is configured the primary button earns a credit
// and reports real success/error. When NO network is configured the sheet shows
// an "ads aren't available yet" state with the button DISABLED — it never offers
// a reward it can't deliver, and never fakes one.

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../providers/scan_credit_provider.dart';
import '../../screens/pricing/pricing_screen.dart';

/// Present the earn-a-scan sheet for [provider]. Returns true when a credit was
/// earned before the sheet closed.
Future<bool?> showWatchAdSheet(
  BuildContext context,
  ScanCreditProvider provider,
) {
  return showAppSheet<bool>(
    context,
    child: WatchAdSheet(provider: provider),
  );
}

class WatchAdSheet extends StatefulWidget {
  final ScanCreditProvider provider;
  const WatchAdSheet({super.key, required this.provider});

  @override
  State<WatchAdSheet> createState() => _WatchAdSheetState();
}

class _WatchAdSheetState extends State<WatchAdSheet> {
  bool _earned = false;

  ScanCreditProvider get _p => widget.provider;

  @override
  void initState() {
    super.initState();
    // Best-effort balance refresh on open (no-op / 0 when logged out).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _p.refresh();
    });
  }

  Future<void> _watch() async {
    final ok = await _p.watchAdForCredit(context);
    if (!mounted) return;
    setState(() => _earned = ok);
  }

  /// Close the sheet and open the plans screen (subscribing removes the need
  /// for scan credits entirely). Pops with [_earned] so an already-earned
  /// credit is still honoured by the caller (the sheet's return contract).
  void _openPlans(BuildContext context) {
    Navigator.of(context).pop(_earned);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PricingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _p,
      builder: (context, _) {
        final available = _p.adsAvailable;
        final watching = _p.isWatchingAd;
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Earn a scan credit',
                  style: BrandText.h2(color: cs.onSurface, size: 21)),
              const SizedBox(height: 6),
              Text(
                '${_formatCredits(_p.balance)} scan '
                '${_p.balance == 1 ? 'credit' : 'credits'} available',
                style: BrandText.mono(color: AppColors.text2, size: 13),
              ),
              const SizedBox(height: 14),
              _body(available, watching),
              const SizedBox(height: 22),
              // The single lime action on this sheet.
              BrandButton(
                label: available
                    ? (watching ? 'Playing ad…' : 'Watch ad to earn a scan')
                    : 'Ads unavailable',
                isLoading: watching,
                onPressed: (available && !watching) ? _watch : null,
              ),
              const SizedBox(height: 10),
              // Secondary path: skip ads entirely with a subscription (unlimited
              // scans + every premium feature). Glass/neutral so the lime ad
              // action stays the single primary.
              BrandButton.secondary(
                label: 'Go unlimited with a plan',
                onPressed: watching ? null : () => _openPlans(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(bool available, bool watching) {
    // Honest unavailable state — never a fake reward.
    if (!available) {
      return Text(
        "Rewarded ads aren't available in this build yet, so scan credits can't "
        'be earned by watching an ad right now. Check back after an update.',
        style: BrandText.body(color: AppColors.text2, size: 14),
      );
    }
    if (_earned && !watching) {
      return Text(
        'Nice — 1 scan credit added. Watch another any time to stock up.',
        style: BrandText.body(color: AppColors.accentInk, size: 14),
      );
    }
    final error = _p.lastError;
    if (error != null && !watching) {
      return Text(error,
          style: BrandText.body(color: AppColors.errorInk, size: 14));
    }
    return Text(
      'Watch a short rewarded video to earn one scan credit. The credit lands '
      'only after the ad finishes and the reward is confirmed.',
      style: BrandText.body(color: AppColors.text2, size: 14),
    );
  }

  String _formatCredits(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}
