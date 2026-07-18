// lib/widgets/scan_credits/scan_gate.dart
//
// The scan-credit gate for USER-INITIATED device scans.
//
//   • Premium (subscribed) users scan without limit and never see an ad.
//   • Free users spend one scan credit per scan, earning more by watching a
//     rewarded ad when they run out.
//   • Scan credits are account-scoped, so a signed-out user is routed to sign
//     in first (no account ⇒ no credits).
//
// Auto/background scans (auto_scan_scheduler, the one-shot first-run check) do
// NOT call this — the passive safety net is never metered or paywalled.
//
// HONESTY: when a free user is out of credits and no rewarded-ad network is
// configured, the watch-ad sheet says so plainly and the scan does not run —
// we never fake a credit or a scan.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/account_provider.dart';
import '../../providers/scan_credit_provider.dart';
import '../../screens/account/login_screen.dart';
import 'watch_ad_sheet.dart';

/// Gate a user-initiated scan. Returns true when the scan may proceed.
/// [context] must be mounted on entry.
Future<bool> ensureScanCredit(BuildContext context) async {
  final account = context.read<AccountProvider>();

  // Subscribers scan without limit and never see an ad.
  if (account.hasPremium) return true;

  // Scan credits require an OrbNet account — route a signed-out user to sign in.
  if (!account.isLoggedIn) {
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (signedIn != true || !context.mounted) return false;
    // They may have signed into a subscribed account.
    if (account.hasPremium) return true;
  }

  final credits = context.read<ScanCreditProvider>();
  final result = await credits.spendForScan();
  if (result.success) return true;
  if (!context.mounted) return false;

  if (result.outOfCredits) {
    // Out of credits — offer a rewarded ad, then spend the credit it earned.
    final earned = await showWatchAdSheet(context, credits);
    if (earned != true || !context.mounted) return false;
    final retry = await credits.spendForScan();
    return retry.success;
  }

  // A real failure (offline / server / signed out) — surface it honestly rather
  // than run an unpaid scan.
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(result.error ?? 'Could not start the scan.')),
  );
  return false;
}
