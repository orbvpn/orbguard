/// Analytics Dashboard Screen
/// Threat analytics, statistics, and reporting interface

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/dashboard_provider.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedTimeRange = '7d';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, _) {
        return GlassPage(
          title: 'Analytics',
          body: provider.isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : Column(
                  children: [
                    // Actions row
                    Padding(
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
                            onPressed: provider.isLoading ? null : () => provider.refreshDashboard(),
                            tooltip: 'Refresh',
                          ),
                        ],
                      ),
                    ),
                    // Tab bar
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
                        child: Container(
                          decoration: GlassTheme.glassDecoration(),
                          child: TabBar(
                            controller: _tabController,
                            indicatorColor: GlassTheme.primaryAccent,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.white54,
                            tabs: const [
                              Tab(text: 'Overview'),
                              Tab(text: 'Threats'),
                              Tab(text: 'Protection'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewTab(provider),
                          _buildThreatsTab(provider),
                          _buildProtectionTab(provider),
                        ],
                      ),
                    ),
                  ],
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
              _buildMetricCard('Total Scans', '1,247', 'magnifer', GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              _buildMetricCard('Threats Blocked', '89', 'forbidden', GlassTheme.errorColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMetricCard('URLs Checked', '3,521', 'link', const Color(0xFF9C27B0)),
              const SizedBox(width: 12),
              _buildMetricCard('SMS Analyzed', '245', 'chat_dots', const Color(0xFF2196F3)),
            ],
          ),
          const SizedBox(height: 24),

          // Threat distribution chart placeholder
          const Text(
            'Threat Distribution',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              children: [
                _buildDistributionBar('Phishing', 0.35, GlassTheme.errorColor),
                _buildDistributionBar('Malware', 0.25, const Color(0xFFFF5722)),
                _buildDistributionBar('Scam', 0.20, GlassTheme.warningColor),
                _buildDistributionBar('Suspicious', 0.15, const Color(0xFF9C27B0)),
                _buildDistributionBar('Other', 0.05, Colors.grey),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Activity timeline
          const Text(
            'Recent Activity',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildActivityCard(
            icon: 'forbidden',
            title: 'Phishing URL Blocked',
            subtitle: 'hxxps://fake-bank.com/login',
            time: '2 min ago',
            color: GlassTheme.errorColor,
          ),
          _buildActivityCard(
            icon: 'chat_dots',
            title: 'Smishing SMS Detected',
            subtitle: 'Suspicious message from +1234567890',
            time: '15 min ago',
            color: GlassTheme.warningColor,
          ),
          _buildActivityCard(
            icon: 'qr_code',
            title: 'Safe QR Code Scanned',
            subtitle: 'https://example.com',
            time: '1 hour ago',
            color: GlassTheme.successColor,
          ),
          _buildActivityCard(
            icon: 'wi_fi_router',
            title: 'Network Scan Complete',
            subtitle: 'No threats detected',
            time: '3 hours ago',
            color: GlassTheme.primaryAccent,
          ),
        ],
      ),
    );
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Threat summary
          GlassCard(
            tintColor: GlassTheme.errorColor,
            child: Column(
              children: [
                Row(
                  children: [
                    const GlassDuotoneIconBox(icon: 'danger_triangle', color: GlassTheme.errorColor, size: 56, iconSize: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '89 Threats Detected',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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

          // Threat types
          const Text(
            'Threat Types',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildThreatTypeCard('Phishing URLs', 35, 'link', GlassTheme.errorColor),
          _buildThreatTypeCard('Malware Apps', 22, 'smartphone', const Color(0xFFFF5722)),
          _buildThreatTypeCard('Smishing SMS', 18, 'chat_dots', GlassTheme.warningColor),
          _buildThreatTypeCard('Scam Calls', 8, 'smartphone', const Color(0xFF9C27B0)),
          _buildThreatTypeCard('Rogue Networks', 6, 'wi_fi_router', const Color(0xFF2196F3)),
          const SizedBox(height: 24),

          // Top threat sources
          const Text(
            'Top Threat Sources',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildThreatSourceCard('Unknown Senders', 42),
          _buildThreatSourceCard('Suspicious Domains', 28),
          _buildThreatSourceCard('Untrusted Apps', 15),
          _buildThreatSourceCard('Public Networks', 4),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Protection score
          _buildProtectionScoreCard(92),
          const SizedBox(height: 24),

          // Protection modules
          const Text(
            'Protection Status',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildProtectionModuleCard('URL Protection', true, '3,521 URLs checked', 'link'),
          _buildProtectionModuleCard('SMS Protection', true, '245 messages scanned', 'chat_dots'),
          _buildProtectionModuleCard('App Security', true, '48 apps analyzed', 'smartphone'),
          _buildProtectionModuleCard('Network Security', true, '12 networks audited', 'wi_fi_router'),
          _buildProtectionModuleCard('Dark Web Monitor', true, '2 emails monitored', 'incognito'),
          _buildProtectionModuleCard('Privacy Protection', false, 'Enable for full protection', 'eye_closed'),
          const SizedBox(height: 24),

          // Quick stats
          const Text(
            'Protection Stats',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickStatCard('Blocked', '89', GlassTheme.errorColor),
              const SizedBox(width: 12),
              _buildQuickStatCard('Safe', '4,589', GlassTheme.successColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickStatCard('Warnings', '23', GlassTheme.warningColor),
              const SizedBox(width: 12),
              _buildQuickStatCard('Uptime', '99.9%', GlassTheme.primaryAccent),
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
