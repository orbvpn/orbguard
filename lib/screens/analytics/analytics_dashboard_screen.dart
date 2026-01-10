/// Analytics Dashboard Screen
/// Threat analytics, statistics, and reporting interface

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/dashboard_provider.dart';
import '../../models/api/threat_indicator.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  String _selectedTimeRange = '7d';
  final _numberFormat = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<DashboardProvider>();
      if (!provider.hasData) {
        provider.refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && !provider.hasData) {
          return GlassPage(
            title: 'Analytics',
            body: const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent)),
          );
        }

        return GlassTabPage(
          title: 'Analytics',
          tabs: [
            GlassTab(
              label: 'Overview',
              iconPath: 'chart',
              content: _buildOverviewTab(provider),
            ),
            GlassTab(
              label: 'Threats',
              iconPath: 'danger_triangle',
              content: _buildThreatsTab(provider),
            ),
            GlassTab(
              label: 'Protection',
              iconPath: 'shield',
              content: _buildProtectionTab(provider),
            ),
          ],
          headerContent: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PopupMenuButton<String>(
                  icon: const DuotoneIcon('calendar', size: 22, color: Colors.white),
                  color: GlassTheme.gradientTop,
                  onSelected: (value) => setState(() => _selectedTimeRange = value),
                  itemBuilder: (context) => [
                    _buildTimeRangeItem('24h', 'Last 24 Hours'),
                    _buildTimeRangeItem('7d', 'Last 7 Days'),
                    _buildTimeRangeItem('30d', 'Last 30 Days'),
                    _buildTimeRangeItem('90d', 'Last 90 Days'),
                  ],
                ),
                IconButton(
                  icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
                  onPressed: provider.isLoading ? null : () => provider.refresh(),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _buildTimeRangeItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (_selectedTimeRange == value)
            const DuotoneIcon('check_circle', size: 18, color: GlassTheme.primaryAccent)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(DashboardProvider provider) {
    final stats = provider.stats;

    // Get metric values from real data
    final totalIndicators = stats?.totalIndicators ?? 0;
    final threatsBlocked = provider.threatsBlockedToday;
    final urlsChecked = stats?.getCountByType(IndicatorType.url) ?? 0;
    final smsAnalyzed = stats?.getCountByType(IndicatorType.phoneNumber) ?? 0;

    // Calculate threat distribution from stats
    final total = stats?.totalIndicators ?? 1;
    final phishingCount = stats?.getCountByType(IndicatorType.url) ?? 0;
    final malwareCount = (stats?.getCountByType(IndicatorType.sha256) ?? 0) +
        (stats?.getCountByType(IndicatorType.sha1) ?? 0) +
        (stats?.getCountByType(IndicatorType.md5) ?? 0);
    final domainCount = stats?.getCountByType(IndicatorType.domain) ?? 0;
    final ipCount = (stats?.getCountByType(IndicatorType.ipv4) ?? 0) +
        (stats?.getCountByType(IndicatorType.ipv6) ?? 0);
    final otherCount = total - phishingCount - malwareCount - domainCount - ipCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time range indicator
          GlassBadge(text: _getTimeRangeLabel(), color: GlassTheme.primaryAccent),
          const SizedBox(height: 16),

          // Key metrics
          Row(
            children: [
              _buildMetricCard('Total Indicators', _numberFormat.format(totalIndicators), 'magnifer', GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              _buildMetricCard('Threats Blocked', _numberFormat.format(threatsBlocked), 'forbidden', GlassTheme.errorColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMetricCard('URLs Checked', _numberFormat.format(urlsChecked), 'link', const Color(0xFF9C27B0)),
              const SizedBox(width: 12),
              _buildMetricCard('Phone/SMS', _numberFormat.format(smsAnalyzed), 'chat_dots', const Color(0xFF2196F3)),
            ],
          ),
          const SizedBox(height: 24),

          // Threat distribution chart
          const Text(
            'Threat Distribution',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              children: [
                _buildDistributionBar('URLs/Phishing', total > 0 ? phishingCount / total : 0, GlassTheme.errorColor),
                _buildDistributionBar('Malware Hashes', total > 0 ? malwareCount / total : 0, const Color(0xFFFF5722)),
                _buildDistributionBar('Domains', total > 0 ? domainCount / total : 0, GlassTheme.warningColor),
                _buildDistributionBar('IP Addresses', total > 0 ? ipCount / total : 0, const Color(0xFF9C27B0)),
                _buildDistributionBar('Other', total > 0 ? otherCount / total : 0, Colors.grey),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Activity timeline from real alerts
          const Text(
            'Recent Activity',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (provider.recentAlerts.isEmpty && provider.realtimeEvents.isEmpty)
            GlassCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No recent activity',
                    style: TextStyle(color: Colors.white.withAlpha(128)),
                  ),
                ),
              ),
            )
          else ...[
            // Show real alerts from provider
            ...provider.recentAlerts.take(4).map((alert) => _buildActivityCard(
                  icon: _getAlertIcon(alert.type),
                  title: alert.title,
                  subtitle: alert.message,
                  time: _formatTime(alert.timestamp),
                  color: _getSeverityColorFromLevel(alert.severity),
                )),
            // Show realtime events if available
            ...provider.realtimeEvents.take(4 - provider.recentAlerts.length).map((event) => _buildActivityCard(
                  icon: _getAlertIcon(event.type),
                  title: event.type.toUpperCase(),
                  subtitle: event.description ?? event.value,
                  time: _formatTime(event.timestamp),
                  color: _getSeverityColorFromLevel(event.severity),
                )),
          ],
        ],
      ),
    );
  }

  String _getAlertIcon(String type) {
    switch (type.toLowerCase()) {
      case 'url':
      case 'phishing':
        return 'link';
      case 'sms':
      case 'smishing':
        return 'chat_dots';
      case 'qr':
        return 'qr_code';
      case 'network':
        return 'wi_fi_router';
      case 'app':
        return 'smartphone';
      default:
        return 'danger_triangle';
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'high':
        return GlassTheme.errorColor;
      case 'medium':
        return GlassTheme.warningColor;
      case 'low':
        return GlassTheme.primaryAccent;
      default:
        return GlassTheme.successColor;
    }
  }

  Color _getSeverityColorFromLevel(SeverityLevel severity) {
    switch (severity) {
      case SeverityLevel.critical:
      case SeverityLevel.high:
        return GlassTheme.errorColor;
      case SeverityLevel.medium:
        return GlassTheme.warningColor;
      case SeverityLevel.low:
        return GlassTheme.primaryAccent;
      case SeverityLevel.info:
      case SeverityLevel.unknown:
        return GlassTheme.successColor;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildMetricCard(String label, String value, String icon, Color color) {
    return Expanded(
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlassDuotoneIconBox(icon: icon, color: color, size: 36, iconSize: 18),
                const Spacer(),
                DuotoneIcon('graph_up', size: 16, color: GlassTheme.successColor),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistributionBar(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13)),
              Text('${(value * 100).toInt()}%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard({
    required String icon,
    required String title,
    required String subtitle,
    required String time,
    required Color color,
  }) {
    return GlassCard(
      child: Row(
        children: [
          GlassDuotoneIconBox(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(time, style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildThreatsTab(DashboardProvider provider) {
    final stats = provider.stats;
    final totalThreats = stats?.activeIndicators ?? 0;

    // Get counts by severity for the threat types breakdown
    final criticalCount = provider.getThreatsBySeverity(SeverityLevel.critical);
    final highCount = provider.getThreatsBySeverity(SeverityLevel.high);
    final mediumCount = provider.getThreatsBySeverity(SeverityLevel.medium);
    final lowCount = provider.getThreatsBySeverity(SeverityLevel.low);

    // Get counts by type
    final urlCount = provider.getIndicatorsByType(IndicatorType.url);
    final domainCount = provider.getIndicatorsByType(IndicatorType.domain);
    final ipCount = provider.getIndicatorsByType(IndicatorType.ipv4) +
        provider.getIndicatorsByType(IndicatorType.ipv6);
    final hashCount = provider.getIndicatorsByType(IndicatorType.sha256) +
        provider.getIndicatorsByType(IndicatorType.sha1) +
        provider.getIndicatorsByType(IndicatorType.md5);
    final phoneCount = provider.getIndicatorsByType(IndicatorType.phoneNumber);

    // Calculate percentages for sources
    final total = totalThreats > 0 ? totalThreats : 1;
    final urlPercent = (urlCount * 100 / total).round();
    final domainPercent = (domainCount * 100 / total).round();
    final ipPercent = (ipCount * 100 / total).round();
    final otherPercent = 100 - urlPercent - domainPercent - ipPercent;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Threat summary
          GlassCard(
            tintColor: totalThreats > 0 ? GlassTheme.errorColor : GlassTheme.successColor,
            child: Column(
              children: [
                Row(
                  children: [
                    GlassDuotoneIconBox(
                      icon: totalThreats > 0 ? 'danger_triangle' : 'verified_check',
                      color: totalThreats > 0 ? GlassTheme.errorColor : GlassTheme.successColor,
                      size: 56,
                      iconSize: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            totalThreats > 0
                                ? '${_numberFormat.format(totalThreats)} Active Threats'
                                : 'No Active Threats',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'In the $_selectedTimeRange period',
                            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Threat types by indicator type
          const Text(
            'Threat Types',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildThreatTypeCard('Phishing URLs', urlCount, 'link', GlassTheme.errorColor),
          _buildThreatTypeCard('Malicious Domains', domainCount, 'globe', const Color(0xFFFF5722)),
          _buildThreatTypeCard('Malicious IPs', ipCount, 'server', GlassTheme.warningColor),
          _buildThreatTypeCard('Malware Hashes', hashCount, 'code', const Color(0xFF9C27B0)),
          _buildThreatTypeCard('Phone/SMS Threats', phoneCount, 'chat_dots', const Color(0xFF2196F3)),
          const SizedBox(height: 24),

          // Threat severity breakdown
          const Text(
            'By Severity',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildThreatTypeCard('Critical', criticalCount, 'danger_circle', GlassTheme.errorColor),
          _buildThreatTypeCard('High', highCount, 'danger_triangle', const Color(0xFFFF5722)),
          _buildThreatTypeCard('Medium', mediumCount, 'info_circle', GlassTheme.warningColor),
          _buildThreatTypeCard('Low', lowCount, 'info_square', Colors.grey),
          const SizedBox(height: 24),

          // Top threat sources
          const Text(
            'Threat Distribution',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildThreatSourceCard('URLs', urlPercent > 0 ? urlPercent : 0),
          _buildThreatSourceCard('Domains', domainPercent > 0 ? domainPercent : 0),
          _buildThreatSourceCard('IP Addresses', ipPercent > 0 ? ipPercent : 0),
          _buildThreatSourceCard('Other', otherPercent > 0 ? otherPercent : 0),
        ],
      ),
    );
  }

  Widget _buildThreatTypeCard(String type, int count, String icon, Color color) {
    return GlassCard(
      child: Row(
        children: [
          GlassDuotoneIconBox(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(type, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ),
          Text(
            count.toString(),
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildThreatSourceCard(String source, int percentage) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(source, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              Text('$percentage%', style: const TextStyle(color: GlassTheme.primaryAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(GlassTheme.primaryAccent),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionTab(DashboardProvider provider) {
    final protectionScore = provider.protectionScore.round();
    final stats = provider.stats;

    // Get feature statuses
    final smsStatus = provider.getFeatureStatus('sms');
    final webStatus = provider.getFeatureStatus('web');
    final appStatus = provider.getFeatureStatus('app');
    final networkStatus = provider.getFeatureStatus('network');
    final vpnStatus = provider.getFeatureStatus('vpn');

    // Calculate stats from real data
    final threatsBlocked = provider.threatsBlockedToday + provider.threatsBlockedWeek;
    final safeScans = (stats?.totalIndicators ?? 0) - (stats?.activeIndicators ?? 0);
    final highSeverity = provider.highSeverityThreats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Protection score
          _buildProtectionScoreCard(protectionScore),
          const SizedBox(height: 24),

          // Protection modules
          const Text(
            'Protection Status',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildProtectionModuleCard(
            'URL Protection',
            webStatus?.isEnabled ?? false,
            webStatus?.isEnabled == true
                ? '${_numberFormat.format(stats?.getCountByType(IndicatorType.url) ?? 0)} URLs monitored'
                : 'Enable for URL scanning',
            'link',
          ),
          _buildProtectionModuleCard(
            'SMS Protection',
            smsStatus?.isEnabled ?? false,
            smsStatus?.isEnabled == true
                ? '${_numberFormat.format(stats?.getCountByType(IndicatorType.phoneNumber) ?? 0)} messages scanned'
                : 'Enable for SMS protection',
            'chat_dots',
          ),
          _buildProtectionModuleCard(
            'App Security',
            appStatus?.isEnabled ?? false,
            appStatus?.isEnabled == true
                ? 'App scanning active'
                : 'Enable for app analysis',
            'smartphone',
          ),
          _buildProtectionModuleCard(
            'Network Security',
            networkStatus?.isEnabled ?? false,
            networkStatus?.isEnabled == true
                ? 'Network monitoring active'
                : 'Enable for network protection',
            'wi_fi_router',
          ),
          _buildProtectionModuleCard(
            'VPN Protection',
            vpnStatus?.isEnabled ?? false,
            vpnStatus?.isEnabled == true
                ? 'VPN connected'
                : 'Enable for encrypted connection',
            'shield',
          ),
          const SizedBox(height: 24),

          // Quick stats
          const Text(
            'Protection Stats',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickStatCard('Blocked', _numberFormat.format(threatsBlocked), GlassTheme.errorColor),
              const SizedBox(width: 12),
              _buildQuickStatCard('Safe', _numberFormat.format(safeScans), GlassTheme.successColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickStatCard('High Risk', _numberFormat.format(highSeverity), GlassTheme.warningColor),
              const SizedBox(width: 12),
              _buildQuickStatCard('Score', '$protectionScore%', GlassTheme.primaryAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionScoreCard(int score) {
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
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 10,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'score',
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Protection Score',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 80
                      ? 'Excellent protection! Your device is well secured.'
                      : score >= 50
                          ? 'Good protection. Some improvements recommended.'
                          : 'Protection needs improvement. Enable more features.',
                  style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionModuleCard(String name, bool enabled, String status, String icon) {
    return GlassCard(
      child: Row(
        children: [
          GlassDuotoneIconBox(
            icon: icon,
            color: enabled ? GlassTheme.successColor : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(
                  status,
                  style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                ),
              ],
            ),
          ),
          DuotoneIcon(
            enabled ? 'check_circle' : 'close_circle',
            color: enabled ? GlassTheme.successColor : Colors.grey,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatCard(String label, String value, Color color) {
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

  String _getTimeRangeLabel() {
    switch (_selectedTimeRange) {
      case '24h':
        return 'Last 24 Hours';
      case '7d':
        return 'Last 7 Days';
      case '30d':
        return 'Last 30 Days';
      case '90d':
        return 'Last 90 Days';
      default:
        return 'Last 7 Days';
    }
  }
}
