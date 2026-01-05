/// Settings Screen
/// Main settings and configuration screen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: const GlassAppBar(
        title: 'Settings',
        showBackButton: true,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Protection settings
              _buildSettingsSection(
                context,
                'Protection',
                Icons.shield,
                const Color(0xFF00D9FF),
                [
                  _buildSettingsTile(
                    'Protection Features',
                    'Enable/disable security features',
                    Icons.security,
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
                    Icons.radar,
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
                Icons.notifications,
                Colors.orange,
                [
                  _buildSettingsTile(
                    'Alert Preferences',
                    'Manage notification types',
                    Icons.notifications_active,
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
                Icons.vpn_lock,
                Colors.green,
                [
                  _buildSettingsTile(
                    'VPN Settings',
                    'Auto-connect and preferences',
                    Icons.vpn_key,
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
              // Privacy
              _buildSettingsSection(
                context,
                'Privacy & Security',
                Icons.privacy_tip,
                Colors.purple,
                [
                  _buildSettingsTile(
                    'Privacy Settings',
                    'Data sharing and app lock',
                    Icons.lock,
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
                Icons.settings,
                Colors.grey,
                [
                  _buildSettingsTile(
                    'API Configuration',
                    'Server and connection settings',
                    Icons.cloud,
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
                    Icons.restore,
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
                Icons.info,
                Colors.blue,
                [
                  _buildSettingsTile(
                    'App Version',
                    '1.0.0 (Build 1)',
                    Icons.info_outline,
                  ),
                  _buildSettingsTile(
                    'Terms of Service',
                    'View terms and conditions',
                    Icons.description,
                    onTap: () {},
                  ),
                  _buildSettingsTile(
                    'Privacy Policy',
                    'View privacy policy',
                    Icons.policy,
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
    IconData icon,
    Color color,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
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
    IconData icon, {
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.red : Colors.grey,
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
          ? const Icon(Icons.chevron_right, color: Colors.grey)
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
    return GlassScaffold(
      appBar: const GlassAppBar(
        title: 'Protection Features',
        showBackButton: true,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final protection = settings.protection;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoCard(
                'Configure which protection features are active. '
                'Disabling features may reduce security.',
                Icons.info_outline,
                Colors.blue,
              ),
              const SizedBox(height: 24),
              _buildSwitchTile(
                'SMS Protection',
                'Analyze SMS messages for threats',
                Icons.sms,
                protection.smsProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(smsProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'URL Protection',
                'Check URLs for malicious content',
                Icons.link,
                protection.urlProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(urlProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'QR Code Protection',
                'Scan QR codes for threats',
                Icons.qr_code_scanner,
                protection.qrProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(qrProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'App Security',
                'Monitor installed apps for risks',
                Icons.apps,
                protection.appSecurityEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(appSecurityEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Network Protection',
                'Monitor WiFi and network security',
                Icons.wifi_lock,
                protection.networkProtectionEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(networkProtectionEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Dark Web Monitoring',
                'Check for credential breaches',
                Icons.dark_mode,
                protection.darkWebMonitoringEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(darkWebMonitoringEnabled: value),
                ),
              ),
              const Divider(color: Colors.white10, height: 32),
              _buildSwitchTile(
                'Real-time Alerts',
                'Get instant threat notifications',
                Icons.notifications_active,
                protection.realTimeAlertsEnabled,
                (value) => settings.updateProtection(
                  protection.copyWith(realTimeAlertsEnabled: value),
                ),
              ),
              _buildSwitchTile(
                'Auto-block Threats',
                'Automatically block detected threats',
                Icons.block,
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

  Widget _buildInfoCard(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
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
    IconData icon,
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
        secondary: Icon(
          icon,
          color: value ? const Color(0xFF00D9FF) : Colors.grey,
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
    return GlassScaffold(
      appBar: const GlassAppBar(
        title: 'Notification Settings',
        showBackButton: true,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final notif = settings.notifications;
          return ListView(
            padding: const EdgeInsets.all(16),
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
                      const Icon(Icons.arrow_forward, color: Colors.grey),
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
    return GlassScaffold(
      appBar: const GlassAppBar(
        title: 'Privacy Settings',
        showBackButton: true,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final privacy = settings.privacy;
          return ListView(
            padding: const EdgeInsets.all(16),
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
                      leading: const Icon(Icons.download, color: Colors.grey),
                      title: const Text(
                        'Export Data',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Download all your data',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Data export started...')),
                        );
                      },
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    ListTile(
                      leading: const Icon(Icons.delete, color: Colors.red),
                      title: const Text(
                        'Delete All Data',
                        style: TextStyle(color: Colors.red),
                      ),
                      subtitle: Text(
                        'Permanently delete all stored data',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.grey),
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
    return GlassScaffold(
      appBar: const GlassAppBar(
        title: 'Scan Settings',
        showBackButton: true,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final scan = settings.scan;
          return ListView(
            padding: const EdgeInsets.all(16),
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
    return GlassScaffold(
      appBar: const GlassAppBar(
        title: 'VPN Settings',
        showBackButton: true,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final vpn = settings.vpn;
          return ListView(
            padding: const EdgeInsets.all(16),
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
    return GlassScaffold(
      appBar: const GlassAppBar(
        title: 'API Configuration',
        showBackButton: true,
      ),
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
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange),
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
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Testing connection...')),
                  );
                  // TODO: Test API connection
                  Future.delayed(const Duration(seconds: 1), () {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Connection successful!')),
                      );
                    }
                  });
                },
                icon: const Icon(Icons.network_check),
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
