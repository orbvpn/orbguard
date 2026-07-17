// lib/screens/account/login_screen.dart
//
// Brand-kit sign-in screen for the shared OrbVPN/OrbNet account. Login is
// OPTIONAL this phase — it unlocks subscription / credits / remote control,
// while anonymous scanning keeps working. Supports email+password (with an
// optional TOTP step) and a magic-link "email me a code" path. OAuth / passkey
// are deferred to a later phase and are not shown here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  _LoginMode _mode = _LoginMode.password;
  bool _magicSent = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill the last email that signed in on this device.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final last = await context.read<AccountProvider>().lastLoggedInEmail();
      if (last != null && last.isNotEmpty && mounted && _emailController.text.isEmpty) {
        _emailController.text = last;
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _dismiss([bool signedIn = false]) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(signedIn);
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
                child: _mode == _LoginMode.password
                    ? _passwordForm(context, account)
                    : _magicForm(context, account),
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
          'Use the same email and password as OrbVPN / OrbNet. '
          'Signing in unlocks your subscription, credits and remote control.',
          textAlign: TextAlign.center,
          style: BrandText.body(color: context.colors.onSurfaceVariant, size: 14),
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
        // The single lime action for this screen.
        BrandButton(
          label: needs2fa ? 'Verify & sign in' : 'Sign in',
          isLoading: account.isBusy,
          onPressed: account.isBusy ? null : _signInWithPassword,
        ),
        const SizedBox(height: 10),
        BrandButton.secondary(
          label: 'Email me a code instead',
          onPressed:
              account.isBusy ? null : () => _switchMode(_LoginMode.magic),
        ),
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
          controller: _emailController,
          hint: 'you@example.com',
          icon: 'letter',
          keyboardType: TextInputType.emailAddress,
          enabled: !account.isBusy && !_magicSent,
        ),
        if (_magicSent) ...[
          const SizedBox(height: 16),
          Text(
            'We emailed a sign-in code to ${_emailController.text.trim()}. '
            'Enter it below.',
            style: BrandText.body(
                color: context.colors.onSurfaceVariant, size: 13),
          ),
          const SizedBox(height: 12),
          _fieldLabel(context, 'Sign-in code'),
          const SizedBox(height: 8),
          _field(
            context,
            controller: _codeController,
            hint: 'Paste the code from your email',
            icon: 'key',
            enabled: !account.isBusy,
          ),
        ],
        const SizedBox(height: 20),
        BrandButton(
          label: _magicSent ? 'Verify & sign in' : 'Email me a code',
          isLoading: account.isBusy,
          onPressed: account.isBusy
              ? null
              : (_magicSent ? _verifyMagicCode : _requestMagicCode),
        ),
        const SizedBox(height: 10),
        BrandButton.secondary(
          label: 'Use password instead',
          onPressed:
              account.isBusy ? null : () => _switchMode(_LoginMode.password),
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
    TextInputType? keyboardType,
    bool obscure = false,
    bool enabled = true,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final cs = context.colors;
    return TextField(
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
