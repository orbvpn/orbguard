/// Settings Screen
/// Main settings and configuration screen

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/settings_provider.dart';
import '../../services/api/orbguard_api_client.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Settings',
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // Protection settings
              _buildSettingsSection(
                context,
                'Protection',
                'shield_check',
                const Color(0xFF00D9FF),
                [
                  _buildSettingsTile(
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
                Colors.orange,
                [
                  _buildSettingsTile(
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
                ],
              ),
              const SizedBox(height: 24),
              // Network & VPN
              _buildSettingsSection(
                context,
                'Network & VPN',
                'shield_keyhole',
                Colors.green,
                [
                  _buildSettingsTile(
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
              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                _buildSettingsSection(
                  context,
                  'Desktop Security',
                  'laptop',
                  const Color(0xFFFF6B6B),
                  [
                    _buildSettingsTile(
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
              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const SizedBox(height: 24),
              // Privacy
              _buildSettingsSection(
                context,
                'Privacy & Security',
                'eye_closed',
                Colors.purple,
                [
                  _buildSettingsTile(
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
              // Advanced
              _buildSettingsSection(
                context,
                'Advanced',
                'settings',
                Colors.grey,
                [
                  _buildSettingsTile(
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
                Colors.blue,
                [
                  _buildSettingsTile(
                    'App Version',
                    '1.0.0 (Build 1)',
                    'info_circle',
                  ),
                  _buildSettingsTile(
                    'Terms of Service',
                    'View terms and conditions',
                    'file_text',
                    onTap: () {},
                  ),
                  _buildSettingsTile(
                    'Privacy Policy',
                    'View privacy policy',
                    'clipboard_text',
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 32),
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
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsTile(
    String title,
    String subtitle,
    String icon, {
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: DuotoneIcon(
        icon,
        color: isDestructive ? Colors.red : Colors.grey,
        size: 24,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 12,
        ),
      ),
      trailing: onTap != null
          ? const DuotoneIcon('alt_arrow_right', color: Colors.grey, size: 20)
          : null,
      onTap: onTap,
    );
  }

  void _showResetDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'Reset Settings',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will reset all settings to their default values. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settings.resetAllSettings();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings reset to defaults')),
              );
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildInfoCard(
                'Configure which protection features are active. '
                'Disabling features may reduce security.',
                'info_circle',
                Colors.blue,
              ),
              const SizedBox(height: 24),
              _buildSwitchTile(
                'SMS Protection',
                'Analyze SMS messages for threats',
                'chat_dots',
                protection.smsProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(smsProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'URL Protection',
                'Check URLs for malicious content',
                'link',
                protection.urlProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(urlProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'QR Code Protection',
                'Scan QR codes for threats',
                'qr_code',
                protection.qrProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(qrProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'App Security',
                'Monitor installed apps for risks',
                'smartphone',
                protection.appSecurityEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(appSecurityEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Network Protection',
                'Monitor WiFi and network security',
                'wi_fi_router',
                protection.networkProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(networkProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Dark Web Monitoring',
                'Check for credential breaches',
                'incognito',
                protection.darkWebMonitoringEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(darkWebMonitoringEnabled: value),
                ),
              ),
              const Divider(color: Colors.white10, height: 32),
              _buildSwitchTile(
                'Real-time Alerts',
                'Get instant threat notifications',
                'bell_bing',
                protection.realTimeAlertsEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(realTimeAlertsEnabled: value),
                ),
              ),
              _buildSwitchTile(
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
        borderRadius: BorderRadius.circular(12),
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
    String title,
    String subtitle,
    String icon,
    bool value,
    Function(bool) onChanged, {
    bool isWarning = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary: DuotoneIcon(
          icon,
          color: value ? const Color(0xFF00D9FF) : Colors.grey,
          size: 24,
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: isWarning ? Colors.orange : const Color(0xFF00D9FF),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildSectionHeader('Notifications'),
              _buildSwitchTile(
                'Push Notifications',
                'Enable all push notifications',
                notif.pushNotificationsEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(pushNotificationsEnabled: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('Alert Types'),
              _buildSwitchTile(
                'Threat Alerts',
                'Notify when threats are detected',
                notif.threatAlertsEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(threatAlertsEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Breach Alerts',
                'Notify about data breaches',
                notif.breachAlertsEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(breachAlertsEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Scan Completed',
                'Notify when scans finish',
                notif.scanCompletedAlerts,
                (value) => settings.updateNotifications(
                  notif.copyWith(scanCompletedAlerts: value),
                ),
              ),
              _buildSwitchTile(
                'Weekly Report',
                'Send weekly security summary',
                notif.weeklyReportEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(weeklyReportEnabled: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('Sound & Vibration'),
              _buildSwitchTile(
                'Sound',
                'Play sound for notifications',
                notif.soundEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(soundEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Vibration',
                'Vibrate for notifications',
                notif.vibrationEnabled,
                (value) => settings.updateNotifications(
                  notif.copyWith(vibrationEnabled: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('Quiet Hours'),
              _buildSwitchTile(
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
                    color: const Color(0xFF1D1E33),
                    borderRadius: BorderRadius.circular(12),
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
                      const DuotoneIcon('alt_arrow_right', color: Colors.grey, size: 20),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF00D9FF),
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
                  primary: Color(0xFF00D9FF),
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
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${hour.toString().padLeft(2, '0')}:00',
            style: const TextStyle(
              color: Colors.white,
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildSectionHeader('App Security'),
              _buildSwitchTile(
                'Biometric Lock',
                'Require fingerprint or face to open app',
                privacy.biometricLockEnabled,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(biometricLockEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Hide Notification Content',
                'Don\'t show details in notifications',
                privacy.hideNotificationContent,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(hideNotificationContent: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('Data Collection'),
              _buildSwitchTile(
                'Analytics',
                'Help improve the app with usage data',
                privacy.analyticsEnabled,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(analyticsEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Crash Reporting',
                'Send crash reports to improve stability',
                privacy.crashReportingEnabled,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(crashReportingEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Share Anonymous Data',
                'Contribute to threat intelligence network',
                privacy.shareAnonymousData,
                (value) => settings.updatePrivacy(
                  privacy.copyWith(shareAnonymousData: value),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('Data Storage'),
              _buildSwitchTile(
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
                      leading: const DuotoneIcon('file_download', color: Colors.grey, size: 24),
                      title: const Text(
                        'Export Data',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Download all your data',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      trailing:
                          const DuotoneIcon('alt_arrow_right', color: Colors.grey, size: 20),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Data export started...')),
                        );
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    ListTile(
                      leading: const DuotoneIcon('trash_bin_minimalistic', color: Colors.red, size: 24),
                      title: const Text(
                        'Delete All Data',
                        style: TextStyle(color: Colors.red),
                      ),
                      subtitle: Text(
                        'Permanently delete all stored data',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      trailing:
                          const DuotoneIcon('alt_arrow_right', color: Colors.grey, size: 20),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF00D9FF),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'Delete All Data',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently delete all your data including scan history, monitored assets, and settings. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All data deleted')),
              );
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildSwitchTile(
                'Auto Scan',
                'Automatically scan for threats',
                scan.autoScanEnabled,
                (value) => settings.updateScan(
                  scan.copyWith(autoScanEnabled: value),
                ),
              ),
              if (scan.autoScanEnabled) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1E33),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan Frequency',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<int>(
                        value: scan.scanFrequencyHours,
                        dropdownColor: const Color(0xFF2A2B40),
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
              const SizedBox(height: 16),
              _buildSwitchTile(
                'Scan on WiFi Only',
                'Only auto-scan when connected to WiFi',
                scan.scanOnWifiOnly,
                (value) => settings.updateScan(
                  scan.copyWith(scanOnWifiOnly: value),
                ),
              ),
              _buildSwitchTile(
                'Scan New Apps',
                'Automatically scan newly installed apps',
                scan.scanNewApps,
                (value) => settings.updateScan(
                  scan.copyWith(scanNewApps: value),
                ),
              ),
              _buildSwitchTile(
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
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF00D9FF),
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
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final vpn = settings.vpn;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildSwitchTile(
                'Auto Connect',
                'Automatically connect VPN when needed',
                vpn.autoConnectEnabled,
                (value) => settings.updateVpn(
                  vpn.copyWith(autoConnectEnabled: value),
                ),
              ),
              if (vpn.autoConnectEnabled) ...[
                const SizedBox(height: 8),
                _buildSwitchTile(
                  'Connect on Unsecured WiFi',
                  'Auto-connect when on open networks',
                  vpn.connectOnUnsecuredWifi,
                  (value) => settings.updateVpn(
                    vpn.copyWith(connectOnUnsecuredWifi: value),
                  ),
                ),
                _buildSwitchTile(
                  'Connect on Mobile Data',
                  'Auto-connect when using cellular',
                  vpn.connectOnMobileData,
                  (value) => settings.updateVpn(
                    vpn.copyWith(connectOnMobileData: value),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D1E33),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Preferred Server',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value: vpn.preferredServer,
                      dropdownColor: const Color(0xFF2A2B40),
                      isExpanded: true,
                      underline: Container(),
                      items: const [
                        DropdownMenuItem(
                            value: 'auto', child: Text('Auto (Fastest)')),
                        DropdownMenuItem(
                            value: 'us', child: Text('United States')),
                        DropdownMenuItem(
                            value: 'uk', child: Text('United Kingdom')),
                        DropdownMenuItem(value: 'de', child: Text('Germany')),
                        DropdownMenuItem(value: 'jp', child: Text('Japan')),
                        DropdownMenuItem(
                            value: 'au', child: Text('Australia')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          settings.updateVpn(
                            vpn.copyWith(preferredServer: value),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSwitchTile(
                'Kill Switch',
                'Block internet if VPN disconnects',
                vpn.killSwitchEnabled,
                (value) => settings.updateVpn(
                  vpn.copyWith(killSwitchEnabled: value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF00D9FF),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const DuotoneIcon('danger_triangle', color: Colors.orange, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'These settings are for advanced users. Incorrect configuration may cause the app to stop working.',
                        style: TextStyle(
                          color: Colors.orange[300],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSwitchTile(
                'Use Custom Server',
                'Connect to a custom API server',
                api.useCustomServer,
                (value) => settings.updateApi(
                  api.copyWith(useCustomServer: value),
                ),
              ),
              if (api.useCustomServer) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1E33),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server URL',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _urlController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'https://api.example.com',
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          filled: true,
                          fillColor: const Color(0xFF2A2B40),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
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
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D1E33),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'API Key',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiKeyController,
                        style: const TextStyle(color: Colors.white),
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'Enter API key',
                          hintStyle: TextStyle(color: Colors.grey[600]),
                          filled: true,
                          fillColor: const Color(0xFF2A2B40),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
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
              const SizedBox(height: 16),
              _buildSwitchTile(
                'WebSocket Connection',
                'Enable real-time updates',
                api.enableWebSocket,
                (value) => settings.updateApi(
                  api.copyWith(enableWebSocket: value),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D1E33),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection Timeout',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: api.connectionTimeout,
                      dropdownColor: const Color(0xFF2A2B40),
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
                icon: const DuotoneIcon('wi_fi_router', color: Colors.black, size: 20),
                label: const Text('Test Connection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D9FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF00D9FF),
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
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Persistence Scanner',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const DuotoneIcon('info_circle', color: Colors.blue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Configure which persistence mechanisms to scan and how often to check for suspicious items.',
                    style: TextStyle(color: Colors.blue[300], fontSize: 13),
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
            (v) => setState(() => _autoScanOnStartup = v),
          ),
          if (_autoScanOnStartup) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1D1E33),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scan Interval', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: _scanIntervalHours,
                    dropdownColor: const Color(0xFF2A2B40),
                    isExpanded: true,
                    underline: Container(),
                    items: const [
                      DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                      DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
                      DropdownMenuItem(value: 24, child: Text('Daily')),
                      DropdownMenuItem(value: 168, child: Text('Weekly')),
                    ],
                    onChanged: (v) => setState(() => _scanIntervalHours = v ?? 24),
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
            (v) => setState(() => _scanLaunchAgents = v),
          ),
          _buildSwitchTile(
            'Launch Daemons',
            'System launch daemons',
            _scanLaunchDaemons,
            (v) => setState(() => _scanLaunchDaemons = v),
          ),
          _buildSwitchTile(
            'Login Items',
            'Apps that open at login',
            _scanLoginItems,
            (v) => setState(() => _scanLoginItems = v),
          ),
          _buildSwitchTile(
            'Kernel Extensions',
            'System extensions and drivers',
            _scanKernelExtensions,
            (v) => setState(() => _scanKernelExtensions = v),
          ),
          _buildSwitchTile(
            'Browser Extensions',
            'Safari, Chrome, Firefox extensions',
            _scanBrowserExtensions,
            (v) => setState(() => _scanBrowserExtensions = v),
          ),
          _buildSwitchTile(
            'Cron Jobs',
            'Scheduled tasks',
            _scanCronJobs,
            (v) => setState(() => _scanCronJobs = v),
          ),
          const SizedBox(height: 24),

          // Advanced settings
          _buildSectionHeader('Advanced'),
          _buildSwitchTile(
            'Deep Scan',
            'More thorough scanning (slower)',
            _deepScan,
            (v) => setState(() => _deepScan = v),
          ),
          _buildSwitchTile(
            'Hash Verification',
            'Compute file hashes for threat intel',
            _hashVerification,
            (v) => setState(() => _hashVerification = v),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(color: Colors.grey[400], fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF00D9FF),
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Platform-specific permissions
          if (Platform.isMacOS) ..._buildMacOSPermissions(context),
          if (Platform.isLinux) ..._buildLinuxPermissions(context),
          if (Platform.isWindows) ..._buildWindowsPermissions(context),
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
        statusColor: Colors.orange,
        instructions: [
          '1. Open System Settings',
          '2. Go to Privacy & Security → Full Disk Access',
          '3. Click the + button and add OrbGuard',
          '4. Restart OrbGuard for changes to take effect',
        ],
        onGrant: () => _openMacOSSettings('x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles'),
      ),
      const SizedBox(height: 16),

      // Automation
      _buildPermissionCard(
        context,
        icon: 'settings',
        title: 'Automation',
        description: 'Allows scanning of Folder Actions and other AppleScript-based persistence.',
        status: 'Recommended',
        statusColor: Colors.blue,
        instructions: [
          '1. Open System Settings',
          '2. Go to Privacy & Security → Automation',
          '3. Enable OrbGuard to control System Events',
        ],
        onGrant: () => _openMacOSSettings('x-apple.systempreferences:com.apple.preference.security?Privacy_Automation'),
      ),
      const SizedBox(height: 16),

      // Accessibility (optional)
      _buildPermissionCard(
        context,
        icon: 'eye',
        title: 'Accessibility',
        description: 'Optional - enables monitoring of input methods and accessibility-based persistence.',
        status: 'Optional',
        statusColor: Colors.grey,
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
          color: Colors.green.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const DuotoneIcon('check_circle', color: Colors.green, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'OrbGuard is notarized by Apple and does not require disabling Gatekeeper.',
                style: TextStyle(color: Colors.green[300], fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 32),
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
        statusColor: Colors.orange,
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
      const SizedBox(height: 16),

      // SELinux info
      _buildPermissionCard(
        context,
        icon: 'shield',
        title: 'SELinux/AppArmor',
        description: 'If SELinux or AppArmor is enabled, you may need to configure a policy for OrbGuard.',
        status: 'If Enabled',
        statusColor: Colors.blue,
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
      const SizedBox(height: 16),

      // File permissions
      _buildPermissionCard(
        context,
        icon: 'folder',
        title: 'File System Access',
        description: 'OrbGuard needs read access to various system directories.',
        status: 'Required',
        statusColor: Colors.orange,
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
      const SizedBox(height: 32),
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
        statusColor: Colors.orange,
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
      const SizedBox(height: 16),

      // Windows Security
      _buildPermissionCard(
        context,
        icon: 'shield',
        title: 'Windows Security Exception',
        description: 'Add OrbGuard to Windows Security exclusions to prevent false positives.',
        status: 'Recommended',
        statusColor: Colors.blue,
        instructions: [
          '1. Open Windows Security',
          '2. Go to Virus & threat protection',
          '3. Click "Manage settings" under Virus & threat protection settings',
          '4. Scroll to Exclusions and click "Add or remove exclusions"',
          '5. Add the OrbGuard installation folder',
        ],
        onGrant: () => _openWindowsSettings('windowsdefender:'),
      ),
      const SizedBox(height: 16),

      // Registry access
      _buildPermissionCard(
        context,
        icon: 'key',
        title: 'Registry Access',
        description: 'OrbGuard scans various registry locations for persistence mechanisms.',
        status: 'Auto-granted',
        statusColor: Colors.green,
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
      const SizedBox(height: 32),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
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
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instructions:',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...instructions.map((instruction) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    instruction,
                    style: TextStyle(
                      color: Colors.grey[400],
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
                icon: const DuotoneIcon('settings', color: Colors.black, size: 18),
                label: const Text('Open Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D9FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
