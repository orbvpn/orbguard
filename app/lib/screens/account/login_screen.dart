// lib/screens/account/login_screen.dart
//
// Brand-kit sign-in screen for the shared OrbVPN/OrbNet account. Login is
// OPTIONAL this phase — it unlocks subscription / credits / remote control,
// while anonymous scanning keeps working.
//
// Sign-in order (top → bottom): Continue with Google / Apple → an "or" divider
// → email + a PRIMARY magic-link "Email me a sign-in code" button (the default
// path) → a subtle "Use password instead" reveal for email+password (with an
// optional TOTP step) → "Skip for now".
//
// Two-factor accounts: after any first factor the server may ask for the
// authenticator code. The password form takes it inline (re-posting the
// password); every other method switches the card to a code step that
// completes the pending sign-in. Both fields also take a recovery code.
//
// HONESTY: the Google/Apple buttons drive the REAL native flow. On failure
// (user cancels aside) a clear error is shown — never a fake success.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../legal/legal_screen.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../providers/account_provider.dart';
import '../../services/orbnet/magic_link_deep_link.dart';
import '../../utils/amazon_build.dart';
import '../../utils/host_platform.dart';

enum _LoginMode { password, magic }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.platform});

  /// The platform to draw for: it decides which sign-in buttons are offered.
  /// Null means the one the app runs on.
  final TargetPlatform? platform;

  /// Whether a sign-in screen is mounted. TwoFactorResume checks this before
  /// opening one for a code step, so a link tapped while the screen is
  /// already up finishes in it instead of stacking a second one.
  static bool get isOpen => _LoginScreenState._mountedCount > 0;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static int _mountedCount = 0;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  // The second-factor code, kept apart from _codeController: that one holds
  // the pasted magic LINK, which must not prefill the code step it leads to.
  final _twoFactorCodeController = TextEditingController();
  // The code field accepts both kinds of code either way; this only swaps in
  // a keyboard that can type a recovery code's letters and hyphen.
  bool _useRecoveryCode = false;
  bool _hadPendingTwoFactor = false;

  // Magic-link is the DEFAULT/PRIMARY path; password hides behind a reveal.
  _LoginMode _mode = _LoginMode.magic;
  bool _magicSent = false;
  bool _obscurePassword = true;
  // Passkey button shows only when the device can run passkey ceremonies.
  bool _passkeyAvailable = false;
  // Watched so an out-of-screen sign-in (magic-link deep link) closes the sheet.
  AccountProvider? _account;
  bool _wasLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _mountedCount++;
    // Pre-fill the last email that signed in on this device.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final account = context.read<AccountProvider>();
      final last = await account.lastLoggedInEmail();
      if (last != null && last.isNotEmpty && mounted && _emailController.text.isEmpty) {
        _emailController.text = last;
      }
      final canPasskey = await account.isPasskeyAvailable();
      if (mounted && canPasskey) setState(() => _passkeyAvailable = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.read<AccountProvider>();
    if (identical(account, _account)) return;
    _account?.removeListener(_onAccountChanged);
    _account = account;
    _wasLoggedIn = account.isLoggedIn;
    _hadPendingTwoFactor = account.hasPendingTwoFactor;
    account.addListener(_onAccountChanged);
  }

  /// The magic-link deep link is handled ABOVE this screen, so a link tapped
  /// while this sheet is open used to sign the user in behind it and leave
  /// them staring at the form they had already filled in — the "login within
  /// the product was not successful" the Microsoft reviewer reported. Close on
  /// the logged-out -> logged-in transition, reusing the same pop(true)
  /// contract the in-screen sign-in paths use.
  void _onAccountChanged() {
    final account = _account;
    if (account == null || !mounted) return;
    final isLoggedIn = account.isLoggedIn;
    final wasLoggedIn = _wasLoggedIn;
    _wasLoggedIn = isLoggedIn;
    // A code step that just opened — from this screen or from a deep link
    // handled above it — starts empty and on the authenticator keyboard.
    final hasPending = account.hasPendingTwoFactor;
    if (hasPending && !_hadPendingTwoFactor) {
      _twoFactorCodeController.clear();
      if (_useRecoveryCode) setState(() => _useRecoveryCode = false);
    }
    _hadPendingTwoFactor = hasPending;
    if (!wasLoggedIn && isLoggedIn) _dismiss(true);
  }

  /// Leaving the screen by hand — Skip for now, the back button, a back
  /// gesture — abandons a code step it was showing, so the pending token goes
  /// now instead of idling. Only a pop gets here: the app lock disposing the
  /// screen with the whole navigator does not, and the pending sign-in then
  /// survives for TwoFactorResume to bring back. A pop with true is the
  /// sign-in finishing, which has already settled the step.
  void _onPopInvoked(bool didPop, Object? result) {
    if (!didPop || result == true) return;
    _account?.cancelTwoFactor();
  }

  @override
  void dispose() {
    _mountedCount--;
    _account?.removeListener(_onAccountChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _twoFactorCodeController.dispose();
    super.dispose();
  }

  /// The platform the buttons are chosen for: the one the screen was given,
  /// else the one the app runs on. Not the theme's: that is how the app is
  /// styled, and a button depends on what this build can do.
  TargetPlatform? get _platform => widget.platform ?? hostPlatform();

  /// The Amazon build creates no accounts. Google and Apple sign-in create
  /// one for a new address, and the server cannot be told not to, so that
  /// build offers neither. The email link there signs in existing accounts
  /// only (AccountProvider.allowRegistration), and password and passkey
  /// sign-in never create one.
  bool get _amazon => isAmazonBuild(context);

  /// Apple's guidelines: only offer "Sign in with Apple" on Apple platforms.
  /// The service also enforces [SignInWithApple.isAvailable] at attempt time.
  bool get _showApple =>
      !_amazon &&
      (_platform == TargetPlatform.iOS || _platform == TargetPlatform.macOS);

  /// google_sign_in ships Android/iOS/macOS/web implementations only — it is
  /// absent from windows/flutter/generated_plugins.cmake and the Linux build.
  /// Rendering the button there gives a second sign-in method that can never
  /// succeed, on the very screen Microsoft cited for 10.1.2.10.
  bool get _showGoogle =>
      !_amazon &&
      (_platform == TargetPlatform.android ||
          _platform == TargetPlatform.iOS ||
          _platform == TargetPlatform.macOS);

  /// Closes this screen with [signedIn] as its result.
  ///
  /// It acts on this screen's own route, never on whatever is on top. A
  /// sign-in success reaches here twice — from the handler that awaited it
  /// and from [_onAccountChanged] — and the route stays mounted through its
  /// exit animation; once it is leaving it is no longer active, so the second
  /// call cannot close the screen underneath (the one that opened sign-in
  /// and awaits its result). And when another route sits above this one —
  /// the Terms page opened from here as a deep-linked sign-in lands — pop()
  /// would close that page and leave the sign-in screen up, so this route is
  /// removed from under it instead.
  void _dismiss([bool signedIn = false]) {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (!route.isCurrent) {
      navigator.removeRoute(route, signedIn);
    } else if (navigator.canPop()) {
      navigator.pop(signedIn);
    }
  }

  Future<void> _signInWithGoogle() async {
    final account = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    final ok = await account.loginWithGoogle();
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Signed in')));
      _dismiss(true);
    }
  }

  Future<void> _signInWithApple() async {
    final account = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    final ok = await account.loginWithApple();
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Signed in')));
      _dismiss(true);
    }
  }

  void _openLegal(LegalDoc doc) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LegalScreen(doc: doc)),
    );
  }

  Widget _legalAcceptance(BuildContext context) {
    final muted = BrandText.body(color: context.colors.onSurfaceVariant, size: 12);
    final link = BrandText.body(color: AppColors.accentInk, size: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text.rich(
        TextSpan(
          text: 'By continuing you agree to the OrbGuard ',
          style: muted,
          children: [
            TextSpan(
              text: 'Terms of Service',
              style: link,
              recognizer: TapGestureRecognizer()
                ..onTap = () => _openLegal(LegalDoc.terms),
            ),
            TextSpan(text: ' and ', style: muted),
            TextSpan(
              text: 'Privacy Policy',
              style: link,
              recognizer: TapGestureRecognizer()
                ..onTap = () => _openLegal(LegalDoc.privacy),
            ),
            TextSpan(text: '.', style: muted),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _signInWithPasskey() async {
    final account = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    // Pass the entered email to target the account; empty is fine (discoverable).
    final ok = await account.loginWithPasskey(_emailController.text.trim());
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Signed in')));
      _dismiss(true);
    }
  }

  Future<void> _signInWithPassword() async {
    final account = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    final ok = await account.login(
      _emailController.text,
      _passwordController.text,
      totpCode: account.requiresTwoFactor ? _twoFactorCodeController.text : null,
    );
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Signed in')),
      );
      _dismiss(true);
    }
  }

  /// The code step's lime action: complete the pending sign-in with whatever
  /// was typed — authenticator code or recovery code alike.
  Future<void> _completeTwoFactor() async {
    final account = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    final ok = await account.completeTwoFactor(_twoFactorCodeController.text);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('Signed in')));
      _dismiss(true);
    }
  }

  void _cancelTwoFactor() {
    _twoFactorCodeController.clear();
    setState(() => _useRecoveryCode = false);
    context.read<AccountProvider>().cancelTwoFactor();
  }

  Future<void> _requestMagicCode() async {
    final account = context.read<AccountProvider>();
    FocusScope.of(context).unfocus();
    final ok = await account.loginWithMagicLink(_emailController.text);
    if (!mounted) return;
    if (ok) setState(() => _magicSent = true);
  }

  Future<void> _verifyMagicCode() async {
    final account = context.read<AccountProvider>();
    final messenger = ScaffoldMessenger.of(context);
    FocusScope.of(context).unfocus();
    // The field is shown as soon as the link is sent, so it can be empty when
    // this fires. Say so instead of round-tripping a blank token and surfacing
    // whatever generic error the backend returns.
    // The email renders the token only as a button, never as readable text, so
    // what the user can realistically copy is the LINK — accept either form.
    final code = magicCodeFromPastedText(_codeController.text);
    if (code == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Paste the sign-in link from your email first'),
      ));
      return;
    }
    final ok = await account.verifyMagicCode(_emailController.text, code);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Signed in')),
      );
      _dismiss(true);
    }
  }

  void _switchMode(_LoginMode mode) {
    setState(() {
      _mode = mode;
      _magicSent = false;
      _codeController.clear();
      _twoFactorCodeController.clear();
      _useRecoveryCode = false;
    });
    context.read<AccountProvider>().clearError();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      onPopInvokedWithResult: _onPopInvoked,
      child: _page(context),
    );
  }

  Widget _page(BuildContext context) {
    return GlassPage(
      title: 'Account',
      body: Consumer<AccountProvider>(
        builder: (context, account, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _header(context),
              const SizedBox(height: 24),
              GlassCard(
                padding: const EdgeInsets.all(20),
                // A pending code step replaces the whole card: the first
                // factor is done and the code is the one thing left to do,
                // so it gets the screen's single lime action to itself.
                child: account.hasPendingTwoFactor
                    ? _twoFactorPanel(context, account)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // On Windows/Linux none of the social providers have
                          // an implementation, so the whole block (and its
                          // "or" divider) collapses rather than rendering dead
                          // controls.
                          if (_hasSocialButtons(context)) ...[
                            _socialButtons(context, account),
                            const SizedBox(height: 18),
                            _orDivider(context),
                            const SizedBox(height: 18),
                          ],
                          _mode == _LoginMode.password
                              ? _passwordForm(context, account)
                              : _magicForm(context, account),
                        ],
                      ),
              ),
              if (account.lastError != null) ...[
                const SizedBox(height: 16),
                _errorBanner(context, account.lastError!),
              ],
              const SizedBox(height: 20),
              // Terms/Privacy acceptance — signing in constitutes agreement.
              _legalAcceptance(context),
              const SizedBox(height: 12),
              // Secondary, non-lime action — dismiss without signing in.
              Center(
                child: TextButton(
                  onPressed: account.isBusy ? null : () => _dismiss(false),
                  child: Text(
                    'Skip for now',
                    style: BrandText.title(
                      color: context.colors.onSurfaceVariant,
                      size: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'You can keep scanning without an account.',
                  textAlign: TextAlign.center,
                  style: BrandText.body(
                    color: context.colors.onSurfaceVariant,
                    size: 12.5,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---- Sections ------------------------------------------------------------

  Widget _header(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.accentPill,
            borderRadius: BorderRadius.circular(GlassTheme.radiusLarge),
          ),
          child: Center(
            child: DuotoneIcon('shield_keyhole', color: AppColors.accentInk, size: 30),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Sign in with your OrbVPN account',
          textAlign: TextAlign.center,
          style: BrandText.h2(color: context.colors.onSurface, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          _amazon
              ? 'Use the OrbVPN account you already have. Signing in brings '
                  'your plan and remote control to this device.'
              : 'Use your OrbVPN / OrbNet account. Signing in unlocks your '
                  'subscription, credits and remote control.',
          textAlign: TextAlign.center,
          style: BrandText.body(color: context.colors.onSurfaceVariant, size: 14),
        ),
      ],
    );
  }

  /// True when at least one social/passkey button can actually run here.
  bool _hasSocialButtons(BuildContext context) =>
      _showGoogle || _showApple || _passkeyAvailable;

  /// Google + (on Apple platforms) Apple — glass buttons, never lime.
  Widget _socialButtons(BuildContext context, AccountProvider account) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showGoogle)
          _socialButton(
            context,
            key: const ValueKey('google_signin_button'),
            mark: SvgPicture.asset(
              'assets/branding/google_g.svg', // vendor identity
              width: 20,
              height: 20,
            ),
            label: 'Continue with Google',
            onPressed: account.isBusy ? null : _signInWithGoogle,
          ),
        if (_showApple) ...[
          if (_showGoogle) const SizedBox(height: 12),
          _socialButton(
            context,
            key: const ValueKey('apple_signin_button'),
            mark: Icon(
              Icons.apple, // vendor identity
              size: 24,
              color: context.colors.onSurface,
            ),
            label: 'Continue with Apple',
            onPressed: account.isBusy ? null : _signInWithApple,
          ),
        ],
        if (_passkeyAvailable) ...[
          const SizedBox(height: 12),
          _socialButton(
            context,
            key: const ValueKey('passkey_signin_button'),
            mark: Icon(
              Icons.fingerprint,
              size: 24,
              color: context.colors.onSurface,
            ),
            label: 'Sign in with a passkey',
            onPressed: account.isBusy ? null : _signInWithPasskey,
          ),
        ],
      ],
    );
  }

  Widget _socialButton(
    BuildContext context, {
    required Key key,
    required Widget mark,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final disabled = onPressed == null;
    return Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: GestureDetector(
          key: key,
          onTap: onPressed,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Brand.rMd),
            child: BackdropFilter(
              filter: Brand.blurSm,
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Brand.glassFill,
                  borderRadius: BorderRadius.circular(Brand.rMd),
                  border: Border.all(color: Brand.glassBorder, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 24, height: 24, child: Center(child: mark)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.title(
                          color: context.colors.onSurface,
                          size: 15.5,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _orDivider(BuildContext context) {
    final line = Expanded(
      child: Divider(
        color: context.colors.onSurfaceVariant.withValues(alpha: 0.25),
        height: 1,
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: BrandText.label(
                color: context.colors.onSurfaceVariant, size: 12),
          ),
        ),
        line,
      ],
    );
  }

  Widget _magicForm(BuildContext context, AccountProvider account) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(context, 'Email'),
        const SizedBox(height: 8),
        _field(
          context,
          fieldKey: const ValueKey('magic_email_field'),
          controller: _emailController,
          hint: 'you@example.com',
          icon: 'letter',
          keyboardType: TextInputType.emailAddress,
          enabled: !account.isBusy && !_magicSent,
        ),
        if (_magicSent) ...[
          const SizedBox(height: 16),
          Text(
            // The Amazon build asks for a link that only an existing
            // account receives, so it does not promise one arrived.
            _amazon
                ? 'Check your email. If ${_emailController.text.trim()} has '
                    'an account, we sent it a sign-in link.\n'
                    'Tap the link on this device, or copy that link and '
                    'paste it below.'
                : 'Check your email. We sent a sign-in link to '
                    '${_emailController.text.trim()}.\n'
                    'Tap the link on this device, or copy that link and '
                    'paste it below.',
            style: BrandText.body(
                color: context.colors.onSurfaceVariant, size: 13),
          ),
          // Always visible, never behind a reveal. The deep link cannot work
          // when the mail is read on another device (or on a platform without
          // an orbguard:// handler), so the code entry is the guaranteed path
          // to a session — hiding it is what made sign-in look broken to the
          // Microsoft Store reviewer (10.1.2.10).
          const SizedBox(height: 16),
          _fieldLabel(context, 'Sign-in link'),
          const SizedBox(height: 8),
          _field(
            context,
            fieldKey: const ValueKey('magic_code_field'),
            controller: _codeController,
            hint: 'Paste the sign-in link from your email',
            icon: 'key',
            enabled: !account.isBusy,
          ),
        ],
        const SizedBox(height: 20),
        // The single lime action for this screen — send the link, then verify
        // whatever code the user pasted.
        BrandButton(
          label: !_magicSent ? 'Email me a sign-in link' : 'Verify & sign in',
          isLoading: account.isBusy,
          onPressed: account.isBusy
              ? null
              : (!_magicSent ? _requestMagicCode : _verifyMagicCode),
        ),
        if (_magicSent) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: account.isBusy ? null : _requestMagicCode,
            child: Text(
              'Resend link',
              style: BrandText.title(
                  color: context.colors.onSurfaceVariant, size: 14),
            ),
          ),
        ],
        const SizedBox(height: 10),
        // Subtle, non-lime reveal for the secondary password path.
        TextButton(
          onPressed:
              account.isBusy ? null : () => _switchMode(_LoginMode.password),
          child: Text(
            'Use password instead',
            style: BrandText.title(
                color: context.colors.onSurfaceVariant, size: 14),
          ),
        ),
      ],
    );
  }

  Widget _passwordForm(BuildContext context, AccountProvider account) {
    final needs2fa = account.requiresTwoFactor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(context, 'Email'),
        const SizedBox(height: 8),
        _field(
          context,
          fieldKey: const ValueKey('pw_email_field'),
          controller: _emailController,
          hint: 'you@example.com',
          icon: 'letter',
          keyboardType: TextInputType.emailAddress,
          enabled: !account.isBusy,
        ),
        const SizedBox(height: 16),
        _fieldLabel(context, 'Password'),
        const SizedBox(height: 8),
        _field(
          context,
          fieldKey: const ValueKey('pw_password_field'),
          controller: _passwordController,
          hint: 'Your password',
          icon: 'lock_password',
          obscure: _obscurePassword,
          enabled: !account.isBusy,
          suffix: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: DuotoneIcon(
              _obscurePassword ? 'eye_closed' : 'eye',
              color: context.colors.onSurfaceVariant,
              size: 20,
            ),
          ),
        ),
        if (needs2fa) ...[
          const SizedBox(height: 16),
          _fieldLabel(context,
              _useRecoveryCode ? 'Recovery code' : 'Authenticator code'),
          const SizedBox(height: 8),
          _twoFactorCodeField(context, account),
          _recoveryCodeToggle(context, account),
        ],
        const SizedBox(height: 20),
        // In password mode this is the single lime action.
        BrandButton(
          label: needs2fa ? 'Verify & sign in' : 'Sign in',
          isLoading: account.isBusy,
          onPressed: account.isBusy ? null : _signInWithPassword,
        ),
        const SizedBox(height: 10),
        // Back to the default magic-link path.
        TextButton(
          onPressed:
              account.isBusy ? null : () => _switchMode(_LoginMode.magic),
          child: Text(
            'Email me a code instead',
            style: BrandText.title(
                color: context.colors.onSurfaceVariant, size: 14),
          ),
        ),
      ],
    );
  }

  /// The code step for a sign-in that began with a magic link, Google, Apple
  /// or a passkey and now waits for the account's second factor.
  Widget _twoFactorPanel(BuildContext context, AccountProvider account) {
    final email = account.twoFactorEmail;
    return Column(
      key: const ValueKey('two_factor_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Two-factor authentication',
          style: BrandText.heading(color: context.colors.onSurface, size: 19),
        ),
        const SizedBox(height: 8),
        Text(
          email == null
              ? 'Enter the 6-digit code from your authenticator app to finish '
                  'signing in.'
              : 'Enter the 6-digit code from your authenticator app to finish '
                  'signing in as $email.',
          style:
              BrandText.body(color: context.colors.onSurfaceVariant, size: 13),
        ),
        const SizedBox(height: 16),
        _fieldLabel(
            context, _useRecoveryCode ? 'Recovery code' : 'Authenticator code'),
        const SizedBox(height: 8),
        _twoFactorCodeField(context, account),
        if (account.twoFactorAcceptsRecoveryCode)
          _recoveryCodeToggle(context, account),
        const SizedBox(height: 12),
        BrandButton(
          label: 'Verify & sign in',
          isLoading: account.isBusy,
          onPressed: account.isBusy ? null : _completeTwoFactor,
        ),
        const SizedBox(height: 10),
        TextButton(
          key: const ValueKey('two_factor_start_over'),
          onPressed: account.isBusy ? null : _cancelTwoFactor,
          child: Text(
            'Start over',
            style: BrandText.title(
                color: context.colors.onSurfaceVariant, size: 14),
          ),
        ),
      ],
    );
  }

  /// The second-factor code field, shared by the password form and the code
  /// step. The server tells a 6-digit TOTP code from a recovery code
  /// (xxxx-xxxxxx, hex) by its shape, so the field must let both through:
  /// filtering to digits would silently strip a recovery code to nothing.
  Widget _twoFactorCodeField(BuildContext context, AccountProvider account) {
    return _field(
      context,
      fieldKey: const ValueKey('two_factor_code_field'),
      controller: _twoFactorCodeController,
      hint: _useRecoveryCode ? 'xxxx-xxxxxx' : '6-digit code',
      icon: 'key',
      keyboardType: _useRecoveryCode
          ? TextInputType.visiblePassword
          : TextInputType.number,
      enabled: !account.isBusy,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\- ]')),
        LengthLimitingTextInputFormatter(64),
      ],
    );
  }

  /// Swaps the keyboard between the number pad (authenticator codes) and one
  /// that can type a recovery code. A number pad has no letters, so without
  /// this a user holding only a recovery code could not type it on a phone.
  Widget _recoveryCodeToggle(BuildContext context, AccountProvider account) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: const ValueKey('two_factor_recovery_toggle'),
        onPressed: account.isBusy
            ? null
            : () => setState(() => _useRecoveryCode = !_useRecoveryCode),
        child: Text(
          _useRecoveryCode
              ? 'Use your authenticator code'
              : 'Use a recovery code',
          style:
              BrandText.title(color: context.colors.onSurfaceVariant, size: 13),
        ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorInk.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DuotoneIcon('danger_triangle', color: AppColors.errorInk, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: BrandText.body(color: AppColors.errorInk, size: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Field helpers -------------------------------------------------------

  Widget _fieldLabel(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: BrandText.label(color: context.colors.onSurfaceVariant, size: 12),
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    required String icon,
    Key? fieldKey,
    TextInputType? keyboardType,
    bool obscure = false,
    bool enabled = true,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final cs = context.colors;
    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => context.read<AccountProvider>().clearError(),
      style: BrandText.title(color: cs.onSurface, size: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: BrandText.body(color: cs.onSurfaceVariant, size: 15),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: DuotoneIcon(icon, color: cs.onSurfaceVariant, size: 20),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffix,
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
