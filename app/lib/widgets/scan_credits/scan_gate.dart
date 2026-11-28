// lib/widgets/scan_credits/scan_gate.dart
//
// The scan-credit gate for every check a PERSON STARTS: the full check on
// Home, and each on-demand tool (a pasted link or message, a QR code, an
// email breach lookup, a Wi-Fi check, the before-a-call check, the hidden VPN
// check, an app file, the spyware forensics).
//
//   • Premium (subscribed) users check without limit and never see an ad.
//   • Everyone else gets the FIRST check they start on the device free,
//     whatever kind it is, and only that one ([CheckAllowance]). Automatic
//     checks do not use it up.
//   • After that a check costs one scan credit. Credits belong to the
//     account, so a signed-out person is asked to sign in first.
//   • Out of credits, the way on depends on the device:
//       phone          : the credits sheet (watch an ad, or take a plan);
//       Mac            : the Premium sheet, whose lime action opens the plans;
//       Windows, Linux : the Premium sheet with sign-in and a plain link to
//                        the site. No plan, price or store is shown there.
//       Amazon build   : the Premium sheet with sign-in only, on any device.
//                        No plan, price, ad, store or site.
//
// Auto/background scans (auto_scan_scheduler, the one-shot first-run check) do
// NOT call this: the passive safety net is never metered or paywalled.
//
// HONESTY: a credit is only ever spent through ScanCreditProvider.spendForScan
// (OrbNet `/scan/consume`). When the server cannot be reached the gate says so
// and the check does not run. When a free user is out of credits and no
// rewarded-ad network is configured, the credits sheet says so plainly. We
// never fake a credit or a scan.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/account_provider.dart';
import '../../providers/check_allowance.dart';
import '../../providers/scan_credit_provider.dart';
import '../../utils/amazon_build.dart';
import '../../utils/host_platform.dart';
import '../sale/login_sheet.dart';
import 'credits_sheet.dart';
import 'premium_sheet.dart';

/// The credit pools with a gate open on them. A second tap while the first
/// is still being decided must not spend a second credit.
final Expando<bool> _open = Expando<bool>('scan gate open');

/// Gate a user-initiated check. Returns true when the check may proceed.
/// [context] must be mounted on entry.
Future<bool> ensureScanCredit(BuildContext context) async {
  final account = context.read<AccountProvider>();

  // Subscribers scan without limit and never see an ad.
  if (account.hasPremium) return true;

  final credits = context.read<ScanCreditProvider>();
  if (_open[credits] ?? false) return false;
  _open[credits] = true;
  try {
    return await _decide(context, account, credits);
  } finally {
    _open[credits] = null;
  }
}

/// Whether checks cost this person nothing: they are subscribed. A screen
/// that used to run its check as it opened asks this first, and leaves the
/// start to everyone else, since the check is theirs to spend.
bool checksAreUnlimited(BuildContext context) =>
    Provider.of<AccountProvider?>(context, listen: false)?.hasPremium ?? false;

/// Runs [check] once the gate lets it through, and not at all otherwise.
/// Every on-demand tool starts its check through this.
Future<void> runGatedCheck(
  BuildContext context,
  FutureOr<void> Function() check,
) async {
  if (!await ensureScanCredit(context)) return;
  // The screen that asked is gone: there is nowhere to show an answer.
  if (!context.mounted) return;
  await check();
}

Future<bool> _decide(
  BuildContext context,
  AccountProvider account,
  ScanCreditProvider credits,
) async {
  final allowance = context.read<CheckAllowance>();

  // The first check a person starts is free, wherever it starts. Only this
  // gate counts it: the automatic check after setup and background checks
  // never pass here, so they do not use it up.
  if (!await allowance.freeCheckUsed()) {
    await allowance.useFreeCheck();
    return true;
  }
  if (!context.mounted) return false;

  // The Amazon build has no ad to watch and no plan to take, so a phone
  // there goes the way Windows and Linux do.
  return isPhonePlatform(allowance.platform) && !isAmazonBuild(context)
      ? _onPhone(context, account, credits)
      : _onComputer(context, account, credits, allowance.platform);
}

/// A phone: sign in, spend a credit, and when there is none, earn one by
/// watching an ad or take a plan.
Future<bool> _onPhone(
  BuildContext context,
  AccountProvider account,
  ScanCreditProvider credits,
) async {
  // Scan credits require an OrbNet account: send a signed-out user to sign in.
  if (!account.isLoggedIn) {
    final signedIn = await showLoginSheet(context);
    if (signedIn != true || !context.mounted) return false;
    // They may have signed into a subscribed account.
    if (account.hasPremium) return true;
  }

  final result = await credits.spendForScan();
  if (result.success) return true;
  if (!context.mounted) return false;

  if (result.outOfCredits) {
    // Out of credits: offer a rewarded ad (or a plan), then spend the credit
    // it earned.
    final earned = await showCreditsSheet(context);
    if (!context.mounted) return false;
    // They may have taken a plan instead.
    if (account.hasPremium) return true;
    if (earned != true) return false;
    final retry = await credits.spendForScan();
    return retry.success;
  }

  _sayWhy(context, result);
  return false;
}

/// A computer, or any device in the Amazon build: no ad can be watched here,
/// so a credit can only be one the account already holds. Without one the
/// Premium sheet is the way on.
Future<bool> _onComputer(
  BuildContext context,
  AccountProvider account,
  ScanCreditProvider credits,
  TargetPlatform? platform,
) async {
  while (true) {
    if (account.hasPremium) return true;
    if (account.isLoggedIn) {
      final result = await credits.spendForScan();
      if (result.success) return true;
      if (!context.mounted) return false;
      if (!result.outOfCredits) {
        _sayWhy(context, result);
        return false;
      }
    }
    // The sheet answers true only once the account has Premium or a credit,
    // so each turn of this loop follows something the person did.
    final bool? paid = await showPremiumSheet(context, platform: platform);
    if (paid != true || !context.mounted) return false;
  }
}

/// A real failure (offline, server, signed out): say it plainly rather than
/// run an unpaid check.
void _sayWhy(BuildContext context, ConsumeResult result) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(result.error ?? 'Could not start the check.')),
  );
}
