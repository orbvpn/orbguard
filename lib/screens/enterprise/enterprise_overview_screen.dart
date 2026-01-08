/// Enterprise Overview Dashboard Screen
/// Organization-wide security status and metrics
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';

class EnterpriseOverviewScreen extends StatefulWidget {
  const EnterpriseOverviewScreen({super.key});

  @override
  State<EnterpriseOverviewScreen> createState() => _EnterpriseOverviewScreenState();
}

class _EnterpriseOverviewScreenState extends State<EnterpriseOverviewScreen> {
  bool _isLoading = false;
  final EnterpriseStats _stats = EnterpriseStats.sample();
  final List<SecurityEvent> _recentEvents = [];
  final List<DeviceHealth> _deviceHealth = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _recentEvents.addAll(_getSampleEvents());
      _deviceHealth.addAll(_getSampleDeviceHealth());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Enterprise Overview',
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export Report',
            onPressed: () => _showExportDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: GlassTheme.primaryAccent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Security Score
                  _buildSecurityScoreCard(),
                  const SizedBox(height: 16),

                  // Key Metrics
                  _buildKeyMetrics(),
                  const SizedBox(height: 24),

                  // Threat Summary
                  const GlassSectionHeader(title: 'Threat Summary'),
                  _buildThreatSummary(),
                  const SizedBox(height: 24),

                  // Device Health
                  const GlassSectionHeader(title: 'Device Health'),
                  _buildDeviceHealthGrid(),
                  const SizedBox(height: 24),

                  // Compliance Status
                  const GlassSectionHeader(title: 'Compliance Status'),
                  _buildComplianceStatus(),
                  const SizedBox(height: 24),

