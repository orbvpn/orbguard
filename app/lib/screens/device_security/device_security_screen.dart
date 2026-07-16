// Device Security Screen
// Anti-theft features: locate, lock, wipe, ring, SIM monitoring

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/victim_safety_notice.dart';
import '../../providers/device_security_provider.dart';
import '../../services/device_agent/device_agent.dart' show AgentDisplayMessage;

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
          actions: [
            // Duress escape — leaves this sensitive view for the neutral home.
            const QuickExitAction(),
            if (provider.status.isLost || provider.status.isStolen)
              GestureDetector(
                onTap: () => provider.markAsRecovered(),
                child: DuotoneIcon('check_circle', size: 22, color: AppColors.accentInk),
              ),
          ],
          tabs: [
            GlassTab(
              label: 'Status',
              iconPath: 'shield',
              content: provider.isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
                  : _buildStatusTab(provider),
            ),
            GlassTab(
              label: 'Anti-Theft',
              iconPath: 'smartphone',
              content: provider.isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
                  : _buildAntiTheftTab(provider),
            ),
            GlassTab(
              label: 'Location',
              iconPath: 'settings',
              content: provider.isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
                  : _buildLocationTab(provider),
            ),
            GlassTab(
              label: 'SIM',
              iconPath: 'chart',
              content: provider.isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
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
    final statusInk = status.isStolen
        ? AppColors.errorInk
        : status.isLost
            ? AppColors.secondaryInk
            : AppColors.accentInk;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Status Card
          GlassCard(
            margin: EdgeInsets.zero,
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
                              color: statusInk,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (status.lastSeen != null)
                            Text(
                              'Last seen ${_formatTime(status.lastSeen!)}',
                              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
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
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Mark Lost', maxLines: 1),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.secondaryInk,
                            side: BorderSide(color: AppColors.secondaryInk),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmMarkStolen(context, provider),
                          icon: DuotoneIcon('danger_circle', size: 18),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Mark Stolen', maxLines: 1),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.errorInk,
                            side: BorderSide(color: AppColors.errorInk),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
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

          // Initialization / API errors — surfaced, never swallowed.
          if (provider.error != null) ...[
            _buildErrorCard(provider),
            const SizedBox(height: 24),
          ],

          // Owner message pushed via remote "message" command.
          if (provider.agentDisplayMessage != null) ...[
            _buildOwnerMessageCard(provider.agentDisplayMessage!),
            const SizedBox(height: 24),
          ],

          // On-device agent state (real lifecycle, honest unavailability).
          _buildAgentCard(provider),
          const SizedBox(height: 24),

          // Security Score
          _buildSecurityScoreCard(status.securityScore),
          const SizedBox(height: 24),

          // Quick Actions
          Text(
            'Quick Actions',
            style: BrandText.title(size: 18),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              _buildActionButton(
                svgIcon: 'map_point',
                label: 'Locate',
                color: AppColors.accentInk,
                isLoading: provider.isLocating,
                onPressed: () => provider.locateDevice(),
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                svgIcon: 'lock',
                label: 'Lock',
                color: AppColors.chartColors[4],
                isLoading: provider.isSendingCommand,
                onPressed: () => _showLockDialog(context, provider),
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                svgIcon: 'bell',
                label: 'Ring',
                color: AppColors.secondaryInk,
                isLoading: provider.isSendingCommand,
                onPressed: () => provider.ringDevice(),
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                svgIcon: 'trash_bin_trash',
                label: 'Wipe',
                color: AppColors.errorInk,
                isLoading: provider.isSendingCommand,
                onPressed: () => _showWipeDialog(context, provider),
              ),
            ],
          ),

          // Issued command lifecycle (pending -> executed/failed).
          if (provider.issuedCommands.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Recent Commands',
              style: BrandText.title(size: 18),
            ),
            const SizedBox(height: 12),
            ...provider.issuedCommands.take(5).map(_buildCommandCard),
          ],

          // Vulnerabilities
          if (status.vulnerabilities.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'OS Vulnerabilities',
                  style: BrandText.title(size: 18),
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

  Widget _buildSecurityScoreCard(int? score) {
    // Score is null until the backend has actually computed it — shown as
    // an explicit "not assessed" state rather than a fabricated 100.
    final color = score == null
        ? context.colors.onSurfaceVariant.withValues(alpha: 0.7)
        : score >= 80
            ? AppColors.accentInk
            : score >= 50
                ? GlassTheme.warningColor
                : GlassTheme.errorColor;
    final ink = score == null
        ? context.colors.onSurfaceVariant.withValues(alpha: 0.7)
        : score >= 80
            ? AppColors.accentInk
            : score >= 50
                ? AppColors.secondaryInk
                : AppColors.errorInk;

    return GlassCard(
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score == null ? 0 : score / 100,
                  strokeWidth: 6,
                  backgroundColor: context.colors.onSurface.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  score == null ? '—' : '$score',
                  style: BrandText.heading(size: 20, color: ink),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Security Score',
                  style: BrandText.title(),
                ),
                const SizedBox(height: 4),
                Text(
                  score == null
                      ? 'Not assessed yet — run a scan'
                      : score >= 80
                          ? 'Your device is well protected'
                          : score >= 50
                              ? 'Some security improvements needed'
                              : 'Your device needs attention',
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
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

  Widget _buildErrorCard(DeviceSecurityProvider provider) {
    return GlassCard(
      margin: EdgeInsets.zero,
      tintColor: GlassTheme.errorColor,
      child: Row(
        children: [
          DuotoneIcon('danger_circle', size: 22, color: AppColors.errorInk),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.error!,
              style: TextStyle(color: context.colors.onSurface, fontSize: 13),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: context.colors.onSurfaceVariant),
            onPressed: provider.clearError,
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerMessageCard(AgentDisplayMessage message) {
    return GlassCard(
      margin: EdgeInsets.zero,
      tintColor: GlassTheme.primaryAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon('chat_dots', size: 20, color: AppColors.accentInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                _formatTime(message.receivedAt),
                style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
          if (message.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message.message,
              style: TextStyle(color: context.colors.onSurface.withValues(alpha: 0.8), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAgentCard(DeviceSecurityProvider provider) {
    final running = provider.agentRunning;
    final color = running ? GlassTheme.successColor : GlassTheme.warningColor;
    final ink = running ? AppColors.accentInk : AppColors.secondaryInk;

    Widget statusLine(String label, String? value) {
      if (value == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(color: context.colors.onSurface.withValues(alpha: 0.8), fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(icon: 'shield', color: color, size: 40, iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      running ? 'Anti-Theft Agent Active' : 'Anti-Theft Agent Stopped',
                      style: TextStyle(color: ink, fontWeight: FontWeight.bold),
                    ),
                    if (provider.agentLastPollAt != null)
                      Text(
                        'Last check ${_formatTime(provider.agentLastPollAt!)}',
                        style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
                      ),
                  ],
                ),
              ),
              if (provider.status.pendingCommands > 0)
                GlassBadge(
                  text: '${provider.status.pendingCommands} pending',
                  color: GlassTheme.warningColor,
                ),
            ],
          ),
          statusLine('Location', provider.agentLocationStatus),
          statusLine('SIM', provider.agentSimStatus),
          statusLine('Background', provider.agentBackgroundStatus),
          statusLine('Agent error', provider.agentLastError),
        ],
      ),
    );
  }

  Widget _buildCommandCard(IssuedCommand cmd) {
    final color = switch (cmd.status) {
      CommandStatus.executed => GlassTheme.successColor,
      CommandStatus.failed || CommandStatus.expired => GlassTheme.errorColor,
      _ => GlassTheme.warningColor,
    };
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(icon: 'bolt_circle', color: color, size: 36, iconSize: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cmd.command.displayName,
                  style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500),
                ),
                if (cmd.detail != null)
                  Text(
                    cmd.detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
                  ),
                Text(
                  _formatTime(cmd.issuedAt),
                  style: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 10),
                ),
              ],
            ),
          ),
          GlassBadge(text: cmd.status.displayName, color: color, fontSize: 10),
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
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVulnerabilityCard(OSVulnerability vuln) {
    final severityColor = vuln.severity == 'critical'
        ? AppColors.severityCritical
        : vuln.severity == 'high'
            ? AppColors.severityHigh
            : AppColors.severityMedium;

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
                      style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      vuln.title,
                      style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
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
            style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (vuln.isExploited) ...[
                const GlassBadge(
                  text: 'EXPLOITED IN THE WILD',
                  color: GlassTheme.errorColor,
                  fontSize: 9,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  'Affects ${vuln.affectedVersions} · CVSS ${vuln.cvssScore.toStringAsFixed(1)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
                ),
              ),
            ],
          ),
          if (vuln.fixedVersion != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                DuotoneIcon('refresh', size: 14, color: AppColors.secondaryInk),
                const SizedBox(width: 4),
                Text(
                  'Fixed in ${vuln.fixedVersion}',
                  style: TextStyle(
                    color: AppColors.secondaryInk,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Anti-Theft Settings',
            style: BrandText.title(size: 18),
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
            color: AppColors.chartColors[4],
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
            color: AppColors.info,
          ),
          _buildSettingsTile(
            svgIcon: 'object_scan',
            title: 'Thief Selfie',
            subtitle: 'Take photo after failed unlock attempts',
            value: settings.thiefSelfieEnabled,
            onChanged: (v) => provider.updateSettings(settings.copyWith(thiefSelfieEnabled: v)),
            color: AppColors.severityCritical,
          ),

          const SizedBox(height: 24),

          // Max unlock attempts
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Failed Unlock Attempts Before Action',
                  style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500),
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
                        inactiveColor: context.colors.outline,
                        onChanged: (v) => provider.updateSettings(
                          settings.copyWith(maxUnlockAttempts: v.toInt()),
                        ),
                      ),
                    ),
                    Text(
                      '${settings.maxUnlockAttempts}',
                      style: TextStyle(color: AppColors.accentInk, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Thief selfies
          if (provider.thiefSelfies.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Captured Photos',
              style: BrandText.title(size: 18),
            ),
            const SizedBox(height: 12),
            GlassCard(
              tintColor: GlassTheme.errorColor,
              child: Row(
                children: [
                  DuotoneIcon('camera', size: 24, color: AppColors.errorInk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${provider.thiefSelfies.length} photos captured',
                      style: TextStyle(color: context.colors.onSurface),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showSelfiesDialog(context, provider),
                    child: const Text('View'),
                  ),
                ],
              ),
            ),
          ] else if (settings.thiefSelfieEnabled) ...[
            // Honest empty state: the feature is armed but nothing has been
            // captured — never a placeholder photo.
            const SizedBox(height: 24),
            Text(
              'Captured Photos',
              style: BrandText.title(size: 18),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Row(
                children: [
                  DuotoneIcon('camera', size: 24, color: context.colors.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No selfies captured. A photo is taken after '
                      'repeated failed unlock attempts and will appear here.',
                      style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 13),
                    ),
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
                Text(title, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500)),
                Text(
                  subtitle,
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: color,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationTab(DeviceSecurityProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current location
          if (provider.status.lastKnownLocation != null) ...[
            Text(
              'Last Known Location',
              style: BrandText.title(size: 18),
            ),
            const SizedBox(height: 12),
            _buildLocationCard(provider.status.lastKnownLocation!, isCurrent: true),
          ],

          // Locate button
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: provider.isLocating ? null : () => provider.locateDevice(),
              icon: provider.isLocating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Brand.onLime),
                    )
                  : DuotoneIcon('map_point', size: 20),
              label: Text(provider.isLocating ? 'Locating...' : 'Locate Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Brand.onLime,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          // Location history
          if (provider.locationHistory.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Location History',
              style: BrandText.title(size: 18),
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
      margin: isCurrent ? EdgeInsets.zero : null,
      tintColor: isCurrent ? GlassTheme.primaryAccent : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: 'map_point',
                color: isCurrent ? GlassTheme.primaryAccent : context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.address ?? 'Unknown Address',
                      style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
                      style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12, fontFamily: 'monospace'),
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
              DuotoneIcon('clock_circle', size: 14, color: context.colors.onSurfaceVariant.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                _formatTime(location.timestamp),
                style: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11),
              ),
              if (location.accuracy != null) ...[
                const SizedBox(width: 16),
                DuotoneIcon('map_point', size: 14, color: context.colors.onSurfaceVariant.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text(
                  '±${location.accuracy!.toStringAsFixed(0)}m',
                  style: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Honest monitoring state (e.g. permission missing, unsupported
          // platform) straight from the agent.
          if (provider.agentSimStatus != null) ...[
            GlassCard(
              margin: EdgeInsets.zero,
              child: Row(
                children: [
                  DuotoneIcon('sim_card', size: 20, color: AppColors.accentInk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      provider.agentSimStatus!,
                      style: TextStyle(color: context.colors.onSurface.withValues(alpha: 0.8), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Current SIMs (active subscriptions reported by this device).
          if (provider.currentSims.isNotEmpty) ...[
            Text(
              'Current SIM Cards',
              style: BrandText.title(size: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Android does not expose real ICCIDs to apps — entries marked '
              '"sub:" are stable subscription fingerprints used for change '
              'detection.',
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
            ),
            const SizedBox(height: 12),
            ...provider.currentSims.map((sim) => _buildSimCard(
                  sim,
                  isCurrent: sim.isActive,
                  provider: provider,
                )),
          ],

          // SIM change events with backend risk assessment.
          if (provider.simEvents.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'SIM Change Events',
              style: BrandText.title(size: 18),
            ),
            const SizedBox(height: 12),
            ...provider.simEvents.map(_buildSimEventCard),
          ],

          if (provider.simEvents.isEmpty && provider.currentSims.isEmpty)
            _buildEmptyState(
              svgIcon: 'sim_card',
              title: 'No SIM Data',
              subtitle: 'SIM card information will appear here once the '
                  'agent has reported it',
            ),
        ],
      ),
    );
  }

  Widget _buildSimEventCard(SIMChangeEvent event) {
    final riskColor = switch (event.riskLevel) {
      'critical' => AppColors.severityCritical,
      'high' => AppColors.severityHigh,
      'medium' => AppColors.severityMedium,
      _ => AppColors.success,
    };
    final description = switch (event.eventType) {
      'inserted' => 'SIM inserted${event.newSim?.carrier != null ? ' (${event.newSim!.carrier})' : ''}',
      'removed' => 'SIM removed${event.oldSim?.carrier != null ? ' (${event.oldSim!.carrier})' : ''}',
      'swapped' => 'SIM swapped'
          '${event.oldSim?.carrier != null ? ' from ${event.oldSim!.carrier}' : ''}'
          '${event.newSim?.carrier != null ? ' to ${event.newSim!.carrier}' : ''}',
      'changed' => 'SIM changed in slot',
      _ => 'SIM event: ${event.eventType}',
    };

    return GlassCard(
      tintColor: event.riskLevel == 'critical' || event.riskLevel == 'high'
          ? riskColor
          : null,
      child: Row(
        children: [
          GlassSvgIconBox(icon: 'sim_card', color: riskColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500),
                ),
                Text(
                  _formatTime(event.detectedAt),
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
          GlassBadge(
            text: event.riskLevel.toUpperCase(),
            color: riskColor,
            fontSize: 10,
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
                    : context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sim.carrier ?? 'Unknown Carrier',
                  style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500),
                ),
                Text(
                  sim.iccid,
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11, fontFamily: 'monospace'),
                ),
                if (sim.phoneNumber != null)
                  Text(
                    sim.phoneNumber!,
                    style: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 12),
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
            DuotoneIcon(svgIcon, size: 64, color: AppColors.accentInk.withAlpha(128)),
            const SizedBox(height: 16),
            Text(
              title,
              style: BrandText.title(size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: context.colors.onSurfaceVariant),
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
        backgroundColor: context.colors.surface,
        title: Text('Lock Device', style: TextStyle(color: context.colors.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter a message to display on the lock screen:',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: TextStyle(color: context.colors.onSurface),
              decoration: InputDecoration(
                hintText: 'e.g., "Call +1234567890 if found"',
                hintStyle: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall)),
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
            child: Text('Lock', style: TextStyle(color: AppColors.accentInk)),
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
        backgroundColor: context.colors.surface,
        title: Text('Wipe Device', style: TextStyle(color: AppColors.errorInk)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WARNING: This will permanently erase ALL data on the device. This action cannot be undone.',
              style: TextStyle(color: AppColors.errorInk),
            ),
            const SizedBox(height: 16),
            Text(
              'Type "WIPE" to confirm:',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: TextStyle(color: context.colors.onSurface),
              decoration: InputDecoration(
                hintText: 'WIPE',
                hintStyle: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall)),
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
            child: Text('Wipe Device', style: TextStyle(color: AppColors.errorInk)),
          ),
        ],
      ),
    );
  }

  void _confirmMarkLost(BuildContext context, DeviceSecurityProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Mark as Lost', style: TextStyle(color: context.colors.onSurface)),
        content: Text(
          'This will enable tracking features and help locate your device.',
          style: TextStyle(color: context.colors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.markAsLost();
            },
            child: Text('Mark Lost', style: TextStyle(color: AppColors.secondaryInk)),
          ),
        ],
      ),
    );
  }

  void _confirmMarkStolen(BuildContext context, DeviceSecurityProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Mark as Stolen', style: TextStyle(color: context.colors.onSurface)),
        content: Text(
          'This will activate all anti-theft features and enable continuous tracking.',
          style: TextStyle(color: context.colors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.markAsStolen();
            },
            child: Text('Mark Stolen', style: TextStyle(color: AppColors.errorInk)),
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
        backgroundColor: context.colors.surface,
        title: Text('Enable Remote Wipe', style: TextStyle(color: AppColors.errorInk)),
        content: Text(
          'WARNING: Enabling this allows remote erasure of all data. Only enable if you understand the risks.',
          style: TextStyle(color: context.colors.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.updateSettings(provider.settings.copyWith(wipeEnabled: true));
            },
            child: Text('Enable', style: TextStyle(color: AppColors.errorInk)),
          ),
        ],
      ),
    );
  }

  void _showSelfiesDialog(BuildContext context, DeviceSecurityProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Captured Photos', style: TextStyle(color: context.colors.onSurface)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: provider.thiefSelfies.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final selfie = provider.thiefSelfies[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSelfieImage(selfie),
                  const SizedBox(height: 4),
                  Text(
                    'Trigger: ${selfie.triggerType}'
                    '${selfie.capturedAt != null ? ' · ${_formatTime(selfie.capturedAt!)}' : ''}',
                    style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfieImage(ThiefSelfie selfie) {
    // Selfies are uploaded as base64 data URIs (see SelfieCapture); render
    // them inline. Anything else is shown as an unrenderable reference —
    // never a placeholder image pretending to be the capture.
    const dataUriPrefix = 'data:image/jpeg;base64,';
    if (selfie.imageUrl.startsWith(dataUriPrefix)) {
      try {
        final bytes = base64Decode(selfie.imageUrl.substring(dataUriPrefix.length));
        return ClipRRect(
          borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
          child: Image.memory(bytes, fit: BoxFit.cover),
        );
      } catch (_) {
        // fall through to the unrenderable notice
      }
    }
    return Text(
      'Image stored remotely (${selfie.imageUrl.length > 60 ? '${selfie.imageUrl.substring(0, 60)}…' : selfie.imageUrl}) '
      '— cannot be rendered inline',
      style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
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
