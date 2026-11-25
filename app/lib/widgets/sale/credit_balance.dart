/// What the sale widgets share about the scan-credit balance: how it is
/// written, and fetching it once so a number is never shown before the
/// server has given one.
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/account_provider.dart';
import '../../providers/scan_credit_provider.dart';
import '../scan_credits/credits_sheet.dart';

/// "3 scan credits", "1 scan credit", "2.5 scan credits".
String scanCredits(double balance) =>
    '${formatCredits(balance)} ${balance == 1 ? 'scan credit' : 'scan credits'}';

/// Asks the server for the balance when it is not known yet: when this
/// first appears, and again for each new account signed in.
class FetchCreditBalance extends StatelessWidget {
  const FetchCreditBalance({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();
    return _Fetch(
      key: ValueKey<String?>(account.isLoggedIn ? account.email ?? '' : null),
      signedIn: account.isLoggedIn,
      child: child,
    );
  }
}

class _Fetch extends StatefulWidget {
  const _Fetch({super.key, required this.signedIn, required this.child});

  final bool signedIn;
  final Widget child;

  @override
  State<_Fetch> createState() => _FetchState();
}

class _FetchState extends State<_Fetch> {
  @override
  void initState() {
    super.initState();
    if (!widget.signedIn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ScanCreditProvider credits = context.read<ScanCreditProvider>();
      if (!credits.balanceKnown && !credits.loading) credits.refresh();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
