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
// HONESTY: the Google/Apple buttons drive the REAL native flow. On failure
// (user cancels aside) a clear error is shown — never a fake success.

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
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../providers/account_provider.dart';

enum _LoginMode { password, magic }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  // Magic-link is the DEFAULT/PRIMARY path; password hides behind a reveal.
  _LoginMode _mode = _LoginMode.magic;
  bool _magicSent = false;
  // After the link is sent we lead with "tap the link" (the email's
  // orbguard://login link signs in automatically). The manual code entry is a
  // fallback revealed on demand — mirrors the OrbVPN "click the link" flow.
  bool _showCodeEntry = false;
  bool _obscurePassword = true;
  // Passkey button shows only when the device can run passkey ceremonies.
  bool _passkeyAvailable = false;

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Apple's guidelines: only offer "Sign in with Apple" on Apple platforms.
  /// The service also enforces [SignInWithApple.isAvailable] at attempt time.
  bool _showApple(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS;
  }

  void _dismiss([bool signedIn = false]) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(signedIn);
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
      totpCode:
          account.requiresTwoFactor ? _codeController.text.trim() : null,
    );
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Signed in')),
      );
      _dismiss(true);
    }
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
    final ok = await account.verifyMagicCode(
      _emailController.text,
      _codeController.text.trim(),
    );
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
      _showCodeEntry = false;
      _codeController.clear();
    });
    context.read<AccountProvider>().clearError();
  }

  @override
  Widget build(BuildContext context) {
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _socialButtons(context, account),
                    const SizedBox(height: 18),
                    _orDivider(context),
                    const SizedBox(height: 18),
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
              const SizedBox(height: 24),
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
          'Use your OrbVPN / OrbNet account. Signing in unlocks your '
          'subscription, credits and remote control.',
          textAlign: TextAlign.center,
          style: BrandText.body(color: context.colors.onSurfaceVariant, size: 14),
        ),
      ],
    );
  }

  /// Google + (on Apple platforms) Apple — glass buttons, never lime.
  Widget _socialButtons(BuildContext context, AccountProvider account) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        if (_showApple(context)) ...[
          const SizedBox(height: 12),
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
            'Check your email — we sent a sign-in link to '
            '${_emailController.text.trim()}.\n'
            'Open it on this device and tap the link to sign in.',
            style: BrandText.body(
                color: context.colors.onSurfaceVariant, size: 13),
          ),
          if (_showCodeEntry) ...[
            const SizedBox(height: 16),
            _fieldLabel(context, 'Sign-in code'),
            const SizedBox(height: 8),
            _field(
              context,
              controller: _codeController,
              hint: 'Paste the code from your email',
              icon: 'key',
              enabled: !account.isBusy,
            ),
          ] else ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: account.isBusy
                    ? null
                    : () => setState(() => _showCodeEntry = true),
                child: Text(
                  "Can't open the link? Enter the code instead",
                  style: BrandText.title(
                      color: context.colors.onSurfaceVariant, size: 13),
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 20),
        // The single lime action for this screen — the default sign-in path.
        // After sending: "Verify & sign in" once the code fallback is revealed,
        // otherwise "Resend link".
        BrandButton(
          label: !_magicSent
              ? 'Email me a sign-in link'
              : (_showCodeEntry ? 'Verify & sign in' : 'Resend link'),
          isLoading: account.isBusy,
          onPressed: account.isBusy
              ? null
              : (!_magicSent
                  ? _requestMagicCode
                  : (_showCodeEntry ? _verifyMagicCode : _requestMagicCode)),
        ),
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
          _fieldLabel(context, 'Authenticator code'),
          const SizedBox(height: 8),
          _field(
            context,
            controller: _codeController,
            hint: '6-digit code',
            icon: 'key',
            keyboardType: TextInputType.number,
            enabled: !account.isBusy,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
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
