// lib/screens/account/security_screen.dart
//
// Account security: passkey management (list / add / rename / delete) and the
// danger zone (permanent account deletion — required by App Store review for
// any app with account creation).
//
// Ported from OrbVPN's profile security section, restyled to OrbGuard's kit:
// every modal presents as an iOS sheet (showAppSheet), glass cards on the
// GlassPage bed, one lime action per screen ("Add a passkey").

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/account_provider.dart';
import '../../services/orbnet/models/passkey_info.dart';
import '../../services/orbnet/orbnet_api_client.dart'
    show AuthenticationException, NetworkException, ServerException;

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  List<PasskeyInfo>? _passkeys; // null = loading
  String? _loadError;
  bool _passkeySupported = false;
  bool _working = false;

  /// Monotonic refresh sequence: only the LATEST in-flight refresh may write
  /// state, so a slow stale response can't resurrect a just-deleted passkey.
  int _refreshSeq = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final seq = ++_refreshSeq;
    final account = context.read<AccountProvider>();
    final supported = await account.isPasskeyAvailable();
    List<PasskeyInfo>? keys;
    String? error;
    try {
      keys = await account.listPasskeys();
      // Newest first — the top row is the one most recently created, which for
      // platform authenticators is the only one guaranteed to still work.
      keys.sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
    } on AuthenticationException {
      // Session expired / token invalid — tell the user to sign in again
      // rather than a generic "could not load".
      error = 'Your session expired. Please sign in again to manage passkeys.';
    } on NetworkException {
      error = "Couldn't reach OrbNet. Check your connection and try again.";
    } on ServerException {
      error = 'OrbNet couldn’t load your passkeys right now. Please try again.';
    } catch (e) {
      error = 'Could not load your passkeys.';
    }
    if (!mounted || seq != _refreshSeq) return;
    setState(() {
      _passkeySupported = supported;
      _passkeys = keys ?? _passkeys ?? const [];
      _loadError = error;
    });
  }

  // ---- Passkey actions -----------------------------------------------------

  Future<void> _addPasskey() async {
    final account = context.read<AccountProvider>();
    final name = await _promptForName(
      title: 'Add a passkey',
      hint: 'e.g. iPhone Face ID',
      initial: '',
      confirmLabel: 'Create passkey',
      explainer:
          'Your device will ask for Face ID, fingerprint, or your device PIN. '
          'The passkey only works for your account on orbai.world.',
    );
    if (name == null || !mounted) return;

    setState(() => _working = true);
    final ok = await account.registerPasskey(
        name: name.isEmpty ? 'OrbGuard passkey' : name);
    if (!mounted) return;
    setState(() => _working = false);
    _snack(ok
        ? 'Passkey added.'
        : (account.lastError ?? 'Could not add the passkey.'));
    await _refresh();
  }

  Future<void> _rename(PasskeyInfo key) async {
    final account = context.read<AccountProvider>();
    final name = await _promptForName(
      title: 'Rename passkey',
      hint: 'Passkey name',
      initial: key.name,
      confirmLabel: 'Save',
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _working = true);
    String message;
    try {
      await account.renamePasskey(key.id, name);
      message = 'Passkey renamed.';
    } catch (e) {
      message = 'Could not rename the passkey.';
    }
    if (!mounted) return;
    _snack(message);
    setState(() => _working = false);
    await _refresh();
  }

  Future<void> _delete(PasskeyInfo key) async {
    final account = context.read<AccountProvider>();
    final keys = _passkeys ?? const <PasskeyInfo>[];
    final isLast = keys.length <= 1;
    // The list is sorted newest-first; with duplicates, the newest is the only
    // one the platform authenticator can still use.
    final isNewestOfMany = keys.length > 1 && keys.first.id == key.id;
    final confirmed = await _confirmSheet(
      title: 'Delete passkey',
      body: 'This removes "${key.name}" from your account — it can no longer '
          'be used to sign in.'
          '${isLast ? '\n\nThis is your LAST passkey; after deleting it you can '
              'still sign in by email link or password.' : ''}'
          '${isNewestOfMany ? '\n\nThis is your MOST RECENT passkey. If the '
              'others are older duplicates from this same device, this is the '
              'one that still works — consider deleting the older ones '
              'instead.' : ''}'
          '\n\nYou may also want to remove it from your device\'s password '
          'manager (iCloud Keychain / Google Password Manager).',
      confirmLabel: 'Delete passkey',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    String message;
    try {
      await account.deletePasskey(key.id);
      message = 'Passkey deleted.';
    } catch (e) {
      message = 'Could not delete the passkey.';
    }
    if (!mounted) return;
    _snack(message);
    setState(() => _working = false);
    await _refresh();
  }

  // ---- Delete account ------------------------------------------------------

  Future<void> _deleteAccount() async {
    final account = context.read<AccountProvider>();
    final navigator = Navigator.of(context);

    // Strong confirmation: the backend hard-deletes everything immediately with
    // no grace period, so require typing DELETE.
    final typed = await _promptForName(
      title: 'Delete account?',
      hint: 'Type DELETE to confirm',
      initial: '',
      confirmLabel: 'Delete forever',
      destructive: true,
      explainer:
          'This permanently deletes your account and ALL its data — scan '
          'history, devices, credits, and passkeys — for BOTH OrbGuard and '
          'OrbVPN (they share this account). This cannot be undone.\n\n'
          'An active subscription is NOT cancelled by deleting your account: '
          'manage it in your App Store / Google Play subscription settings, '
          'or it will keep renewing.\n\n'
          'Type DELETE below to confirm.',
    );
    if (typed == null || !mounted) return;
    if (typed.trim().toUpperCase() != 'DELETE') {
      _snack('Account not deleted — confirmation text did not match.');
      return;
    }

    setState(() => _working = true);
    final ok = await account.deleteAccount();
    if (!mounted) return;
    setState(() => _working = false);
    if (ok) {
      _snack('Your account has been permanently deleted.');
      navigator.popUntil((route) => route.isFirst);
    } else {
      _snack(account.lastError ?? 'Could not delete the account.');
    }
  }

  // ---- Sheet helpers -------------------------------------------------------

  /// A single-field input sheet. Returns the trimmed text, or null on cancel.
  Future<String?> _promptForName({
    required String title,
    required String hint,
    required String initial,
    required String confirmLabel,
    String? explainer,
    bool destructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: initial);
    return showAppSheet<String>(
      context,
      child: Builder(
        builder: (sheetContext) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: EdgeInsets.fromLTRB(
              22, 20, 22, 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BrandText.h2(color: cs.onSurface, size: 21)),
              if (explainer != null) ...[
                const SizedBox(height: 12),
                Text(explainer,
                    style:
                        BrandText.body(color: cs.onSurfaceVariant, size: 14)),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: destructive
                    ? TextCapitalization.characters
                    : TextCapitalization.sentences,
                decoration: InputDecoration(hintText: hint),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: destructive
                        ? BrandButton.destructive(
                            label: confirmLabel,
                            onPressed: () => Navigator.of(sheetContext)
                                .pop(controller.text.trim()),
                          )
                        : BrandButton(
                            label: confirmLabel,
                            onPressed: () => Navigator.of(sheetContext)
                                .pop(controller.text.trim()),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A destructive confirm sheet. Returns true when confirmed.
  Future<bool?> _confirmSheet({
    required String title,
    required String body,
    required String confirmLabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    return showAppSheet<bool>(
      context,
      child: Builder(
        builder: (sheetContext) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: BrandText.h2(color: cs.onSurface, size: 21)),
              const SizedBox(height: 14),
              Text(body,
                  style: BrandText.body(color: cs.onSurfaceVariant, size: 14)),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BrandButton.destructive(
                      label: confirmLabel,
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keys = _passkeys;

    return GlassPage(
      title: 'Account security',
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('Passkeys',
                style: BrandText.h2(color: cs.onSurface, size: 20)),
            const SizedBox(height: 4),
            Text(
              'Sign in with Face ID, fingerprint, or your device PIN — no '
              'password to phish or leak.',
              style: BrandText.body(color: cs.onSurfaceVariant, size: 13.5),
            ),
            const SizedBox(height: 14),
            if (_loadError != null)
              GlassCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_loadError!,
                        style: BrandText.body(
                            color: AppColors.errorInk, size: 13.5)),
                    const SizedBox(height: 12),
                    // Explicit retry — pull-to-refresh is unreachable with a
                    // mouse on desktop.
                    BrandButton.secondary(
                        label: 'Try again', onPressed: _refresh),
                  ],
                ),
              )
            else if (keys == null)
              const GlassCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.all(24),
                child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (keys.isEmpty)
              GlassCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    DuotoneIcon('shield_keyhole',
                        size: 22, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No passkeys yet. Add one to sign in without a '
                        'password.',
                        style: BrandText.body(
                            color: cs.onSurfaceVariant, size: 13.5),
                      ),
                    ),
                  ],
                ),
              )
            else
              GlassCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < keys.length; i++) ...[
                      if (i > 0)
                        Divider(
                            height: 1,
                            indent: 56,
                            color: cs.onSurface.withAlpha(16)),
                      _PasskeyRow(
                        info: keys[i],
                        // Platform authenticators keep ONE passkey per account
                        // and overwrite on re-registration, so when duplicates
                        // exist only the newest-created row still signs in —
                        // badge it so cleanup keeps the right one.
                        isNewest: i == 0 && keys.length > 1,
                        enabled: !_working,
                        onRename: () => _rename(keys[i]),
                        onDelete: () => _delete(keys[i]),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 14),
            // The single lime action on this screen.
            BrandButton(
              label: 'Add a passkey',
              isLoading: _working,
              onPressed:
                  (_passkeySupported && !_working) ? _addPasskey : null,
            ),
            if (!_passkeySupported) ...[
              const SizedBox(height: 8),
              Text(
                'This device does not support passkeys.',
                style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5),
              ),
            ],
            const SizedBox(height: 32),
            Text('Danger zone',
                style: BrandText.h2(color: AppColors.errorInk, size: 20)),
            const SizedBox(height: 14),
            GlassCard(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: DuotoneIcon('trash_bin_trash',
                    size: 24, color: AppColors.errorInk),
                title: Text('Delete account',
                    style: BrandText.title(
                        color: AppColors.errorInk, size: 15)),
                subtitle: Text(
                  'Permanently delete your account and all its data',
                  style:
                      BrandText.body(color: cs.onSurfaceVariant, size: 12.5),
                ),
                onTap: _working ? null : _deleteAccount,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One passkey row: platform icon, name, added/last-used dates, and a menu
/// with Rename / Delete.
class _PasskeyRow extends StatelessWidget {
  final PasskeyInfo info;
  final bool enabled;

  /// Badge the newest-created passkey when duplicates exist — with platform
  /// authenticators it is the only one guaranteed to still sign in.
  final bool isNewest;

  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _PasskeyRow({
    required this.info,
    required this.enabled,
    required this.onRename,
    required this.onDelete,
    this.isNewest = false,
  });

  String _dates() {
    final fmt = DateFormat.yMMMd();
    final added =
        info.createdAt != null ? 'Added ${fmt.format(info.createdAt!)}' : null;
    final used = info.lastUsedAt != null
        ? 'last used ${fmt.format(info.lastUsedAt!)}'
        : 'never used';
    return [if (added != null) added, used].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading:
          DuotoneIcon('key_minimalistic', size: 24, color: AppColors.accentInk),
      title: Row(
        children: [
          Flexible(
            child: Text(info.name,
                style: BrandText.title(color: cs.onSurface, size: 14.5),
                overflow: TextOverflow.ellipsis),
          ),
          if (isNewest) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accentPill,
                borderRadius: BorderRadius.circular(Brand.rPill),
              ),
              child: Text('MOST RECENT',
                  style: BrandText.label(
                      color: AppColors.accentInk, size: 9.5)),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${_dates()}${info.backedUp ? ' · synced' : ''}',
        style: BrandText.body(color: cs.onSurfaceVariant, size: 12),
      ),
      trailing: PopupMenuButton<String>(
        enabled: enabled,
        icon: DuotoneIcon('menu_dots', size: 20, color: cs.onSurfaceVariant),
        onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(
            value: 'delete',
            child: Text('Delete',
                style: TextStyle(color: AppColors.errorInk)),
          ),
        ],
      ),
    );
  }
}
