// Settings Screen
// Main settings and configuration screen

import 'dart:io';
import '../../utils/platform_info.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/theme_mode_selector.dart';
import '../../models/app_mode.dart';
import '../../providers/settings_provider.dart';
import '../../services/api/orbguard_api_client.dart';
import '../../services/vpn/orbvpn_handoff_controller.dart';
import '../../services/security/desktop_scan_config.dart';
import 'package:url_launcher/url_launcher.dart';
import '../pricing/pricing_screen.dart';
import '../trust/device_capabilities_screen.dart';
import '../trust/privacy_explainer_screen.dart';
import '../account/login_screen.dart';
import '../account/security_screen.dart';
import '../../providers/account_provider.dart';
import '../../services/iap/iap_service.dart';
import '../../widgets/premium/premium_gate.dart';
import '../legal/legal_screen.dart';
import 'notification_discipline_screen.dart';

class SettingsScreen extends StatelessWidget {
  /// When true, skips the outer page wrapper (for embedding in other screens)
  final bool embedded;

  const SettingsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Settings',
      embedded: embedded,
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // Account — shared OrbVPN/OrbNet sign-in (optional; unlocks
              // subscription/credits/remote control). Anonymous scanning works
              // without it.
              _buildAccountSection(context),
              const SizedBox(height: 24),
              // Appearance
              _buildSettingsSection(
                context,
                'Appearance',
                'moon_stars',
                AppColors.chartColors[4],
                [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ThemeModeSelector(
                      current: settings.themeMode,
                      onChanged: settings.setThemeMode,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Protection settings
              _buildSettingsSection(
                context,
                'Protection',
                'shield_check',
                AppColors.accentInk,
                [
                  _buildSettingsTile(
                    context,
                    'Protection Features',
                    'Enable/disable security features',
                    'shield_check',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProtectionSettingsScreen(),
                      ),
                    ),
                  ),
                  _buildSettingsTile(
                    context,
                    'Scan Settings',
                    'Auto-scan and frequency',
                    'radar',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScanSettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Notifications
              _buildSettingsSection(
                context,
                'Notifications',
                'bell',
                AppColors.secondaryInk,
                [
                  _buildSettingsTile(
                    context,
                    'Alert Preferences',
                    'Manage notification types',
                    'bell_bing',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsScreen(),
                      ),
                    ),
                  ),
                  _buildSettingsTile(
                    context,
                    'Notification discipline',
                    'How we decide to alert you — rare, serious, actionable',
                    'bell',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationDisciplineScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Network & VPN
              _buildSettingsSection(
                context,
                'Network & VPN',
                'shield_keyhole',
                AppColors.accentInk,
                [
                  _buildSettingsTile(
                    context,
                    'VPN Settings',
                    'Auto-connect and preferences',
                    'key',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VpnSettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Desktop Security (only show on desktop platforms)
              if (PlatformInfo.isMacOS || PlatformInfo.isWindows || PlatformInfo.isLinux)
                _buildSettingsSection(
                  context,
                  'Desktop Security',
                  'laptop',
                  AppColors.errorInk,
                  [
                    _buildSettingsTile(
                      context,
                      'Persistence Scanner',
                      'Configure startup item scanning',
                      'radar',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DesktopScannerSettingsScreen(),
                        ),
                      ),
                    ),
                    _buildSettingsTile(
                      context,
                      'Permissions',
                      'Grant required system permissions',
                      'shield_check',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DesktopPermissionsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              if (PlatformInfo.isMacOS || PlatformInfo.isWindows || PlatformInfo.isLinux)
                const SizedBox(height: 24),
              // Privacy
              _buildSettingsSection(
                context,
                'Privacy & Security',
                'eye_closed',
                AppColors.chartColors[4],
                [
                  _buildSettingsTile(
                    context,
                    'Privacy Settings',
                    'Data sharing and app lock',
                    'lock',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacySettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Trust & transparency — the Phase 3 consumer trust surfaces.
              _buildSettingsSection(
                context,
                'Trust & transparency',
                'shield_keyhole',
                AppColors.accentInk,
                [
                  _buildSettingsTile(
                    context,
                    'How your privacy works',
                    'Everything runs on your phone — what we can and cannot see',
                    'incognito',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyExplainerScreen(),
                      ),
                    ),
                  ),
                  _buildSettingsTile(
                    context,
                    'What OrbGuard can do here',
                    'Honest capabilities for your device',
                    'smartphone',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DeviceCapabilitiesScreen(),
                      ),
                    ),
                  ),
                  _buildSettingsTile(
                    context,
                    'Plans & pricing',
                    'The price you see is the price that renews',
                    'wallet',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PricingScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Experience — Guard (consumer) vs the opt-in Pro expert console.
              _buildSettingsSection(
                context,
                'Experience',
                'widget_5',
                AppColors.accentInk,
                [
                  // Expert (Pro) mode is premium. Turning it ON requires a live
                  // subscription — otherwise we DON'T flip; we upsell. Turning
                  // it OFF (back to the always-free Guard) is never gated.
                  Consumer<AccountProvider>(
                    builder: (context, account, _) {
                      final cs = Theme.of(context).colorScheme;
                      final locked = !account.hasPremium;
                      return SwitchListTile(
                        secondary: DuotoneIcon(
                          'structure',
                          color: cs.onSurfaceVariant,
                          size: 24,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Expert (Pro) mode',
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (locked) ...[
                              const SizedBox(width: 8),
                              const PremiumBadge(),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          settings.isProMode
                              ? 'On — advanced threat-intelligence & enterprise tools are visible'
                              : locked
                                  ? 'Premium — subscribe to unlock the expert console'
                                  : 'Off — the simple, consumer Guard experience',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        value: settings.isProMode,
                        onChanged: (on) {
                          // Enabling Pro needs premium; if not entitled, show
                          // the upsell and leave the switch OFF (honest — Pro
                          // is not active until it's paid for).
                          if (on && !account.hasPremium) {
                            PremiumGate.ensure(context, account,
                                feature: 'Expert (Pro) mode');
                            return;
                          }
                          settings
                              .setAppMode(on ? AppMode.pro : AppMode.guard);
                        },
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Advanced
              _buildSettingsSection(
                context,
                'Advanced',
                'settings',
                Theme.of(context).colorScheme.onSurfaceVariant,
                [
                  _buildSettingsTile(
                    context,
                    'API Configuration',
                    'Server and connection settings',
                    'cloud_storage',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ApiSettingsScreen(),
                      ),
                    ),
                  ),
                  _buildSettingsTile(
                    context,
                    'Reset Settings',
                    'Restore default settings',
                    'refresh',
                    isDestructive: true,
                    onTap: () => _showResetDialog(context, settings),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // About
              _buildSettingsSection(
                context,
                'About',
                'info_circle',
                AppColors.secondaryInk,
                [
                  _buildSettingsTile(
                    context,
                    'App Version',
                    '1.0.0 (Build 1)',
                    'info_circle',
                  ),
                  _buildSettingsTile(
                    context,
                    'Terms of Service',
                    'View terms and conditions',
                    'file_text',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const LegalScreen(doc: LegalDoc.terms),
                      ),
                    ),
                  ),
                  _buildSettingsTile(
                    context,
                    'Privacy Policy',
                    'View privacy policy',
                    'clipboard_text',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const LegalScreen(doc: LegalDoc.privacy),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context,
    String title,
    String icon,
    Color color,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DuotoneIcon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: EdgeInsets.zero,
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    String title,
    String subtitle,
    String icon, {
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: DuotoneIcon(
        icon,
        color: isDestructive ? AppColors.errorInk : cs.onSurfaceVariant,
        size: 24,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? AppColors.errorInk : cs.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      trailing: onTap != null
          ? DuotoneIcon('alt_arrow_right', color: cs.onSurfaceVariant, size: 20)
          : null,
      onTap: onTap,
    );
  }

  /// Account section — reflects login state from [AccountProvider]. Logged
  /// out: a single "Sign in / Account" row opening the login screen. Logged in:
  /// the account email + a "Sign out" row.
  Widget _buildAccountSection(BuildContext context) {
    return Consumer<AccountProvider>(
      builder: (context, account, _) {
        final loggedIn = account.isLoggedIn;
        final tier = account.subscriptionTier;
        return _buildSettingsSection(
          context,
          'Account',
          'shield_keyhole',
          AppColors.accentInk,
          [
            if (!loggedIn)
              _buildSettingsTile(
                context,
                'Sign in / Account',
                'Use your OrbVPN account to unlock subscription & remote control',
                'login',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
              )
            else ...[
              _buildSettingsTile(
                context,
                account.email ?? 'Signed in',
                tier != null && tier.isNotEmpty
                    ? 'Signed in with your OrbVPN account · $tier'
                    : 'Signed in with your OrbVPN account',
                'shield_keyhole',
              ),
              // Subscription: current plan + the purchase path. One subscription
              // covers OrbGuard and OrbVPN.
              _buildSettingsTile(
                context,
                'Subscription',
                account.hasPremium
                    ? '${account.subscriptionLabel} — covers OrbGuard & OrbVPN'
                    : 'Free plan — view plans & subscribe',
                'wallet',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PricingScreen()),
                ),
              ),
              if (account.hasPremium)
                _buildSettingsTile(
                  context,
                  'Manage subscription',
                  Platform.isAndroid
                      ? 'Change, upgrade, or cancel in Google Play'
                      : 'Change, upgrade, or cancel in the App Store',
                  'settings',
                  onTap: () => _openStoreSubscriptionManagement(context),
                ),
              _buildSettingsTile(
                context,
                'Restore purchases',
                'Recover a subscription bought on this store account',
                'refresh',
                onTap: () => _restorePurchases(context),
              ),
              // Passkeys + account deletion live in Account security.
              _buildSettingsTile(
                context,
                'Account security',
                'Passkeys, sign-in options & account deletion',
                'shield_keyhole',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SecurityScreen()),
                ),
              ),
              _buildSettingsTile(
                context,
                'Sign out',
                'Sign out of your OrbVPN account on this device',
                'logout',
                isDestructive: true,
                onTap: () => _showSignOutSheet(context, account),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Open the platform's own subscription-management page (App Store / Google
  /// Play). Store-billed subscriptions can only be changed or cancelled there.
  Future<void> _openStoreSubscriptionManagement(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = Platform.isAndroid
        ? 'https://play.google.com/store/account/subscriptions'
        : 'https://apps.apple.com/account/subscriptions';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  /// Restore previously-bought subscriptions and surface the outcome here (the
  /// IAP results stream's regular listener is the pricing screen, which isn't
  /// open now).
  Future<void> _restorePurchases(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final iap = context.read<IapService>();
    messenger.showSnackBar(
      const SnackBar(content: Text('Checking for previous purchases…')),
    );
    final sub = iap.results.listen((r) {
      if (r.message != null || r.isSuccess) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(r.isSuccess
                ? 'Subscription restored — premium unlocked.'
                : r.message!),
          ));
      }
    });
    try {
      await iap.restore();
    } finally {
      // The restore verify/feedback lands within restore()'s own window (it
      // waits for delivery); a short grace covers the last verify round-trip.
      Future<void>.delayed(const Duration(seconds: 8), sub.cancel);
    }
  }

  void _showSignOutSheet(BuildContext context, AccountProvider account) {
    final messenger = ScaffoldMessenger.of(context);
    _showDangerSheet(
      context,
      title: 'Sign out',
      body: Text(
        'You will be signed out of your OrbVPN account on this device. '
        'Anonymous scanning keeps working.',
        style: TextStyle(
          fontSize: 14.5,
          height: 1.45,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      confirmLabel: 'Sign out',
      onConfirm: () async {
        await account.logout();
        messenger.showSnackBar(
          const SnackBar(content: Text('Signed out')),
        );
      },
    );
  }

  void _showResetDialog(BuildContext context, SettingsProvider settings) {
    _showDangerSheet(
      context,
      title: 'Reset Settings',
      body: Text(
        'This will reset all settings to their default values. This action cannot be undone.',
        style: TextStyle(
          fontSize: 14.5,
          height: 1.45,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      confirmLabel: 'Reset',
      onConfirm: () {
        settings.resetAllSettings();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings reset to defaults')),
        );
      },
    );
  }
}

/// Protection Settings Screen
class ProtectionSettingsScreen extends StatelessWidget {
  const ProtectionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Protection Features',
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final protection = settings.protection;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _buildInfoCard(
                'Configure which protection features are active. '
                'Disabling features may reduce security.',
                'info_circle',
                AppColors.secondaryInk,
              ),
              const SizedBox(height: 24),
              _buildSwitchTile(
                context,
                'SMS Protection',
                'Analyze SMS messages for threats',
                'chat_dots',
                protection.smsProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(smsProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'URL Protection',
                'Check URLs for malicious content',
                'link_round',
                protection.urlProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(urlProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'QR Code Protection',
                'Scan QR codes for threats',
                'qr_code',
                protection.qrProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(qrProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'App Security',
                'Monitor installed apps for risks',
                'smartphone',
                protection.appSecurityEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(appSecurityEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Network Protection',
                'Monitor WiFi and network security',
                'wi_fi_router',
                protection.networkProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(networkProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Dark Web Monitoring',
                'Check for credential breaches',
                'incognito',
                protection.darkWebMonitoringEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(darkWebMonitoringEnabled: value),
                ),
              ),
              const Divider(height: 32),
              _buildSwitchTile(
                context,
                'Real-time Alerts',
                'Get instant threat notifications',
                'bell_bing',
                protection.realTimeAlertsEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(realTimeAlertsEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Auto-block Threats',
                'Automatically block detected threats',
                'forbidden',
                protection.autoBlockThreats,
                (value) => settings.updateProtection(
                  protection.copyWith(autoBlockThreats: value),
                ),
                isWarning: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(String text, String icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Row(
        children: [
          DuotoneIcon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withAlpha(204),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    String icon,
    bool value,
    Function(bool) onChanged, {
    bool isWarning = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: SwitchListTile(
        secondary: DuotoneIcon(
          icon,
          color: value ? AppColors.accentInk : cs.onSurfaceVariant,
          size: 24,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        // Theme styles the active switch (lime track + onLime thumb);
        // warning switches keep a pink cue.
        activeThumbColor: isWarning ? AppColors.warning : null,
      ),
    );
  }
}

/// Notification Settings Screen
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Notification Settings',
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final notif = settings.notifications;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _buildSectionHeader(context, 'Notifications'),
              _buildSwitchTile(
                context,
                'Push Notifications',
                'Enable all push notifications',
                notif.pushNotificationsEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(pushNotificationsEnabled: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader(context, 'Alert Types'),
              _buildSwitchTile(
                context,
                'Threat Alerts',
                'Notify when threats are detected',
                notif.threatAlertsEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(threatAlertsEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Breach Alerts',
                'Notify about data breaches',
                notif.breachAlertsEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(breachAlertsEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Scan Completed',
                'Notify when scans finish',
                notif.scanCompletedAlerts,
                (value) => settings.updateNotifications(
                  notif.copyWith(scanCompletedAlerts: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader(context, 'Sound & Vibration'),
              _buildSwitchTile(
                context,
                'Sound',
                'Play sound for notifications',
                notif.soundEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(soundEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Vibration',
                'Vibrate for notifications',
                notif.vibrationEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(vibrationEnabled: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader(context, 'Quiet Hours'),
              _buildSwitchTile(
                context,
                'Enable Quiet Hours',
                'Silence notifications during set hours',
                notif.quietHoursEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(quietHoursEnabled: value),
                ),
              ),
              if (notif.quietHoursEnabled)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildTimeSelector(
                        context,
                        'Start',
                        notif.quietHoursStart,
                        (hour) => settings.updateNotifications(
                          notif.copyWith(quietHoursStart: hour),
                        ),
                      ),
                      DuotoneIcon('alt_arrow_right',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 20),
                      _buildTimeSelector(
                        context,
                        'End',
                        notif.quietHoursEnd,
                        (hour) => settings.updateNotifications(
                          notif.copyWith(quietHoursEnd: hour),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(color: cs.onSurface),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildTimeSelector(
    BuildContext context,
    String label,
    int hour,
    Function(int) onChanged,
  ) {
    return InkWell(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: 0),
          builder: (context, child) {
            return Theme(
              data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: AppColors.primary,
                ),
              ),
              child: child!,
            );
          },
        );
        if (time != null) {
          onChanged(time.hour);
        }
      },
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${hour.toString().padLeft(2, '0')}:00',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Privacy Settings Screen
class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Privacy Settings',
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final privacy = settings.privacy;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _buildSectionHeader(context, 'App Security'),
              _buildSwitchTile(
                context,
                'Biometric Lock',
                'Require fingerprint or face to open app',
                privacy.biometricLockEnabled,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(biometricLockEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Hide Notification Content',
                'Don\'t show details in notifications',
                privacy.hideNotificationContent,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(hideNotificationContent: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader(context, 'Data Collection'),
              _buildSwitchTile(
                context,
                'Analytics',
                'Help improve the app with usage data',
                privacy.analyticsEnabled,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(analyticsEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Crash Reporting',
                'Send crash reports to improve stability',
                privacy.crashReportingEnabled,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(crashReportingEnabled: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Share Anonymous Data',
                'Contribute to threat intelligence network',
                privacy.shareAnonymousData,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(shareAnonymousData: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader(context, 'Data Storage'),
              _buildSwitchTile(
                context,
                'Local Data Only',
                'Don\'t sync data to cloud (reduces features)',
                privacy.localDataOnly,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(localDataOnly: value),
                ),
              ),
              const SizedBox(height: 24),
              // Data management
              GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: DuotoneIcon('file_download',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 24),
                      title: Text(
                        'Export Data',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                      subtitle: Text(
                        'Not available yet',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12),
                      ),
                      // No real data-export pipeline exists, so this reports
                      // honestly instead of faking an "export started" toast.
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Data export is not available yet')),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: DuotoneIcon('trash_bin_minimalistic', color: AppColors.errorInk, size: 24),
                      title: Text(
                        'Delete All Data',
                        style: TextStyle(color: AppColors.errorInk),
                      ),
                      subtitle: Text(
                        'Permanently delete all stored data',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12),
                      ),
                      trailing: DuotoneIcon('alt_arrow_right',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 20),
                      onTap: () => _showDeleteDialog(context),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(color: cs.onSurface),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    _showDangerSheet(
      context,
      title: 'Delete All Data',
      body: Text(
        'This will permanently delete all your data including scan history, monitored assets, and settings. This action cannot be undone.',
        style: TextStyle(
          fontSize: 14.5,
          height: 1.45,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      confirmLabel: 'Delete',
      onConfirm: () async {
        // Actually clear the locally persisted store (settings, scan
        // history, monitored assets, freeze status — everything kept in
        // SharedPreferences) instead of only claiming to.
        final messenger = ScaffoldMessenger.of(context);
        await context.read<SettingsProvider>().resetAllSettings();
        messenger.showSnackBar(
          const SnackBar(content: Text('Local data cleared')),
        );
      },
    );
  }
}

/// Scan Settings Screen
class ScanSettingsScreen extends StatelessWidget {
  const ScanSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Scan Settings',
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final scan = settings.scan;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _buildSwitchTile(
                context,
                'Auto Scan',
                'Automatically scan for threats',
                scan.autoScanEnabled,
                (value) => settings.updateScan(
                  scan.copyWith(autoScanEnabled: value),
                ),
              ),
              if (scan.autoScanEnabled) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan Frequency',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<int>(
                        value: scan.scanFrequencyHours,
                        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        isExpanded: true,
                        underline: Container(),
                        items: const [
                          DropdownMenuItem(
                              value: 6, child: Text('Every 6 hours')),
                          DropdownMenuItem(
                              value: 12, child: Text('Every 12 hours')),
                          DropdownMenuItem(value: 24, child: Text('Daily')),
                          DropdownMenuItem(value: 168, child: Text('Weekly')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            settings.updateScan(
                              scan.copyWith(scanFrequencyHours: value),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _buildSwitchTile(
                context,
                'Scan on WiFi Only',
                'Only auto-scan when connected to WiFi',
                scan.scanOnWifiOnly,
                (value) => settings.updateScan(
                  scan.copyWith(scanOnWifiOnly: value),
                ),
              ),
              _buildSwitchTile(
                context,
                'Deep Scan',
                'More thorough scanning (uses more battery)',
                scan.deepScanEnabled,
                (value) => settings.updateScan(
                  scan.copyWith(deepScanEnabled: value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(color: cs.onSurface),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// VPN Settings Screen
class VpnSettingsScreen extends StatelessWidget {
  const VpnSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'VPN Settings',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildOrbVpnHandoffCard(context),
        ],
      ),
    );
  }

  /// Interim VPN hand-off: OrbGuard has no bundled tunnel yet, so it opens the
  /// OrbVPN app (or its download page). See docs/VPN_PORT_PLAN.md.
  Widget _buildOrbVpnHandoffCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.vpn_lock_rounded, color: cs.onSurface, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'VPN by OrbVPN',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'OrbGuard uses the OrbVPN app for the VPN tunnel. Open OrbVPN to '
            "connect — or download it if you don't have it yet.",
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final controller = OrbVpnHandoffController();
                await controller.connect();
                controller.dispose();
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open OrbVPN'),
            ),
          ),
        ],
      ),
    );
  }
}

/// API Settings Screen
class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _apiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'API Configuration',
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final api = settings.api;

          // Initialize controllers with current values
          if (_urlController.text.isEmpty) {
            _urlController.text = api.serverUrl;
          }
          if (_apiKeyController.text.isEmpty && api.apiKey != null) {
            _apiKeyController.text = api.apiKey!;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withAlpha(20),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: Row(
                  children: [
                    DuotoneIcon('danger_triangle', color: AppColors.secondaryInk, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'These settings are for advanced users. Incorrect configuration may cause the app to stop working.',
                        style: TextStyle(
                          color: AppColors.secondaryInk,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSwitchTile(
                context,
                'Use Custom Server',
                'Connect to a custom API server',
                api.useCustomServer,
                (value) => settings.updateApi(
                  api.copyWith(useCustomServer: value),
                ),
              ),
              if (api.useCustomServer) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server URL',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _urlController,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'https://api.example.com',
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          settings.updateApi(api.copyWith(serverUrl: value));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'API Key',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiKeyController,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface),
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'Enter API key',
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          settings.updateApi(api.copyWith(apiKey: value));
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _buildSwitchTile(
                context,
                'WebSocket Connection',
                'Enable real-time updates',
                api.enableWebSocket,
                (value) => settings.updateApi(
                  api.copyWith(enableWebSocket: value),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection Timeout',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: api.connectionTimeout,
                      dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      isExpanded: true,
                      underline: Container(),
                      items: const [
                        DropdownMenuItem(value: 15, child: Text('15 seconds')),
                        DropdownMenuItem(value: 30, child: Text('30 seconds')),
                        DropdownMenuItem(value: 60, child: Text('60 seconds')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          settings.updateApi(
                            api.copyWith(connectionTimeout: value),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Testing connection...')),
                  );
                  final success = await OrbGuardApiClient.instance.testConnection();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? 'Connection successful!' : 'Connection failed'),
                        backgroundColor: success ? GlassTheme.successColor : GlassTheme.errorColor,
                      ),
                    );
                  }
                },
                icon: const DuotoneIcon('wi_fi_router', color: Brand.onLime, size: 20),
                label: const Text('Test Connection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Brand.onLime,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(color: cs.onSurface),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// Desktop Scanner Settings Screen
class DesktopScannerSettingsScreen extends StatefulWidget {
  const DesktopScannerSettingsScreen({super.key});

  @override
  State<DesktopScannerSettingsScreen> createState() => _DesktopScannerSettingsScreenState();
}

class _DesktopScannerSettingsScreenState extends State<DesktopScannerSettingsScreen> {
  bool _autoScanOnStartup = true;
  bool _scanLaunchAgents = true;
  bool _scanLaunchDaemons = true;
  bool _scanLoginItems = true;
  bool _scanKernelExtensions = true;
  bool _scanBrowserExtensions = true;
  bool _scanCronJobs = true;
  bool _deepScan = false;
  bool _hashVerification = true;
  int _scanIntervalHours = 24;

  @override
  void initState() {
    super.initState();
    DesktopScanConfig.load().then((c) {
      if (!mounted) return;
      setState(() {
        _autoScanOnStartup = c.autoScanOnStartup;
        _scanIntervalHours = c.scanIntervalHours;
        _scanLaunchAgents = c.scanLaunchAgents;
        _scanLaunchDaemons = c.scanLaunchDaemons;
        _scanLoginItems = c.scanLoginItems;
        _scanKernelExtensions = c.scanKernelExtensions;
        _scanBrowserExtensions = c.scanBrowserExtensions;
        _scanCronJobs = c.scanCronJobs;
        _deepScan = c.deepScan;
        _hashVerification = c.hashVerification;
      });
    });
  }

  /// Apply a change and persist the whole config so the scanner honors it.
  void _setAndSave(VoidCallback change) {
    setState(change);
    DesktopScanConfig(
      autoScanOnStartup: _autoScanOnStartup,
      scanIntervalHours: _scanIntervalHours,
      scanLaunchAgents: _scanLaunchAgents,
      scanLaunchDaemons: _scanLaunchDaemons,
      scanLoginItems: _scanLoginItems,
      scanKernelExtensions: _scanKernelExtensions,
      scanBrowserExtensions: _scanBrowserExtensions,
      scanCronJobs: _scanCronJobs,
      deepScan: _deepScan,
      hashVerification: _hashVerification,
    ).save();
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Persistence Scanner',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.info.withAlpha(20),
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
            ),
            child: Row(
              children: [
                DuotoneIcon('info_circle', color: AppColors.secondaryInk, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Configure which persistence mechanisms to scan and how often to check for suspicious items.',
                    style: TextStyle(color: AppColors.secondaryInk, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Auto scan settings
          _buildSectionHeader('Automatic Scanning'),
          _buildSwitchTile(
            'Auto Scan on Startup',
            'Scan when app launches',
            _autoScanOnStartup,
            (v) => _setAndSave(() => _autoScanOnStartup = v),
          ),
          if (_autoScanOnStartup) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scan Interval', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: _scanIntervalHours,
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    isExpanded: true,
                    underline: Container(),
                    items: const [
                      DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                      DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
                      DropdownMenuItem(value: 24, child: Text('Daily')),
                      DropdownMenuItem(value: 168, child: Text('Weekly')),
                    ],
                    onChanged: (v) => _setAndSave(() => _scanIntervalHours = v ?? 24),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Scan targets
          _buildSectionHeader('Scan Targets'),
          _buildSwitchTile(
            'Launch Agents',
            'User and system launch agents',
            _scanLaunchAgents,
            (v) => _setAndSave(() => _scanLaunchAgents = v),
          ),
          _buildSwitchTile(
            'Launch Daemons',
            'System launch daemons',
            _scanLaunchDaemons,
            (v) => _setAndSave(() => _scanLaunchDaemons = v),
          ),
          _buildSwitchTile(
            'Login Items',
            'Apps that open at login',
            _scanLoginItems,
            (v) => _setAndSave(() => _scanLoginItems = v),
          ),
          _buildSwitchTile(
            'Kernel Extensions',
            'System extensions and drivers',
            _scanKernelExtensions,
            (v) => _setAndSave(() => _scanKernelExtensions = v),
          ),
          _buildSwitchTile(
            'Browser Extensions',
            'Safari, Chrome, Firefox extensions',
            _scanBrowserExtensions,
            (v) => _setAndSave(() => _scanBrowserExtensions = v),
          ),
          _buildSwitchTile(
            'Cron Jobs',
            'Scheduled tasks',
            _scanCronJobs,
            (v) => _setAndSave(() => _scanCronJobs = v),
          ),
          const SizedBox(height: 24),

          // Advanced settings
          _buildSectionHeader('Advanced'),
          _buildSwitchTile(
            'Deep Scan',
            'More thorough scanning (slower)',
            _deepScan,
            (v) => _setAndSave(() => _deepScan = v),
          ),
          _buildSwitchTile(
            'Hash Verification',
            'Compute file hashes for threat intel',
            _hashVerification,
            (v) => _setAndSave(() => _hashVerification = v),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: SwitchListTile(
        title: Text(title,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        subtitle: Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// Desktop Permissions Screen
class DesktopPermissionsScreen extends StatelessWidget {
  const DesktopPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Permissions',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Platform-specific permissions
          if (PlatformInfo.isMacOS) ..._buildMacOSPermissions(context),
          if (PlatformInfo.isLinux) ..._buildLinuxPermissions(context),
          if (PlatformInfo.isWindows) ..._buildWindowsPermissions(context),
        ],
      ),
    );
  }

  List<Widget> _buildMacOSPermissions(BuildContext context) {
    return [
      // Full Disk Access
      _buildPermissionCard(
        context,
        icon: 'folder',
        title: 'Full Disk Access',
        description: 'Required to scan all persistence locations including protected system directories.',
        status: 'Required',
        statusColor: AppColors.amberInk,
        instructions: [
          '1. Open System Settings',
          '2. Go to Privacy & Security → Full Disk Access',
          '3. Click the + button and add OrbGuard',
          '4. Restart OrbGuard for changes to take effect',
        ],
        onGrant: () => _openMacOSSettings('x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles'),
      ),
      const SizedBox(height: 24),

      // Automation
      _buildPermissionCard(
        context,
        icon: 'settings',
        title: 'Automation',
        description: 'Allows scanning of Folder Actions and other AppleScript-based persistence.',
        status: 'Recommended',
        statusColor: AppColors.secondaryInk,
        instructions: [
          '1. Open System Settings',
          '2. Go to Privacy & Security → Automation',
          '3. Enable OrbGuard to control System Events',
        ],
        onGrant: () => _openMacOSSettings('x-apple.systempreferences:com.apple.preference.security?Privacy_Automation'),
      ),
      const SizedBox(height: 24),

      // Accessibility (optional)
      _buildPermissionCard(
        context,
        icon: 'eye',
        title: 'Accessibility',
        description: 'Optional - enables monitoring of input methods and accessibility-based persistence.',
        status: 'Optional',
        statusColor: Brand.text3,
        instructions: [
          '1. Open System Settings',
          '2. Go to Privacy & Security → Accessibility',
          '3. Click the + button and add OrbGuard',
        ],
        onGrant: () => _openMacOSSettings('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'),
      ),
      const SizedBox(height: 24),

      // Info about notarization
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.success.withAlpha(20),
          borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
        ),
        child: Row(
          children: [
            DuotoneIcon('check_circle', color: AppColors.accentInk, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'OrbGuard is notarized by Apple and does not require disabling Gatekeeper.',
                style: TextStyle(color: AppColors.accentInk, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildLinuxPermissions(BuildContext context) {
    return [
      // Root access info
      _buildPermissionCard(
        context,
        icon: 'key',
        title: 'Root Access',
        description: 'Some persistence locations require root privileges to scan (e.g., /etc/systemd, /etc/cron.d).',
        status: 'Recommended',
        statusColor: AppColors.amberInk,
        instructions: [
          'Option 1: Run OrbGuard with sudo for full access',
          '  sudo orbguard',
          '',
          'Option 2: Add your user to required groups',
          '  sudo usermod -aG systemd-journal \$USER',
          '',
          'Option 3: Use polkit rules for specific access',
        ],
        onGrant: null,
      ),
      const SizedBox(height: 24),

      // SELinux info
      _buildPermissionCard(
        context,
        icon: 'shield',
        title: 'SELinux/AppArmor',
        description: 'If SELinux or AppArmor is enabled, you may need to configure a policy for OrbGuard.',
        status: 'If Enabled',
        statusColor: AppColors.secondaryInk,
        instructions: [
          'For SELinux:',
          '  Check status: getenforce',
          '  View denials: ausearch -m avc -ts recent',
          '',
          'For AppArmor:',
          '  Check status: aa-status',
          '  You may need to create a profile in /etc/apparmor.d/',
        ],
        onGrant: null,
      ),
      const SizedBox(height: 24),

      // File permissions
      _buildPermissionCard(
        context,
        icon: 'folder',
        title: 'File System Access',
        description: 'OrbGuard needs read access to various system directories.',
        status: 'Required',
        statusColor: AppColors.amberInk,
        instructions: [
          'Directories that require access:',
          '  /etc/systemd/system',
          '  /etc/init.d',
          '  /etc/cron.d',
          '  /etc/xdg/autostart',
          '  ~/.config/autostart',
          '  ~/.bashrc, ~/.profile, etc.',
        ],
        onGrant: null,
      ),
    ];
  }

  List<Widget> _buildWindowsPermissions(BuildContext context) {
    return [
      // Administrator access
      _buildPermissionCard(
        context,
        icon: 'shield_check',
        title: 'Administrator Access',
        description: 'Required to scan system registry keys and protected persistence locations.',
        status: 'Required',
        statusColor: AppColors.amberInk,
        instructions: [
          '1. Right-click on OrbGuard',
          '2. Select "Run as administrator"',
          '',
          'For persistent admin access:',
          '1. Right-click OrbGuard → Properties',
          '2. Go to Compatibility tab',
          '3. Check "Run this program as administrator"',
        ],
        onGrant: null,
      ),
      const SizedBox(height: 24),

      // Windows Security
      _buildPermissionCard(
        context,
        icon: 'shield',
        title: 'Windows Security Exception',
        description: 'Add OrbGuard to Windows Security exclusions to prevent false positives.',
        status: 'Recommended',
        statusColor: AppColors.secondaryInk,
        instructions: [
          '1. Open Windows Security',
          '2. Go to Virus & threat protection',
          '3. Click "Manage settings" under Virus & threat protection settings',
          '4. Scroll to Exclusions and click "Add or remove exclusions"',
          '5. Add the OrbGuard installation folder',
        ],
        onGrant: () => _openWindowsSettings('windowsdefender:'),
      ),
      const SizedBox(height: 24),

      // Registry access
      _buildPermissionCard(
        context,
        icon: 'key',
        title: 'Registry Access',
        description: 'OrbGuard scans various registry locations for persistence mechanisms.',
        status: 'Auto-granted',
        statusColor: AppColors.accentInk,
        instructions: [
          'Registry locations scanned:',
          '  HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run',
          '  HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run',
          '  HKLM\\SOFTWARE\\Microsoft\\Active Setup',
          '  And more...',
          '',
          'These are automatically accessible when running as admin.',
        ],
        onGrant: null,
      ),
    ];
  }

  Widget _buildPermissionCard(
    BuildContext context, {
    required String icon,
    required String title,
    required String description,
    required String status,
    required Color statusColor,
    required List<String> instructions,
    VoidCallback? onGrant,
  }) {
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon(icon, color: statusColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.overlayLight,
              borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instructions:',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...instructions.map((instruction) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    instruction,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontFamily: instruction.startsWith('  ') ? 'monospace' : null,
                    ),
                  ),
                )),
              ],
            ),
          ),
          if (onGrant != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onGrant,
                icon: const DuotoneIcon('settings', color: Brand.onLime, size: 18),
                label: const Text('Open Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Brand.onLime,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMacOSSettings(String url) async {
    // Use 'open' command on macOS to open system preferences
    await Process.run('open', [url]);
  }

  Future<void> _openWindowsSettings(String url) async {
    // Use 'start' command on Windows to open settings
    await Process.run('cmd', ['/c', 'start', url], runInShell: true);
  }
}

/// A destructive confirm rendered as an iOS bottom sheet: the same layout as the
/// shared SheetPanel confirm, but the primary action is a danger-styled
/// [BrandButton.destructive]. The primary button dismisses the sheet first, then
/// runs [onConfirm]; Cancel or a barrier-dismiss just closes it.
void _showDangerSheet(
  BuildContext context, {
  required String title,
  required Widget body,
  required String confirmLabel,
  required VoidCallback onConfirm,
  String cancelLabel = 'Cancel',
}) {
  final cs = Theme.of(context).colorScheme;
  showAppSheet(
    context,
    child: Builder(
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: BrandText.h2(color: cs.onSurface, size: 21)),
            const SizedBox(height: 14),
            Flexible(child: SingleChildScrollView(child: body)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BrandButton.destructive(
                    label: confirmLabel,
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      onConfirm();
                    },
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
