/// What a computer shows when a check needs more than the free tier gives.
///
/// A phone has the credits sheet: watch an ad or take a plan. A computer has
/// no ads, so past the free check it means OrbGuard Premium, and how the
/// sheet says that depends on the device it is drawn for:
///
///   * A Mac sells the plans in the app, so the one lime action opens them.
///   * Windows and Linux sell nothing. The sheet says the check needs
///     OrbGuard Premium, offers sign-in to someone who already has it, and
///     gives the site as a plain address. No plan, price or store is shown
///     or named there.
///   * The Amazon build, on any device, is Windows and Linux without the
///     site: it says the check needs OrbGuard Premium and offers sign-in.
///
/// HONEST STATES: it only closes with "go on" once the account really has
/// Premium, or really has a credit to spend. Asking the account again shows
/// what the server answered, and says so when it could not be reached.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/pressable.dart';
import '../../providers/account_provider.dart';
import '../../providers/scan_credit_provider.dart';
import '../../utils/amazon_build.dart';
import '../sale/login_sheet.dart';
import '../sale/plans_sheet.dart';

/// Opens an address outside the app. True when it opened.
typedef LinkOpener = Future<bool> Function(Uri address);

/// Presents the sheet for [platform]. Completes with true when the check can
/// be tried again: the account now has Premium, or a credit to spend.
Future<bool?> showPremiumSheet(
  BuildContext context, {
  required TargetPlatform? platform,
}) =>
    showAppSheet<bool>(context, child: PremiumSheet(platform: platform));

class PremiumSheet extends StatefulWidget {
  const PremiumSheet({super.key, required this.platform, this.openLink});

  /// The device the sheet is drawn for. Null is a browser.
  final TargetPlatform? platform;

  /// Stands in for the system's browser, for tests.
  final LinkOpener? openLink;

  /// The site, as the sheet shows it and as it opens.
  static const String siteLabel = 'guard.orbai.world';
  static final Uri site = Uri.parse('https://guard.orbai.world');

  @override
  State<PremiumSheet> createState() => _PremiumSheetState();
}

class _PremiumSheetState extends State<PremiumSheet> {
  AccountProvider? _account;
  bool _busy = false;
  bool _closed = false;

  /// One plain line under the words, when there is something to say, and
  /// whether it reports something that went wrong.
  String? _note;
  bool _noteIsError = false;

  /// Only the Mac build has a store to sell the plans through.
  bool get _sellsPlans =>
      widget.platform == TargetPlatform.macOS && !isAmazonBuild(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AccountProvider account = context.read<AccountProvider>();
    if (!identical(account, _account)) {
      _account?.removeListener(_onAccount);
      _account = account..addListener(_onAccount);
    }
  }

  @override
  void dispose() {
    _account?.removeListener(_onAccount);
    super.dispose();
  }

  /// The account changed while this sheet was the one on top: a sign-in
  /// finished from a link, or a plan landed.
  void _onAccount() {
    if (!mounted || _busy) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (_account?.hasPremium ?? false) _close();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(true);
  }

  /// Closes with "go on" when the account can now pay for the check.
  Future<void> _goOnIfPaid() async {
    final AccountProvider account = context.read<AccountProvider>();
    if (account.hasPremium) return _close();
    if (!account.isLoggedIn) return;
    // A free account may hold credits earned on a phone.
    final ScanCreditProvider credits = context.read<ScanCreditProvider>();
    await credits.refresh();
    if (!mounted) return;
    if (credits.balanceKnown && credits.balance >= 1) _close();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      await action();
    } finally {
      if (mounted && !_closed) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        final bool? signedIn = await showLoginSheet(context);
        if (signedIn == true && mounted) await _goOnIfPaid();
      });

  Future<void> _seePlans() => _run(() async {
        await showPlansSheet(context);
        if (mounted) await _goOnIfPaid();
      });

  /// Asks the server for the account's plan again: one bought on another
  /// device, or on the web, shows up here.
  Future<void> _refresh() => _run(() async {
        final AccountProvider account = context.read<AccountProvider>();
        final bool asked = await account.refreshEntitlement();
        if (!mounted) return;
        if (account.hasPremium) return _close();
        setState(() {
          _noteIsError = !asked;
          _note = asked
              ? 'Still no Premium on this account.'
              : 'Could not refresh your account. Try again in a moment.';
        });
      });

  Future<void> _openSite() async {
    final LinkOpener open = widget.openLink ??
        (Uri address) =>
            launchUrl(address, mode: LaunchMode.externalApplication);
    bool opened = false;
    try {
      opened = await open(PremiumSheet.site);
    } on Object {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() {
        _noteIsError = true;
        _note = 'Could not open ${PremiumSheet.siteLabel}.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool signedIn = context.watch<AccountProvider>().isLoggedIn;
    final String? note = _note;

    final Widget signIn = signedIn
        ? _button('Refresh my account', _refresh, lime: !_sellsPlans)
        : _button('Sign in', _signIn, lime: !_sellsPlans);

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
                  DuotoneIcon(AppIcons.crown, size: 26, color: Brand.limeInk),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text('This needs OrbGuard Premium',
                textAlign: TextAlign.center,
                style: BrandText.h2(color: cs.onSurface, size: 23)),
          ),
          const SizedBox(height: 10),
          Text('The first check is free. More checks need OrbGuard Premium.',
              textAlign: TextAlign.center,
              style: BrandText.body(size: 15, color: Brand.text2)
                  .copyWith(height: Brand.bodyHeight(1.45))),
          const SizedBox(height: 8),
          Text(
              signedIn
                  ? 'This account has no Premium yet.'
                  : 'Already have Premium? Sign in and it works here too.',
              textAlign: TextAlign.center,
              style: BrandText.body(size: 14, color: Brand.text2)
                  .copyWith(height: Brand.bodyHeight(1.45))),
          if (note != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(note,
                  textAlign: TextAlign.center,
                  style: BrandText.body(
                          size: 14,
                          color:
                              _noteIsError ? AppColors.errorInk : cs.onSurface)
                      .copyWith(height: Brand.bodyHeight(1.45))),
            ),
          ],
          const SizedBox(height: 22),
          if (_sellsPlans) ...[
            // The one lime action on this sheet.
            BrandButton(
                label: 'See plans', onPressed: _busy ? null : _seePlans),
            const SizedBox(height: 10),
            signIn,
          ] else ...[
            signIn,
            // The Amazon build names no site to pay at.
            if (!isAmazonBuild(context)) ...[
              const SizedBox(height: 6),
              Center(child: _SiteLink(onTap: _openSite)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onPressed, {required bool lime}) {
    final VoidCallback? action = _busy ? null : onPressed;
    return lime
        ? BrandButton(label: label, onPressed: action)
        : BrandButton.secondary(label: label, onPressed: action);
  }
}

/// The site's address as a plain link. It says where it goes and nothing
/// about what is there.
class _SiteLink extends StatelessWidget {
  const _SiteLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Open ${PremiumSheet.siteLabel} in your browser',
      radius: BorderRadius.circular(Brand.rSm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            widthFactor: 1,
            child: Text(
              PremiumSheet.siteLabel,
              style: BrandText.title(
                      size: 14.5, weight: FontWeight.w500, color: Brand.text2)
                  .copyWith(
                decoration: TextDecoration.underline,
                decorationColor: Brand.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
