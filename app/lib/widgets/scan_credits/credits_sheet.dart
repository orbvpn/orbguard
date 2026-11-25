/// The credits sheet: the free path, told honestly.
///
/// Each check a person starts uses one scan credit. The sheet shows the
/// balance the server gave, a glass button to earn a credit by watching a
/// rewarded ad, and the one lime action: go unlimited with a plan.
///
/// HONEST STATES: no numeral until the server has said the balance (and none
/// at all when signed out, where there is no balance). When this build has no
/// ad network the ad button is off and says so; it never offers a reward it
/// cannot deliver, and never fakes one. A failed ad or refresh shows the
/// provider's own message.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/account_provider.dart';
import '../../providers/scan_credit_provider.dart';
import '../sale/login_sheet.dart';
import '../sale/plans_sheet.dart';

/// Presents the credits sheet. Completes with true when a credit was earned
/// before it closed, however it closed.
Future<bool?> showCreditsSheet(BuildContext context) async {
  bool earned = false;
  final bool? popped = await showAppSheet<bool>(
    context,
    child: CreditsSheet(
      onEarned: () => earned = true,
      onGoUnlimited: () {
        if (context.mounted) showPlansSheet(context);
      },
    ),
  );
  return popped == true || earned;
}

/// A whole number prints as one ("3"); anything else with one decimal.
String formatCredits(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class CreditsSheet extends StatefulWidget {
  const CreditsSheet({super.key, this.onEarned, this.onGoUnlimited});

  /// Called as soon as a credit lands.
  final VoidCallback? onEarned;

  /// Called after this sheet has closed for the plans.
  final VoidCallback? onGoUnlimited;

  @override
  State<CreditsSheet> createState() => _CreditsSheetState();
}

class _CreditsSheetState extends State<CreditsSheet> {
  bool _earned = false;

  @override
  void initState() {
    super.initState();
    // The balance as the server has it now (a no-op when signed out).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ScanCreditProvider>().refresh();
    });
  }

  Future<void> _watch() async {
    final ScanCreditProvider credits = context.read<ScanCreditProvider>();
    setState(() => _earned = false);
    final bool ok = await credits.watchAdForCredit(context);
    if (!mounted) return;
    if (ok) widget.onEarned?.call();
    setState(() => _earned = ok);
  }

  Future<void> _signIn() async {
    final ScanCreditProvider credits = context.read<ScanCreditProvider>();
    final bool? signedIn = await showLoginSheet(context);
    if (signedIn == true && mounted) await credits.refresh();
  }

  void _goUnlimited() {
    Navigator.of(context).pop(_earned);
    widget.onGoUnlimited?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final AccountProvider account = context.watch<AccountProvider>();
    final ScanCreditProvider credits = context.watch<ScanCreditProvider>();

    final bool signedIn = account.isLoggedIn;
    final bool watching = credits.isWatchingAd;
    final bool showNumber = signedIn && credits.balanceKnown;
    final double balance = credits.balance;

    final String sentence = !signedIn
        ? 'Each check you start uses one credit. Sign in to get yours.'
        : (showNumber && balance < 1)
            ? 'You are out of credits. Earn one, or go unlimited.'
            : 'Each check you start uses one credit.';

    // One plain line under the sentence, when there is something to say.
    String? note;
    Color? noteInk;
    final String? error = credits.lastError;
    if (signedIn && !credits.adsAvailable) {
      note = 'A credit cannot be earned by watching an ad in this build yet.';
      noteInk = Brand.text2;
    } else if (_earned && !watching) {
      note = '1 scan credit added.';
      noteInk = AppColors.accentInk;
    } else if (error != null && !watching) {
      note = error;
      noteInk = AppColors.errorInk;
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: BrandGlassCircle(
              size: 56,
              child:
                  DuotoneIcon(AppIcons.ticket, size: 26, color: Brand.limeInk),
            ),
          ),
          const SizedBox(height: 14),
          if (showNumber)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(formatCredits(balance),
                    style: BrandText.numeral(size: 44, color: cs.onSurface)),
                const SizedBox(width: 8),
                Text(balance == 1 ? 'scan credit' : 'scan credits',
                    style: BrandText.body(size: 15, color: Brand.text2)),
              ],
            )
          else
            Semantics(
              header: true,
              child: Text('Scan credits',
                  textAlign: TextAlign.center,
                  style: BrandText.h2(color: cs.onSurface, size: 23)),
            ),
          const SizedBox(height: 10),
          Text(sentence,
              textAlign: TextAlign.center,
              style: BrandText.body(size: 15, color: Brand.text2)),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note,
                textAlign: TextAlign.center,
                style: BrandText.body(size: 14, color: noteInk)
                    .copyWith(height: Brand.bodyHeight(1.45))),
          ],
          const SizedBox(height: 22),
          if (signedIn)
            BrandButton.secondary(
              label: 'Watch ad to earn a scan',
              svgPath: 'assets/icons/${AppIcons.play}.svg',
              isLoading: watching,
              onPressed: (credits.adsAvailable && !watching) ? _watch : null,
            )
          else
            BrandButton.secondary(label: 'Sign in', onPressed: _signIn),
          const SizedBox(height: 10),
          // The one lime action on this sheet.
          BrandButton(
            label: 'Go unlimited with a plan',
            onPressed: watching ? null : _goUnlimited,
          ),
        ],
      ),
    );
  }
}