                  // Recent Events
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const GlassSectionHeader(title: 'Recent Events'),
                      TextButton(
                        onPressed: () {},
                        child: const Text('View All', style: TextStyle(color: GlassTheme.primaryAccent)),
                      ),
                    ],
                  ),
                  ..._recentEvents.take(5).map((event) => _buildEventCard(event)),
                ],
              ),
            ),
    );
  }

  Widget _buildSecurityScoreCard() {
    final score = _stats.securityScore;
    Color scoreColor;
    String scoreLabel;
    if (score >= 80) {
      scoreColor = GlassTheme.successColor;
      scoreLabel = 'Excellent';
    } else if (score >= 60) {
      scoreColor = GlassTheme.warningColor;
      scoreLabel = 'Good';
    } else {
      scoreColor = GlassTheme.errorColor;
      scoreLabel = 'Needs Attention';
    }

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 10,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Score',
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield, color: scoreColor),
                      const SizedBox(width: 8),
                      Text(
                        scoreLabel,
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Organization security posture based on ${_stats.totalDevices} devices and ${_stats.activeUsers} active users',
                    style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildMiniStat(Icons.devices, '${_stats.totalDevices}', 'Devices'),
                      const SizedBox(width: 16),
                      _buildMiniStat(Icons.people, '${_stats.activeUsers}', 'Users'),
                      const SizedBox(width: 16),
                      _buildMiniStat(Icons.warning, '${_stats.openIncidents}', 'Incidents'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11)),
      ],
    );
  }

  Widget _buildKeyMetrics() {
    return Row(
      children: [
        _buildMetricCard('Threats Blocked', '${_stats.threatsBlocked}', GlassTheme.errorColor, Icons.block, '+12%'),
        const SizedBox(width: 12),
        _buildMetricCard('Policies Active', '${_stats.activePolicies}', GlassTheme.primaryAccent, Icons.policy, ''),
        const SizedBox(width: 12),
        _buildMetricCard('Compliance', '${_stats.complianceRate}%', GlassTheme.successColor, Icons.verified, '+5%'),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, Color color, IconData icon, String trend) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 11), textAlign: TextAlign.center),
            if (trend.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(trend, style: TextStyle(color: GlassTheme.successColor, fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThreatSummary() {
    return GlassCard(
      child: Column(
        children: [
          _buildThreatRow('Critical', _stats.criticalThreats, GlassTheme.errorColor),
          _buildThreatRow('High', _stats.highThreats, const Color(0xFFFF5722)),
          _buildThreatRow('Medium', _stats.mediumThreats, GlassTheme.warningColor),
          _buildThreatRow('Low', _stats.lowThreats, GlassTheme.successColor),
        ],
      ),
    );
  }

  Widget _buildThreatRow(String level, int count, Color color) {
    final total = _stats.criticalThreats + _stats.highThreats + _stats.mediumThreats + _stats.lowThreats;
    final percentage = total > 0 ? count / total : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 60,
            child: Text(level, style: const TextStyle(color: Colors.white)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 40,
            child: Text(
              '$count',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceHealthGrid() {
    return Row(
      children: [
        _buildHealthCard('Healthy', _stats.healthyDevices, GlassTheme.successColor, Icons.check_circle),
        const SizedBox(width: 12),
        _buildHealthCard('At Risk', _stats.atRiskDevices, GlassTheme.warningColor, Icons.warning),
        const SizedBox(width: 12),
        _buildHealthCard('Critical', _stats.criticalDevices, GlassTheme.errorColor, Icons.error),
      ],
    );
  }

  Widget _buildHealthCard(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: GlassCard(
        onTap: () {},
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text('$count', style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildComplianceStatus() {
    return GlassCard(
      child: Column(
        children: [
          _buildComplianceRow('SOC 2', _stats.soc2Compliance, true),
          _buildComplianceRow('GDPR', _stats.gdprCompliance, true),
          _buildComplianceRow('HIPAA', _stats.hipaaCompliance, false),
          _buildComplianceRow('PCI-DSS', _stats.pciCompliance, true),
          _buildComplianceRow('ISO 27001', _stats.isoCompliance, false),
        ],
      ),
    );
  }

  Widget _buildComplianceRow(String framework, int percentage, bool enabled) {
    Color statusColor;
    if (!enabled) {
      statusColor = Colors.grey;
    } else if (percentage >= 90) {
      statusColor = GlassTheme.successColor;
    } else if (percentage >= 70) {
      statusColor = GlassTheme.warningColor;
    } else {
      statusColor = GlassTheme.errorColor;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              framework,
              style: TextStyle(color: enabled ? Colors.white : Colors.white54, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: enabled ? percentage / 100 : 0,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 50,
            child: Text(
              enabled ? '$percentage%' : 'N/A',
              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            enabled ? (percentage >= 90 ? Icons.check_circle : Icons.warning) : Icons.remove_circle,
            size: 18,
            color: statusColor,
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(SecurityEvent event) {
    return GlassCard(
      onTap: () => _showEventDetails(context, event),
      child: Row(
        children: [
          GlassIconBox(
            icon: _getEventIcon(event.type),
            color: _getEventColor(event.severity),
            size: 44,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(event.description, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GlassBadge(text: event.severity, color: _getEventColor(event.severity), fontSize: 10),
              const SizedBox(height: 4),
              Text(_formatTime(event.timestamp), style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  void _showEventDetails(BuildContext context, SecurityEvent event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlassIconBox(icon: _getEventIcon(event.type), color: _getEventColor(event.severity), size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      GlassBadge(text: event.severity, color: _getEventColor(event.severity)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(event.description, style: TextStyle(color: Colors.white.withAlpha(204))),
            const SizedBox(height: 16),
            GlassContainer(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildDetailRow('Type', event.type),
                  _buildDetailRow('Source', event.source),
                  _buildDetailRow('Time', _formatTime(event.timestamp)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Dismiss'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Export Report', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: GlassTheme.errorColor),
              title: const Text('PDF Report', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: GlassTheme.successColor),
              title: const Text('CSV Export', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.code, color: GlassTheme.primaryAccent),
              title: const Text('JSON Export', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(153))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  IconData _getEventIcon(String type) {
    switch (type.toLowerCase()) {
      case 'malware':
        return Icons.bug_report;
      case 'phishing':
        return Icons.phishing;
      case 'policy violation':
        return Icons.policy;
      case 'unauthorized access':
        return Icons.lock;
      case 'data exfiltration':
        return Icons.upload;
      default:
        return Icons.security;
    }
  }

  Color _getEventColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return GlassTheme.errorColor;
      case 'high':
        return const Color(0xFFFF5722);
      case 'medium':
        return GlassTheme.warningColor;
      case 'low':
        return GlassTheme.successColor;
      default:
        return GlassTheme.primaryAccent;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  List<SecurityEvent> _getSampleEvents() {
    return [
      SecurityEvent(
        id: '1',
        title: 'Malware Blocked',
        description: 'Ransomware attempt blocked on device LAPTOP-042',
        type: 'Malware',
        severity: 'Critical',
        source: 'Endpoint Protection',
        timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
      ),
      SecurityEvent(
        id: '2',
        title: 'Phishing Attempt Detected',
        description: 'Phishing email blocked for user john.doe@company.com',
        type: 'Phishing',
        severity: 'High',
        source: 'Email Security',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      SecurityEvent(
        id: '3',
        title: 'Policy Violation',
        description: 'USB storage device connected to restricted workstation',
        type: 'Policy Violation',
        severity: 'Medium',
        source: 'DLP',
        timestamp: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      SecurityEvent(
        id: '4',
        title: 'Failed Login Attempts',
        description: 'Multiple failed login attempts from IP 192.168.1.100',
        type: 'Unauthorized Access',
        severity: 'Medium',
        source: 'IAM',
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
      ),
      SecurityEvent(
        id: '5',
        title: 'Suspicious Download',
        description: 'Potentially malicious file downloaded by user',
        type: 'Malware',
        severity: 'Low',
        source: 'Web Gateway',
        timestamp: DateTime.now().subtract(const Duration(hours: 8)),
      ),
    ];
  }

  List<DeviceHealth> _getSampleDeviceHealth() {
    return [
      DeviceHealth(deviceId: 'LAPTOP-001', status: 'healthy', lastSeen: DateTime.now()),
      DeviceHealth(deviceId: 'LAPTOP-002', status: 'at_risk', lastSeen: DateTime.now().subtract(const Duration(hours: 2))),
      DeviceHealth(deviceId: 'DESKTOP-001', status: 'healthy', lastSeen: DateTime.now()),
    ];
  }
}

class EnterpriseStats {
  final int securityScore;
  final int totalDevices;
  final int activeUsers;
  final int openIncidents;
  final int threatsBlocked;
  final int activePolicies;
  final int complianceRate;
  final int criticalThreats;
  final int highThreats;
  final int mediumThreats;
  final int lowThreats;
  final int healthyDevices;
  final int atRiskDevices;
  final int criticalDevices;
  final int soc2Compliance;
  final int gdprCompliance;
  final int hipaaCompliance;
  final int pciCompliance;
  final int isoCompliance;

  EnterpriseStats({
    required this.securityScore,
    required this.totalDevices,
    required this.activeUsers,
    required this.openIncidents,
    required this.threatsBlocked,
    required this.activePolicies,
    required this.complianceRate,
    required this.criticalThreats,
    required this.highThreats,
    required this.mediumThreats,
    required this.lowThreats,
    required this.healthyDevices,
    required this.atRiskDevices,
    required this.criticalDevices,
    required this.soc2Compliance,
    required this.gdprCompliance,
    required this.hipaaCompliance,
    required this.pciCompliance,
    required this.isoCompliance,
  });

  factory EnterpriseStats.sample() {
    return EnterpriseStats(
      securityScore: 78,
      totalDevices: 247,
      activeUsers: 189,
      openIncidents: 12,
      threatsBlocked: 1847,
      activePolicies: 34,
      complianceRate: 92,
      criticalThreats: 3,
      highThreats: 8,
      mediumThreats: 24,
      lowThreats: 45,
      healthyDevices: 218,
      atRiskDevices: 23,
      criticalDevices: 6,
      soc2Compliance: 94,
      gdprCompliance: 89,
      hipaaCompliance: 0,
      pciCompliance: 78,
      isoCompliance: 0,
    );
  }
}

class SecurityEvent {
  final String id;
  final String title;
  final String description;
  final String type;
  final String severity;
  final String source;
  final DateTime timestamp;

  SecurityEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.severity,
    required this.source,
    required this.timestamp,
  });
}

class DeviceHealth {
  final String deviceId;
  final String status;
  final DateTime lastSeen;

  DeviceHealth({
    required this.deviceId,
    required this.status,
    required this.lastSeen,
  });
}
