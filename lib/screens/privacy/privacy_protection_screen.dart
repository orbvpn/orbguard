/// Privacy Protection Screen
/// Camera/microphone monitoring, clipboard protection, and tracker blocking

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/privacy_provider.dart';

class PrivacyProtectionScreen extends StatefulWidget {
  const PrivacyProtectionScreen({super.key});

  @override
  State<PrivacyProtectionScreen> createState() => _PrivacyProtectionScreenState();
}

class _PrivacyProtectionScreenState extends State<PrivacyProtectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrivacyProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PrivacyProvider>(
      builder: (context, provider, _) {
        return GlassTabPage(
          title: 'Privacy Protection',
          hasSearch: true,
          searchHint: 'Search permissions...',
          headerContent: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: DuotoneIcon(AppIcons.shield, size: 22, color: Colors.white),
                  onPressed: provider.isAuditing ? null : () => provider.runAudit(),
                  tooltip: 'Run Audit',
                ),
              ],
            ),
          ),
          tabs: [
            GlassTab(
              label: 'Overview',
              iconPath: 'shield',
              content: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
                  : _buildOverviewTab(provider),
            ),
            GlassTab(
              label: 'Camera/Mic',
              iconPath: 'camera',
              content: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
                  : _buildCameraMicTab(provider),
            ),
            GlassTab(
              label: 'Trackers',
              iconPath: 'forbidden',
              content: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
                  : _buildTrackersTab(provider),
            ),
            GlassTab(
              label: 'Events',
              iconPath: 'history',
              content: provider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
                  : _buildEventsTab(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOverviewTab(PrivacyProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy Score
          if (provider.lastAudit != null) _buildPrivacyScoreCard(provider.lastAudit!),
          const SizedBox(height: 24),

          // Quick Settings
          const Text(
            'Protection Settings',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          _buildSettingsTile(
            icon: AppIcons.camera,
            title: 'Camera Monitoring',
            subtitle: 'Get alerts when apps access camera',
            value: provider.cameraMonitoringEnabled,
            onChanged: provider.setCameraMonitoring,
            color: GlassTheme.primaryAccent,
          ),
          _buildSettingsTile(
            icon: AppIcons.microphone,
            title: 'Microphone Monitoring',
            subtitle: 'Get alerts when apps access microphone',
            value: provider.micMonitoringEnabled,
            onChanged: provider.setMicMonitoring,
            color: const Color(0xFFFF5722),
          ),
          _buildSettingsTile(
            icon: AppIcons.clipboard,
            title: 'Clipboard Protection',
            subtitle: 'Scan clipboard for threats',
            value: provider.clipboardProtectionEnabled,
            onChanged: provider.setClipboardProtection,
            color: const Color(0xFF9C27B0),
          ),
          _buildSettingsTile(
            icon: AppIcons.forbidden,
            title: 'Tracker Blocking',
            subtitle: 'Block known trackers and analytics',
            value: provider.trackerBlockingEnabled,
            onChanged: provider.setTrackerBlocking,
            color: GlassTheme.warningColor,
          ),

          const SizedBox(height: 24),

          // Stats
          if (provider.lastAudit != null) ...[
            const Text(
              'Privacy Stats',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatCard('Apps Audited', provider.lastAudit!.totalAppsAudited.toString(), GlassTheme.primaryAccent),
                const SizedBox(width: 12),
                _buildStatCard('Trackers Found', provider.lastAudit!.totalTrackers.toString(), GlassTheme.errorColor),
              ],
            ),
          ],

          // Recommendations
          if (provider.lastAudit != null && provider.lastAudit!.recommendations.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Recommendations',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...provider.lastAudit!.recommendations.map((rec) => GlassCard(
                  child: Row(
                    children: [
                      const GlassSvgIconBox(icon: AppIcons.lightbulb, color: GlassTheme.warningColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          rec,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildPrivacyScoreCard(PrivacyAuditResult audit) {
    final score = audit.privacyScore;
    final color = score >= 80
        ? GlassTheme.successColor
        : score >= 50
            ? GlassTheme.warningColor
            : GlassTheme.errorColor;

    return GlassCard(
      tintColor: color,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 8,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  '$score',
                  style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold),
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
                  'Privacy Score',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 80
                      ? 'Your privacy is well protected'
                      : score >= 50
                          ? 'Some privacy improvements needed'
                          : 'Your privacy needs attention',
                  style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required String icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color color,
  }) {
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(icon: icon, color: color),
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
            activeColor: GlassTheme.primaryAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraMicTab(PrivacyProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Camera Events
          Row(
            children: [
              DuotoneIcon(AppIcons.camera, color: GlassTheme.primaryAccent, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Recent Camera Access',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (provider.recentCameraEvents.isEmpty)
            _buildEmptyCard('No camera access recorded')
          else
            ...provider.recentCameraEvents.map((event) => _buildEventCard(event)),

          const SizedBox(height: 24),

          // Microphone Events
          Row(
            children: [
              DuotoneIcon(AppIcons.microphone, color: const Color(0xFFFF5722), size: 24),
              const SizedBox(width: 8),
              const Text(
                'Recent Microphone Access',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (provider.recentMicEvents.isEmpty)
            _buildEmptyCard('No microphone access recorded')
          else
            ...provider.recentMicEvents.map((event) => _buildEventCard(event)),

          // Background Access Warning
          if (provider.backgroundEvents.isNotEmpty) ...[
            const SizedBox(height: 24),
            GlassCard(
              tintColor: GlassTheme.errorColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DuotoneIcon(AppIcons.dangerTriangle, color: GlassTheme.errorColor, size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'Background Access Detected',
                        style: TextStyle(color: GlassTheme.errorColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${provider.backgroundEvents.length} apps accessed camera/mic in the background',
                    style: TextStyle(color: Colors.white.withAlpha(179)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return GlassCard(
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Colors.white.withAlpha(128)),
        ),
      ),
    );
  }

  Widget _buildEventCard(PrivacyEvent event) {
    final color = event.isBackground ? GlassTheme.errorColor : GlassTheme.primaryAccent;

    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: event.type == PrivacyEventType.cameraAccess ? AppIcons.camera : AppIcons.microphone,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.appName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                Text(
                  event.isBackground ? 'Background access' : 'Foreground access',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            _formatTime(event.timestamp),
            style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackersTab(PrivacyProvider provider) {
    if (provider.trackers.isEmpty) {
      return _buildEmptyState(
        icon: AppIcons.chartSquare,
        title: 'No Trackers Found',
        subtitle: 'Known trackers will appear here',
      );
    }

    final groupedTrackers = <String, List<TrackerInfo>>{};
    for (final tracker in provider.trackers) {
      groupedTrackers.putIfAbsent(tracker.category, () => []).add(tracker);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Blocked count
        GlassCard(
          tintColor: GlassTheme.successColor,
          child: Row(
            children: [
              const GlassSvgIconBox(icon: AppIcons.forbidden, color: GlassTheme.successColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${provider.blockedTrackers.length} Trackers Blocked',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Out of ${provider.trackers.length} known trackers',
                      style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        ...groupedTrackers.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassSectionHeader(title: entry.key),
              ...entry.value.map((tracker) => _buildTrackerCard(tracker, provider)),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildTrackerCard(TrackerInfo tracker, PrivacyProvider provider) {
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: tracker.isBlocked ? AppIcons.forbidden : AppIcons.chartSquare,
            color: tracker.isBlocked ? GlassTheme.successColor : GlassTheme.warningColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tracker.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                Text(
                  tracker.company,
                  style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: tracker.isBlocked,
            onChanged: (_) => provider.toggleTrackerBlocking(tracker.id),
            activeColor: GlassTheme.successColor,
          ),
        ],
      ),
    );
  }

  Widget _buildEventsTab(PrivacyProvider provider) {
    if (provider.events.isEmpty) {
      return _buildEmptyState(
        icon: AppIcons.timer,
        title: 'No Events',
        subtitle: 'Privacy events will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.events.length,
      itemBuilder: (context, index) {
        final event = provider.events[index];
        return _buildEventCard(event);
      },
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
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
