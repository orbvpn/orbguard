/// Analytics Dashboard Screen
/// Threat analytics, statistics, and reporting interface
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/dashboard_provider.dart';
import '../../models/api/threat_indicator.dart';
import '../../services/api/orbguard_api_client.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  String _selectedTimeRange = '7d';
  final _numberFormat = NumberFormat('#,###');
  final _apiClient = OrbGuardApiClient.instance;

  // Analytics data from dedicated API.
  // Shapes mirror the live backend (orbguard-lab handlers/analytics.go +
  // models/analytics.go): threat analytics carries `summary` and
  // `by_type: [{category, count, percentage}]`; alert metrics carries
  // `total_alerts`/`open_alerts` and optional `mtta_minutes`; geo carries
  // `countries: [{country_code, country_name, count, percentage}]`;
  // detection metrics carries optional `detection_rate` and
  // `false_positive_rate` (absent when the server has no tracking data).
  Map<String, dynamic>? _threatAnalytics;
  Map<String, dynamic>? _alertMetrics;
  Map<String, dynamic>? _geoData;
  Map<String, dynamic>? _detectionMetrics;
  String? _analyticsError;
  bool _isLoadingAnalytics = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<DashboardProvider>();
      if (!provider.hasData) {
        provider.refresh();
      }
      _loadAnalytics();
    });
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoadingAnalytics = true;
      _analyticsError = null;
    });

    final errors = <String>[];

    Map<String, dynamic>? threats;
    try {
      threats = await _apiClient.getThreatAnalytics(period: _selectedTimeRange);
    } catch (e) {
      errors.add('threats: $e');
    }

    Map<String, dynamic>? alerts;
    try {
      alerts = await _apiClient.getAlertMetrics(period: _selectedTimeRange);
    } catch (e) {
      errors.add('alerts: $e');
    }

    Map<String, dynamic>? geo;
    try {
      geo = await _apiClient.getGeoDistribution(period: _selectedTimeRange);
    } catch (e) {
      errors.add('geo: $e');
    }

    Map<String, dynamic>? detections;
    try {
      detections = await _apiClient.getDetectionMetrics(period: _selectedTimeRange);
    } catch (e) {
      errors.add('detections: $e');
    }

    if (!mounted) return;
    setState(() {
      _threatAnalytics = threats;
      _alertMetrics = alerts;
      _geoData = geo;
      _detectionMetrics = detections;
      _analyticsError =
          errors.isEmpty ? null : 'Failed to load analytics — ${errors.join('; ')}';
      _isLoadingAnalytics = false;
    });
  }

  void _onTimeRangeChanged(String value) {
    setState(() => _selectedTimeRange = value);
    _loadAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        final cs = Theme.of(context).colorScheme;
        if (provider.isLoading && !provider.hasData) {
          return GlassPage(
            title: 'Analytics',
            body: Center(child: CircularProgressIndicator(color: AppColors.accentInk)),
          );
        }

        return GlassTabPage(
          title: 'Analytics',
          actions: [
            PopupMenuButton<String>(
              icon: DuotoneIcon('calendar', size: 22, color: cs.onSurface),
              color: cs.surfaceContainerHighest,
              onSelected: _onTimeRangeChanged,
              itemBuilder: (context) => [
                _buildTimeRangeItem('24h', 'Last 24 Hours'),
                _buildTimeRangeItem('7d', 'Last 7 Days'),
                _buildTimeRangeItem('30d', 'Last 30 Days'),
                _buildTimeRangeItem('90d', 'Last 90 Days'),
              ],
            ),
            GestureDetector(
              onTap: _showReportDialog,
              child: DuotoneIcon('document_add', size: 22, color: cs.onSurface),
            ),
            GestureDetector(
              onTap: () {
                if (!provider.isLoading) provider.refresh();
              },
              child: DuotoneIcon('refresh', size: 22, color: cs.onSurface),
            ),
          ],
          tabs: [
            GlassTab(
              label: 'Overview',
              iconPath: 'chart',
              content: _buildOverviewTab(context, provider),
            ),
            GlassTab(
              label: 'Threats',
              iconPath: 'danger_triangle',
              content: _buildThreatsTab(context, provider),
            ),
            GlassTab(
              label: 'Protection',
              iconPath: 'shield',
              content: _buildProtectionTab(context, provider),
            ),
          ],
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
            DuotoneIcon('check_circle', size: 18, color: AppColors.accentInk)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: context.onSurface)),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context, DashboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final stats = provider.stats;

    // Use analytics API data if available, fallback to dashboard provider.
    // Live summary keys (models/analytics.go AnalyticsSummary):
    // total_indicators, blocked_domains, blocked_ips, ... The backend does
    // not emit threats_blocked/urls_checked/sms_analyzed.
    final summary = _threatAnalytics?['summary'] as Map<String, dynamic>?;
    final totalIndicators =
        (summary?['total_indicators'] as num?)?.toInt() ?? stats?.totalIndicators ?? 0;
    final threatsBlocked = summary != null
        ? ((summary['blocked_domains'] as num?)?.toInt() ?? 0) +
            ((summary['blocked_ips'] as num?)?.toInt() ?? 0)
        : provider.threatsBlockedToday;
    final urlsChecked = stats?.getCountByType(IndicatorType.url) ?? 0;
    final smsAnalyzed = stats?.getCountByType(IndicatorType.phoneNumber) ?? 0;

    // Threat distribution: the live backend emits
    // by_type: [{category, count, percentage}] (CategoryCount uses the key
    // 'category', not 'name').
    final typeDistribution =
        (_threatAnalytics?['by_type'] as List?)?.cast<Map<String, dynamic>>();
    final total = totalIndicators > 0 ? totalIndicators : 1;

    double phishingRatio = 0, malwareRatio = 0, domainRatio = 0, ipRatio = 0, otherRatio = 0;
    if (typeDistribution != null && typeDistribution.isNotEmpty) {
      for (final item in typeDistribution) {
        final name = (item['category'] as String? ?? '').toLowerCase();
        final count = ((item['count'] as num?)?.toInt() ?? 0).toDouble();
        final ratio = count / total;
        if (name.contains('url') || name.contains('phish')) {
          phishingRatio += ratio;
        } else if (name.contains('hash') || name.contains('sha') || name.contains('md5')) {
          malwareRatio += ratio;
        } else if (name.contains('domain')) {
          domainRatio += ratio;
        } else if (name.contains('ip')) {
          ipRatio += ratio;
        } else {
          otherRatio += ratio;
        }
      }
    } else {
      final phishingCount = stats?.getCountByType(IndicatorType.url) ?? 0;
      final malwareCount = (stats?.getCountByType(IndicatorType.sha256) ?? 0) +
          (stats?.getCountByType(IndicatorType.sha1) ?? 0) +
          (stats?.getCountByType(IndicatorType.md5) ?? 0);
      final domainCount = stats?.getCountByType(IndicatorType.domain) ?? 0;
      final ipCount = (stats?.getCountByType(IndicatorType.ipv4) ?? 0) +
          (stats?.getCountByType(IndicatorType.ipv6) ?? 0);
      phishingRatio = phishingCount / total;
      malwareRatio = malwareCount / total;
      domainRatio = domainCount / total;
      ipRatio = ipCount / total;
      otherRatio = (total - phishingCount - malwareCount - domainCount - ipCount) / total;
    }

    // Alert metrics from analytics API (live keys: total_alerts, open_alerts,
    // acknowledged_alerts, resolved_alerts, optional mtta_minutes).
    final alertTotal = (_alertMetrics?['total_alerts'] as num?)?.toInt();
    final alertOpen = (_alertMetrics?['open_alerts'] as num?)?.toInt();

    // Geo top countries from analytics API. Live entries carry country_name /
    // country_code / count / percentage; there is no top-level total, so it
    // is computed client-side from the per-country counts.
    final geoCountries =
        (_geoData?['countries'] as List?)?.cast<Map<String, dynamic>>();
    final geoTotal = geoCountries?.fold<int>(
            0, (sum, c) => sum + ((c['count'] as num?)?.toInt() ?? 0)) ??
        0;
    final topGeoCountries = geoCountries?.take(3).toList();

    // Detection quality (live keys: detection_rate / false_positive_rate are
    // ABSENT when the server has no tracked review data; mtta_minutes is
    // absent when no alert was acknowledged). These render as 'n/a' rather
    // than fabricated numbers.
    final detectionRate = (_detectionMetrics?['detection_rate'] as num?)?.toDouble();
    final falsePositiveRate =
        (_detectionMetrics?['false_positive_rate'] as num?)?.toDouble();
    final mttaMinutes = (_alertMetrics?['mtta_minutes'] as num?)?.toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time range indicator + loading
          Row(
            children: [
              GlassBadge(text: _getTimeRangeLabel(), color: GlassTheme.primaryAccent),
              if (_isLoadingAnalytics) ...[
                const SizedBox(width: 8),
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentInk)),
              ],
            ],
          ),
          if (_analyticsError != null) ...[
            const SizedBox(height: 12),
            GlassCard(
              margin: EdgeInsets.zero,
              tintColor: GlassTheme.errorColor,
              child: Row(
                children: [
                  DuotoneIcon('danger_circle', color: AppColors.errorInk, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _analyticsError!,
                      style: TextStyle(color: cs.onSurface, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: DuotoneIcon('refresh', color: cs.onSurface, size: 20),
                    onPressed: _loadAnalytics,
                    tooltip: 'Retry',
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Key metrics
          Row(
            children: [
              _buildMetricCard(context, 'Total Indicators', _numberFormat.format(totalIndicators), 'magnifer', GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              _buildMetricCard(context, 'Threats Blocked', _numberFormat.format(threatsBlocked), 'forbidden', GlassTheme.errorColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMetricCard(context, 'URLs Checked', _numberFormat.format(urlsChecked), 'link', AppColors.chartColors[4]),
              const SizedBox(width: 12),
              _buildMetricCard(context, 'Phone/SMS', _numberFormat.format(smsAnalyzed), 'chat_dots', AppColors.chartColors[2]),
            ],
          ),

          // Alert metrics from analytics API
          if (alertTotal != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMetricCard(context, 'Total Alerts', _numberFormat.format(alertTotal), 'bell', GlassTheme.warningColor),
                const SizedBox(width: 12),
                _buildMetricCard(context, 'Open', _numberFormat.format(alertOpen ?? 0), 'notification_unread', AppColors.severityCritical),
              ],
            ),
          ],
          const SizedBox(height: 24),

          // Detection quality — values may legitimately be absent from the
          // server (untracked); show 'n/a' instead of fake numbers.
          Text(
            'Detection Quality',
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GlassCard(
            margin: EdgeInsets.zero,
            child: Row(
              children: [
                _buildQualityMetric(
                  context,
                  'Detection Rate',
                  detectionRate != null
                      ? '${(detectionRate * 100).toStringAsFixed(1)}%'
                      : 'n/a',
                  detectionRate != null ? AppColors.accentInk : cs.onSurfaceVariant,
                ),
                _buildQualityMetric(
                  context,
                  'False Positives',
                  falsePositiveRate != null
                      ? '${(falsePositiveRate * 100).toStringAsFixed(1)}%'
                      : 'n/a',
                  falsePositiveRate != null ? AppColors.secondaryInk : cs.onSurfaceVariant,
                ),
                _buildQualityMetric(
                  context,
                  'MTTA',
                  mttaMinutes != null ? '${mttaMinutes.toStringAsFixed(0)}m' : 'n/a',
                  mttaMinutes != null ? AppColors.accentInk : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Threat distribution chart
          Text(
            'Threat Distribution',
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GlassCard(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _buildDistributionBar(context, 'URLs/Phishing', phishingRatio, AppColors.chartColors[7]),
                _buildDistributionBar(context, 'Malware Hashes', malwareRatio, AppColors.chartColors[5]),
                _buildDistributionBar(context, 'Domains', domainRatio, AppColors.chartColors[1]),
                _buildDistributionBar(context, 'IP Addresses', ipRatio, AppColors.chartColors[4]),
                _buildDistributionBar(context, 'Other', otherRatio, cs.onSurfaceVariant),
              ],
            ),
          ),

          // Geo distribution from analytics API (live entry keys:
          // country_name, country_code, count; total computed client-side).
          if (topGeoCountries != null && topGeoCountries.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Top Threat Origins',
              style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GlassCard(
              margin: EdgeInsets.zero,
              child: Column(
                children: topGeoCountries.map((c) {
                  final country = c['country_name'] as String? ??
                      c['country_code'] as String? ??
                      'Unknown';
                  final count = (c['count'] as num?)?.toInt() ?? 0;
                  return _buildDistributionBar(
                    context,
                    country,
                    geoTotal > 0 ? count / geoTotal : 0,
                    AppColors.chartColors[0],
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Activity timeline from real alerts
          Text(
            'Recent Activity',
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (provider.recentAlerts.isEmpty && provider.realtimeEvents.isEmpty)
            GlassCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No recent activity',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else ...[
            ...provider.recentAlerts.take(4).map((alert) => _buildActivityCard(
                  context,
                  icon: _getAlertIcon(alert.type),
                  title: alert.title,
                  subtitle: alert.message,
                  time: _formatTime(alert.timestamp),
                  color: _getSeverityColorFromLevel(alert.severity),
                )),
            ...provider.realtimeEvents.take(4 - provider.recentAlerts.length).map((event) => _buildActivityCard(
                  context,
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

  Color _getSeverityColorFromLevel(SeverityLevel severity) {
    switch (severity) {
      case SeverityLevel.critical:
        return AppColors.severityCritical;
      case SeverityLevel.high:
        return AppColors.severityHigh;
      case SeverityLevel.medium:
        return AppColors.severityMedium;
      case SeverityLevel.low:
        return AppColors.severityLow;
      case SeverityLevel.info:
      case SeverityLevel.unknown:
        return AppColors.severityInfo;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildMetricCard(BuildContext context, String label, String value, String icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GlassCard(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlassDuotoneIconBox(icon: icon, color: color, size: 36, iconSize: 18),
                const Spacer(),
                DuotoneIcon('graph_up', size: 16, color: AppColors.accentInk),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: BrandText.heading(color: cs.onSurface, size: 28),
            ),
            Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityMetric(BuildContext context, String label, String value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionBar(BuildContext context, String label, double value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ),
              Text('${(value * 100).toInt()}%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: cs.onSurface.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(
    BuildContext context, {
    required String icon,
    required String title,
    required String subtitle,
    required String time,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      child: Row(
        children: [
          GlassDuotoneIconBox(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
                Text(
                  subtitle,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(time, style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildThreatsTab(BuildContext context, DashboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Threat summary
          GlassCard(
            margin: EdgeInsets.zero,
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
                            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'In the $_selectedTimeRange period',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
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
          Text(
            'Threat Types',
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildThreatTypeCard(context, 'Phishing URLs', urlCount, 'link', AppColors.chartColors[7]),
          _buildThreatTypeCard(context, 'Malicious Domains', domainCount, 'globe', AppColors.chartColors[5]),
          _buildThreatTypeCard(context, 'Malicious IPs', ipCount, 'server', AppColors.chartColors[1]),
          _buildThreatTypeCard(context, 'Malware Hashes', hashCount, 'code', AppColors.chartColors[4]),
          _buildThreatTypeCard(context, 'Phone/SMS Threats', phoneCount, 'chat_dots', AppColors.chartColors[2]),
          const SizedBox(height: 24),

          // Threat severity breakdown
          Text(
            'By Severity',
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildThreatTypeCard(context, 'Critical', criticalCount, 'danger_circle', AppColors.severityCritical),
          _buildThreatTypeCard(context, 'High', highCount, 'danger_triangle', AppColors.severityHigh),
          _buildThreatTypeCard(context, 'Medium', mediumCount, 'info_circle', AppColors.severityMedium),
          _buildThreatTypeCard(context, 'Low', lowCount, 'info_square', AppColors.severityLow),
          const SizedBox(height: 24),

          // Top threat sources
          Text(
            'Threat Distribution',
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildThreatSourceCard(context, 'URLs', urlPercent > 0 ? urlPercent : 0),
          _buildThreatSourceCard(context, 'Domains', domainPercent > 0 ? domainPercent : 0),
          _buildThreatSourceCard(context, 'IP Addresses', ipPercent > 0 ? ipPercent : 0),
          _buildThreatSourceCard(context, 'Other', otherPercent > 0 ? otherPercent : 0),
        ],
      ),
    );
  }

  Widget _buildThreatTypeCard(BuildContext context, String type, int count, String icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      child: Row(
        children: [
          GlassDuotoneIconBox(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(type, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
          ),
          Text(
            count.toString(),
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildThreatSourceCard(BuildContext context, String source, int percentage) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(source, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
              Text('$percentage%', style: TextStyle(color: AppColors.chartColors[0], fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: cs.onSurface.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.chartColors[0]),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionTab(BuildContext context, DashboardProvider provider) {
    final cs = Theme.of(context).colorScheme;
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Protection score
          _buildProtectionScoreCard(context, protectionScore),
          const SizedBox(height: 24),

          // Protection modules
          Text(
            'Protection Status',
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildProtectionModuleCard(
            context,
            'URL Protection',
            webStatus?.isEnabled ?? false,
            webStatus?.isEnabled == true
                ? '${_numberFormat.format(stats?.getCountByType(IndicatorType.url) ?? 0)} URLs monitored'
                : 'Enable for URL scanning',
            'link',
          ),
          _buildProtectionModuleCard(
            context,
            'SMS Protection',
            smsStatus?.isEnabled ?? false,
            smsStatus?.isEnabled == true
                ? '${_numberFormat.format(stats?.getCountByType(IndicatorType.phoneNumber) ?? 0)} messages scanned'
                : 'Enable for SMS protection',
            'chat_dots',
          ),
          _buildProtectionModuleCard(
            context,
            'App Security',
            appStatus?.isEnabled ?? false,
            appStatus?.isEnabled == true
                ? 'App scanning active'
                : 'Enable for app analysis',
            'smartphone',
          ),
          _buildProtectionModuleCard(
            context,
            'Network Security',
            networkStatus?.isEnabled ?? false,
            networkStatus?.isEnabled == true
                ? 'Network monitoring active'
                : 'Enable for network protection',
            'wi_fi_router',
          ),
          _buildProtectionModuleCard(
            context,
            'VPN Protection',
            vpnStatus?.isEnabled ?? false,
            vpnStatus?.isEnabled == true
                ? 'VPN connected'
                : 'Enable for encrypted connection',
            'shield',
          ),
          const SizedBox(height: 24),

          // Quick stats
          Text(
            'Protection Stats',
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickStatCard(context, 'Blocked', _numberFormat.format(threatsBlocked), AppColors.errorInk),
              const SizedBox(width: 12),
              _buildQuickStatCard(context, 'Safe', _numberFormat.format(safeScans), AppColors.accentInk),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickStatCard(context, 'High Risk', _numberFormat.format(highSeverity), AppColors.secondaryInk),
              const SizedBox(width: 12),
              _buildQuickStatCard(context, 'Score', '$protectionScore%', AppColors.accentInk),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionScoreCard(BuildContext context, int score) {
    final cs = Theme.of(context).colorScheme;
    final color = score >= 80
        ? GlassTheme.successColor
        : score >= 50
            ? GlassTheme.warningColor
            : GlassTheme.errorColor;
    final ink = score >= 80
        ? AppColors.accentInk
        : score >= 50
            ? AppColors.secondaryInk
            : AppColors.errorInk;

    return GlassCard(
      margin: EdgeInsets.zero,
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
                  backgroundColor: cs.onSurface.withValues(alpha: 0.06),
                  // Lime ring on a lime-tinted card is near-invisible on light;
                  // use the contrast-safe deep-lime ink for the high (lime)
                  // state. Pink/red states stay on their fill hue.
                  valueColor: AlwaysStoppedAnimation<Color>(
                      score >= 80 ? AppColors.accentInk : color),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: BrandText.heading(color: ink, size: 32),
                    ),
                    Text(
                      'score',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
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
                Text(
                  'Protection Score',
                  style: TextStyle(color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 80
                      ? 'Excellent protection! Your device is well secured.'
                      : score >= 50
                          ? 'Good protection. Some improvements recommended.'
                          : 'Protection needs improvement. Enable more features.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtectionModuleCard(BuildContext context, String name, bool enabled, String status, String icon) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      child: Row(
        children: [
          GlassDuotoneIconBox(
            icon: icon,
            color: enabled ? GlassTheme.successColor : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
                Text(
                  status,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          DuotoneIcon(
            enabled ? 'check_circle' : 'close_circle',
            color: enabled ? AppColors.accentInk : cs.onSurfaceVariant,
            size: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatCard(BuildContext context, String label, String value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              value,
              style: BrandText.heading(color: color, size: 28),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // Report types/formats offered here are exactly the ones the live backend
  // accepts (orbguard-lab analytics_service.go supportedReportTypes /
  // supportedReportFormats); anything else is rejected with HTTP 400.
  static const List<MapEntry<String, String>> _reportTypes = [
    MapEntry('threat_landscape', 'Threat Landscape'),
    MapEntry('campaign_analysis', 'Campaign Analysis'),
    MapEntry('source_health', 'Source Health'),
  ];
  static const List<String> _reportFormats = ['json', 'csv', 'html'];

  Future<void> _showReportDialog() async {
    String selectedType = _reportTypes.first.key;
    String selectedFormat = _reportFormats.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Generate Report',
              style: TextStyle(color: dialogContext.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Type',
                  style: TextStyle(
                      color: dialogContext.onSurfaceMuted, fontSize: 12)),
              const SizedBox(height: 4),
              DropdownButton<String>(
                value: selectedType,
                isExpanded: true,
                dropdownColor: dialogContext.colors.surfaceContainerHighest,
                style: TextStyle(color: dialogContext.onSurface),
                items: _reportTypes
                    .map((t) => DropdownMenuItem(value: t.key, child: Text(t.value)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedType = v);
                },
              ),
              const SizedBox(height: 12),
              Text('Format',
                  style: TextStyle(
                      color: dialogContext.onSurfaceMuted, fontSize: 12)),
              const SizedBox(height: 4),
              DropdownButton<String>(
                value: selectedFormat,
                isExpanded: true,
                dropdownColor: dialogContext.colors.surfaceContainerHighest,
                style: TextStyle(color: dialogContext.onSurface),
                items: _reportFormats
                    .map((f) => DropdownMenuItem(value: f, child: Text(f.toUpperCase())))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedFormat = v);
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Period: ${_getTimeRangeLabel()}',
                style: TextStyle(
                    color: dialogContext.onSurfaceMuted, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Brand.onLime,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Generate'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final report = await _apiClient.createAnalyticsReport(
        reportType: selectedType,
        format: selectedFormat,
        period: _selectedTimeRange,
      );
      if (!mounted) return;
      final id = report['id'] as String? ?? '';
      final status = report['status'] as String? ?? 'unknown';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report $status${id.isNotEmpty ? ' — $id' : ''}'),
          backgroundColor: GlassTheme.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report generation failed: $e'),
          backgroundColor: GlassTheme.errorColor,
        ),
      );
    }
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
