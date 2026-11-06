// lib/screens/account/two_factor_resume.dart
//
// Keeps a sign-in that waits for its second factor in front of the user.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/account_provider.dart';
import 'login_screen.dart';

/// Opens the sign-in screen whenever a sign-in is waiting for its second
/// factor ([AccountProvider.hasPendingTwoFactor]) and no sign-in screen is
/// there to take the code.
///
/// Two things leave a pending code step with nowhere to type the code:
///
///  * a magic link redeemed while no sign-in screen was open — it
///    cold-started the app, or the user closed the screen after asking for
///    the link;
///  * the app lock. While locked, `AppLockGate` shows its lock screen in
///    place of the root navigator, which disposes every route, the sign-in
///    screen in the middle of a code step included. With the lock on, that
///    happens each time the user switches to the authenticator app to read
///    the code.
///
/// Mount it around the root navigator, inside the app lock:
/// `AppLockGate(child: TwoFactorResume(navigatorKey: key, child: navigator))`.
/// The lock then rebuilds this widget along with the navigator on unlock,
/// and the check it runs on mount puts the code step back.
class TwoFactorResume extends StatefulWidget {
  const TwoFactorResume({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// The key of the navigator inside [child]. This widget sits above that
  /// navigator, so `Navigator.of(context)` cannot reach it.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  State<TwoFactorResume> createState() => _TwoFactorResumeState();
}

class _TwoFactorResumeState extends State<TwoFactorResume> {
  AccountProvider? _account;
  bool _checkQueued = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.read<AccountProvider>();
    if (identical(account, _account)) return;
    _account?.removeListener(_queueCheck);
    _account = account..addListener(_queueCheck);
    // The pending sign-in can be older than this widget: the navigator it
    // wraps has just been rebuilt by an unlock.
    _queueCheck();
  }

  @override
  void dispose() {
    _account?.removeListener(_queueCheck);
    super.dispose();
  }

  /// Runs the check once the current frame is built: the navigator is a
  /// descendant, so it is mounted only by then, and a sign-in screen pushed
  /// by an earlier check has mounted by the time the next one runs, so the
  /// screen is never pushed twice.
  void _queueCheck() {
    if (_checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _checkQueued = false;
        _openCodeStep();
      })
      ..ensureVisualUpdate();
  }

  void _openCodeStep() {
    final account = _account;
    final navigator = widget.navigatorKey.currentState;
    if (!mounted || account == null || navigator == null) return;
    if (!account.hasPendingTwoFactor || LoginScreen.isOpen) return;
    // Reopening a step whose token the server already refuses would only
    // collect a code that can never succeed.
    if (account.expireStaleTwoFactor()) return;
    unawaited(navigator
        .push(MaterialPageRoute<bool>(builder: (_) => const LoginScreen())));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
