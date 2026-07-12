/// Protection Status Card Widget
/// Displays device protection status and feature overview

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/api/threat_stats.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/duotone_icon.dart';

/// Card displaying overall protection status
class ProtectionStatusCard extends StatelessWidget {
  final ProtectionOverview? protection;
  final ProtectionStatus? status;
  final bool isLoading;
  final VoidCallback? onTap;
  final VoidCallback? onScanTap;

  const ProtectionStatusCard({
    super.key,
    this.protection,
    this.status,
    this.isLoading = false,
    this.onTap,
    this.onScanTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (isLoading)
            _buildLoadingState()
          else
            _buildProtectionStatus(),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildProtectionStatus() {
    final isProtected = protection?.isProtected ?? status?.isActive ?? false;
    final score = protection?.protectionScore ?? status?.score ?? 0.0;
    final grade = protection?.protectionGrade ?? status?.grade ?? 'U';

    Color statusColor;
    String statusIcon;
    String statusText;

    if (!isProtected) {
      statusColor = Colors.red;
      statusIcon = AppIcons.shield;
      statusText = 'Not Protected';
    } else if (score >= 80) {
      statusColor = Colors.green;
      statusIcon = AppIcons.shieldCheck;
      statusText = 'Fully Protected';
    } else if (score >= 50) {
      statusColor = Colors.orange;
      statusIcon = AppIcons.shield;
      statusText = 'Partially Protected';
    } else {
      statusColor = Colors.red;
      statusIcon = AppIcons.dangerTriangle;
      statusText = 'Low Protection';
    }

    return Column(
      children: [
        // Protection score circle
        _ProtectionScoreCircle(
          score: score,
          grade: grade,
          color: statusColor,
          icon: statusIcon,
        ),
        const SizedBox(height: 16),
        // Status text
        Text(
          statusText,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: statusColor,
          ),
        ),
        const SizedBox(height: 8),
        // Last scan info
        if (protection?.lastScan != null)
          Text(
            'Last scan: ${_formatTime(protection!.lastScan)}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        const SizedBox(height: 20),
        // Feature status row
        if (protection != null) _buildFeatureRow(),
        // Scan button
        if (onScanTap != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onScanTap,
              icon: const DuotoneIcon(AppIcons.search, size: 20, color: Colors.black),
              label: const Text('Start Scan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFeatureRow() {
    final features = [
      _FeatureInfo('SMS', protection!.smsProtection, AppIcons.chatDots),
      _FeatureInfo('Web', protection!.webProtection, AppIcons.globus),
      _FeatureInfo('App', protection!.appProtection, AppIcons.smartphone),
      _FeatureInfo('Network', protection!.networkProtection, AppIcons.wifi),
      _FeatureInfo('VPN', protection!.vpnProtection, AppIcons.key),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: features.map((f) => _FeatureStatusChip(feature: f)).toList(),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Animated protection score circle
class _ProtectionScoreCircle extends StatelessWidget {
  final double score;
  final String grade;
  final Color color;
  final String icon;

  const _ProtectionScoreCircle({
    required this.score,
    required this.grade,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          SizedBox(
            width: 140,
            height: 140,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 8,
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation(Colors.grey.withOpacity(0.1)),
            ),
          ),
          // Progress circle
          SizedBox(
            width: 140,
            height: 140,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 8,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          // Inner content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DuotoneIcon(icon, size: 32, color: color),
              const SizedBox(height: 4),
              Text(
                grade,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                '${score.round()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Feature info helper class
class _FeatureInfo {
  final String name;
  final FeatureStatus status;
  final String icon;

  _FeatureInfo(this.name, this.status, this.icon);
}

/// Feature status chip widget
class _FeatureStatusChip extends StatelessWidget {
  final _FeatureInfo feature;

  const _FeatureStatusChip({required this.feature});

  @override
  Widget build(BuildContext context) {
    final isEnabled = feature.status.isEnabled;
    final isHealthy = feature.status.isHealthy;

    Color color;
    if (!isEnabled) {
      color = Colors.grey;
    } else if (!isHealthy) {
      color = Colors.orange;
    } else {
      color = Colors.green;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: DuotoneIcon(
            feature.icon,
            size: 20,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          feature.name,
          style: TextStyle(
            fontSize: 10,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Compact protection status indicator
class ProtectionStatusIndicator extends StatelessWidget {
  final bool isProtected;
  final double score;
  final VoidCallback? onTap;

  const ProtectionStatusIndicator({
    super.key,
    required this.isProtected,
    required this.score,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String icon;

    if (!isProtected) {
      color = Colors.red;
      icon = AppIcons.shield;
    } else if (score >= 80) {
      color = Colors.green;
      icon = AppIcons.shieldCheck;
    } else if (score >= 50) {
      color = Colors.orange;
      icon = AppIcons.shield;
    } else {
      color = Colors.red;
      icon = AppIcons.dangerTriangle;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              '${score.round()}%',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Device health status card
class DeviceHealthCard extends StatelessWidget {
  final DeviceHealthStatus? health;
  final bool isLoading;
  final VoidCallback? onTap;

  const DeviceHealthCard({
    super.key,
    this.health,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (health != null)
            _buildHealth()
          else
            _buildEmptyState(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (health?.isHealthy ?? true)
                ? Colors.green.withOpacity(0.2)
                : Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DuotoneIcon(
            AppIcons.smartphone,
            color: (health?.isHealthy ?? true) ? Colors.green : Colors.orange,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Device Health',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (health != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getGradeColor(health!.grade).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              health!.grade,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _getGradeColor(health!.grade),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHealth() {
    return Column(
      children: [
        // Health checks
        _buildHealthCheck('Secure Screen Lock', health!.hasSecureScreenLock),
        _buildHealthCheck('Device Encrypted', health!.isEncrypted),
        _buildHealthCheck('Security Patch', health!.hasLatestSecurityPatch),
        _buildHealthCheck('Not Rooted', !health!.isRooted),
        _buildHealthCheck(
            'Dev Options Off', !health!.developerOptionsEnabled),
        // Issues
        if (health!.hasIssues) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const DuotoneIcon(AppIcons.infoCircle,
                        color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${health!.issues.length} issue${health!.issues.length > 1 ? 's' : ''} found',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...health!.issues
                    .take(3)
                    .map((issue) => Padding(
                          padding: const EdgeInsets.only(left: 24, top: 4),
                          child: Text(
                            '• $issue',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                          ),
                        )),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHealthCheck(String label, bool passed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          DuotoneIcon(
            passed ? AppIcons.checkCircle : AppIcons.closeCircle,
            size: 18,
            color: passed ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: passed ? Colors.grey[300] : Colors.red[300],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            DuotoneIcon(AppIcons.questionCircle, size: 40, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text(
              'Health status unavailable',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.lightGreen;
      case 'C':
        return Colors.amber;
      case 'D':
        return Colors.orange;
      case 'F':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
