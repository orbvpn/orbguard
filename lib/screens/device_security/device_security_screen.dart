/// Device Security Screen
/// Anti-theft features: locate, lock, wipe, ring, SIM monitoring

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/device_security_provider.dart';

class DeviceSecurityScreen extends StatefulWidget {
  const DeviceSecurityScreen({super.key});

  @override
  State<DeviceSecurityScreen> createState() => _DeviceSecurityScreenState();
}

class _DeviceSecurityScreenState extends State<DeviceSecurityScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceSecurityProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceSecurityProvider>(
      builder: (context, provider, _) {
        return GlassTabPage(
          title: 'Device Security',
          hasSearch: true,
          searchHint: 'Search...',
          headerContent: (provider.status.isLost || provider.status.isStolen)
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: DuotoneIcon('check_circle', size: 24, color: GlassTheme.successColor),
                        tooltip: 'Mark as Recovered',
                        onPressed: () => provider.markAsRecovered(),
                      ),
                    ],
                  ),
                )
              : null,
          tabs: [
            GlassTab(
              label: 'Status',
              iconPath: 'shield',
              content: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
                  : _buildStatusTab(provider),
            ),
            GlassTab(
              label: 'Anti-Theft',
              iconPath: 'smartphone',
              content: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
                  : _buildAntiTheftTab(provider),
            ),
            GlassTab(
              label: 'Location',
              iconPath: 'settings',
              content: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
                  : _buildLocationTab(provider),
            ),
            GlassTab(
              label: 'SIM',
              iconPath: 'chart',
              content: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
                  : _buildSimTab(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusTab(DeviceSecurityProvider provider) {
    final status = provider.status;
    final statusColor = status.isStolen
        ? GlassTheme.errorColor
        : status.isLost
            ? GlassTheme.warningColor
            : GlassTheme.successColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Status Card
          GlassCard(
            tintColor: statusColor,
            child: Column(
              children: [
                Row(
                  children: [
                    GlassSvgIconBox(
                      icon: status.isStolen
                          ? 'danger_circle'
                          : status.isLost
                              ? 'object_scan'
                              : 'check_circle',
                      color: statusColor,
                      size: 56,
                      iconSize: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status.isStolen
                                ? 'Device Reported Stolen'
                                : status.isLost
                                    ? 'Device Marked Lost'
                                    : 'Device Secure',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (status.lastSeen != null)
                            Text(
                              'Last seen ${_formatTime(status.lastSeen!)}',
                              style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!status.isLost && !status.isStolen) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmMarkLost(context, provider),
                          icon: DuotoneIcon('object_scan', size: 18),
                          label: const Text('Mark Lost'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GlassTheme.warningColor,
                            side: const BorderSide(color: GlassTheme.warningColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmMarkStolen(context, provider),
                          icon: DuotoneIcon('danger_circle', size: 18),
                          label: const Text('Mark Stolen'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GlassTheme.errorColor,
                            side: const BorderSide(color: GlassTheme.errorColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Security Score
          _buildSecurityScoreCard(status.securityScore),
          const SizedBox(height: 24),

          // Quick Actions
          const Text(
            'Quick Actions',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              _buildActionButton(
                svgIcon: 'map_point',
                label: 'Locate',
                color: GlassTheme.primaryAccent,
                isLoading: provider.isLocating,
                onPressed: () => provider.locateDevice(),
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                svgIcon: 'lock',
                label: 'Lock',
                color: const Color(0xFF9C27B0),
                isLoading: provider.isSendingCommand,
                onPressed: () => _showLockDialog(context, provider),
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                svgIcon: 'bell',
                label: 'Ring',
                color: GlassTheme.warningColor,
                isLoading: provider.isSendingCommand,
                onPressed: () => provider.ringDevice(),
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                svgIcon: 'trash_bin_trash',
                label: 'Wipe',
                color: GlassTheme.errorColor,
                isLoading: provider.isSendingCommand,
                onPressed: () => _showWipeDialog(context, provider),
              ),
            ],
          ),

          // Vulnerabilities
          if (status.vulnerabilities.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'OS Vulnerabilities',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                GlassBadge(
                  text: '${status.vulnerabilities.length} found',
                  color: GlassTheme.errorColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...status.vulnerabilities.map((vuln) => _buildVulnerabilityCard(vuln)),
          ],
        ],
      ),
    );
  }

  Widget _buildSecurityScoreCard(int score) {
    final color = score >= 80
        ? GlassTheme.successColor
        : score >= 50
            ? GlassTheme.warningColor
            : GlassTheme.errorColor;

    return GlassCard(
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 6,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  '$score',
                  style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Security Score',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 80
                      ? 'Your device is well protected'
                      : score >= 50
                          ? 'Some security improvements needed'
                          : 'Your device needs attention',
                  style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.read<DeviceSecurityProvider>().auditVulnerabilities(),
            child: const Text('Scan'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String svgIcon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    return Expanded(
      child: GlassContainer(
        onTap: isLoading ? null : onPressed,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            if (isLoading)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              DuotoneIcon(svgIcon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVulnerabilityCard(OSVulnerability vuln) {
    final severityColor = vuln.severity == 'critical'
        ? GlassTheme.errorColor
        : vuln.severity == 'high'
            ? const Color(0xFFFF5722)
            : GlassTheme.warningColor;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(icon: 'bug', color: severityColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vuln.cveId,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      vuln.title,
                      style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 12),
                    ),
                  ],
                ),
              ),
              GlassBadge(text: vuln.severity.toUpperCase(), color: severityColor, fontSize: 10),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            vuln.description,
            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 13),
          ),
          if (vuln.fixedVersion != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                DuotoneIcon(
                  vuln.isPatched ? 'check_circle' : 'refresh',
                  size: 14,
                  color: vuln.isPatched ? GlassTheme.successColor : GlassTheme.warningColor,
                ),
                const SizedBox(width: 4),
                Text(
                  vuln.isPatched ? 'Patched' : 'Update to ${vuln.fixedVersion}',
                  style: TextStyle(
                    color: vuln.isPatched ? GlassTheme.successColor : GlassTheme.warningColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAntiTheftTab(DeviceSecurityProvider provider) {
    final settings = provider.settings;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Anti-Theft Settings',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          _buildSettingsTile(
            svgIcon: 'map_point',
            title: 'Remote Locate',
            subtitle: 'Allow remote location tracking',
            value: settings.locateEnabled,
            onChanged: (v) => provider.updateSettings(settings.copyWith(locateEnabled: v)),
            color: GlassTheme.primaryAccent,
          ),
          _buildSettingsTile(
            svgIcon: 'lock',
            title: 'Remote Lock',
            subtitle: 'Allow remote device locking',
            value: settings.lockEnabled,
            onChanged: (v) => provider.updateSettings(settings.copyWith(lockEnabled: v)),
            color: const Color(0xFF9C27B0),
          ),
          _buildSettingsTile(
            svgIcon: 'bell',
            title: 'Remote Ring',
            subtitle: 'Allow remote sound alarm',
            value: settings.ringEnabled,
            onChanged: (v) => provider.updateSettings(settings.copyWith(ringEnabled: v)),
            color: GlassTheme.warningColor,
          ),
          _buildSettingsTile(
            svgIcon: 'trash_bin_trash',
            title: 'Remote Wipe',
            subtitle: 'Allow remote data erasure (dangerous)',
            value: settings.wipeEnabled,
            onChanged: (v) => _confirmEnableWipe(context, provider, v),
            color: GlassTheme.errorColor,
          ),
          _buildSettingsTile(
            svgIcon: 'sim_card',
            title: 'SIM Monitoring',
            subtitle: 'Alert when SIM card is changed',
            value: settings.simMonitoringEnabled,
            onChanged: (v) => provider.updateSettings(settings.copyWith(simMonitoringEnabled: v)),
            color: const Color(0xFF2196F3),
          ),
          _buildSettingsTile(
            svgIcon: 'object_scan',
            title: 'Thief Selfie',
            subtitle: 'Take photo after failed unlock attempts',
            value: settings.thiefSelfieEnabled,
            onChanged: (v) => provider.updateSettings(settings.copyWith(thiefSelfieEnabled: v)),
            color: const Color(0xFFFF5722),
          ),

          const SizedBox(height: 24),

          // Max unlock attempts
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Failed Unlock Attempts Before Action',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: settings.maxUnlockAttempts.toDouble(),
                        min: 3,
                        max: 10,
                        divisions: 7,
                        activeColor: GlassTheme.primaryAccent,
                        inactiveColor: Colors.white24,
                        onChanged: (v) => provider.updateSettings(
                          settings.copyWith(maxUnlockAttempts: v.toInt()),
                        ),
                      ),
                    ),
                    Text(
                      '${settings.maxUnlockAttempts}',
                      style: const TextStyle(color: GlassTheme.primaryAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Thief selfies
          if (provider.thiefSelfies.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Captured Photos',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GlassCard(
              tintColor: GlassTheme.errorColor,
              child: Row(
                children: [
                  DuotoneIcon('camera', size: 24, color: GlassTheme.errorColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${provider.thiefSelfies.length} photos captured',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('View'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required String svgIcon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color color,
  }) {
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(icon: svgIcon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: color,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationTab(DeviceSecurityProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current location
          if (provider.status.lastKnownLocation != null) ...[
            const Text(
              'Last Known Location',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildLocationCard(provider.status.lastKnownLocation!, isCurrent: true),
          ],

          // Locate button
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: provider.isLocating ? null : () => provider.locateDevice(),
              icon: provider.isLocating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : DuotoneIcon('map_point', size: 20),
              label: Text(provider.isLocating ? 'Locating...' : 'Locate Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          // Location history
          if (provider.locationHistory.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Location History',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...provider.locationHistory.take(10).map((loc) => _buildLocationCard(loc)),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationCard(DeviceLocation location, {bool isCurrent = false}) {
    return GlassCard(
      tintColor: isCurrent ? GlassTheme.primaryAccent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: 'map_point',
                color: isCurrent ? GlassTheme.primaryAccent : Colors.white54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.address ?? 'Unknown Address',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              if (isCurrent) const GlassBadge(text: 'Latest', color: GlassTheme.primaryAccent),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              DuotoneIcon('clock_circle', size: 14, color: Colors.white.withAlpha(102)),
              const SizedBox(width: 4),
              Text(
                _formatTime(location.timestamp),
                style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
              ),
              if (location.accuracy != null) ...[
                const SizedBox(width: 16),
                DuotoneIcon('map_point', size: 14, color: Colors.white.withAlpha(102)),
                const SizedBox(width: 4),
                Text(
                  '±${location.accuracy!.toStringAsFixed(0)}m',
                  style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimTab(DeviceSecurityProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current SIM
          if (provider.currentSIM != null) ...[
            const Text(
              'Current SIM Card',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildSimCard(provider.currentSIM!, isCurrent: true, provider: provider),
          ],

          // Trusted SIMs
          if (provider.trustedSIMs.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Trusted SIM Cards',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...provider.trustedSIMs.map((sim) => _buildSimCard(sim, provider: provider)),
          ],

          // SIM History
          if (provider.simHistory.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'SIM History',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...provider.simHistory.map((sim) => _buildSimCard(sim, provider: provider)),
          ],

          if (provider.simHistory.isEmpty && provider.currentSIM == null)
            _buildEmptyState(
              svgIcon: 'sim_card',
              title: 'No SIM Data',
              subtitle: 'SIM card information will appear here',
            ),
        ],
      ),
    );
  }

  Widget _buildSimCard(SIMInfo sim, {bool isCurrent = false, required DeviceSecurityProvider provider}) {
    return GlassCard(
      tintColor: sim.isTrusted ? GlassTheme.successColor : null,
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: 'sim_card',
            color: sim.isTrusted
                ? GlassTheme.successColor
                : isCurrent
                    ? GlassTheme.primaryAccent
                    : Colors.white54,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sim.carrier ?? 'Unknown Carrier',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                Text(
                  sim.iccid,
                  style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11, fontFamily: 'monospace'),
                ),
                if (sim.phoneNumber != null)
                  Text(
                    sim.phoneNumber!,
                    style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 12),
                  ),
              ],
            ),
          ),
          if (sim.isTrusted)
            const GlassBadge(text: 'Trusted', color: GlassTheme.successColor)
          else if (!sim.isTrusted)
            TextButton(
              onPressed: () => provider.addTrustedSIM(sim.iccid),
              child: const Text('Trust'),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required String svgIcon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon(svgIcon, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withAlpha(153)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showLockDialog(BuildContext context, DeviceSecurityProvider provider) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Lock Device', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter a message to display on the lock screen:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g., "Call +1234567890 if found"',
                hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.lockDevice(message: controller.text);
            },
            child: const Text('Lock', style: TextStyle(color: GlassTheme.primaryAccent)),
          ),
        ],
      ),
    );
  }

  void _showWipeDialog(BuildContext context, DeviceSecurityProvider provider) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Wipe Device', style: TextStyle(color: GlassTheme.errorColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'WARNING: This will permanently erase ALL data on the device. This action cannot be undone.',
              style: TextStyle(color: GlassTheme.errorColor),
            ),
            const SizedBox(height: 16),
            const Text(
              'Type "WIPE" to confirm:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'WIPE',
                hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text == 'WIPE') {
                Navigator.pop(context);
                provider.wipeDevice(confirmationCode: 'WIPE');
              }
            },
            child: const Text('Wipe Device', style: TextStyle(color: GlassTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  void _confirmMarkLost(BuildContext context, DeviceSecurityProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Mark as Lost', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will enable tracking features and help locate your device.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.markAsLost();
            },
            child: const Text('Mark Lost', style: TextStyle(color: GlassTheme.warningColor)),
          ),
        ],
      ),
    );
  }

  void _confirmMarkStolen(BuildContext context, DeviceSecurityProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Mark as Stolen', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will activate all anti-theft features and enable continuous tracking.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.markAsStolen();
            },
            child: const Text('Mark Stolen', style: TextStyle(color: GlassTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  void _confirmEnableWipe(BuildContext context, DeviceSecurityProvider provider, bool enable) {
    if (!enable) {
      provider.updateSettings(provider.settings.copyWith(wipeEnabled: false));
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Enable Remote Wipe', style: TextStyle(color: GlassTheme.errorColor)),
        content: const Text(
          'WARNING: Enabling this allows remote erasure of all data. Only enable if you understand the risks.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.updateSettings(provider.settings.copyWith(wipeEnabled: true));
            },
            child: const Text('Enable', style: TextStyle(color: GlassTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
