/// Threat Statistics Card Widget
/// Displays threat statistics from OrbGuard Lab API

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/api/threat_stats.dart';
import '../../models/api/threat_indicator.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/duotone_icon.dart';

/// Card displaying threat statistics overview
class ThreatStatsCard extends StatelessWidget {
  final ThreatStats? stats;
  final ThreatOverview? threatOverview;
  final bool isLoading;
  final VoidCallback? onTap;

  const ThreatStatsCard({
    super.key,
    this.stats,
    this.threatOverview,
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
            _buildLoadingState()
          else if (stats != null || threatOverview != null)
            _buildStats()
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
            color: Colors.cyan.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const DuotoneIcon(
            AppIcons.chartSquare,
            color: Colors.cyan,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Threat Intelligence',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (onTap != null)
          const DuotoneIcon(
            AppIcons.chevronRight,
            color: Colors.grey,
            size: 20,
          ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            DuotoneIcon(AppIcons.cloudStorage, size: 40, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text(
              'Unable to load threat data',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    return Column(
      children: [
        // Main stats row
        Row(
          children: [
            Expanded(
              child: _StatItem(
                label: 'Blocked Today',
                value: _formatNumber(threatOverview?.threatsBlockedToday ?? 0),
                color: Colors.green,
                icon: AppIcons.shield,
              ),
            ),
            Expanded(
              child: _StatItem(
                label: 'This Week',
                value: _formatNumber(threatOverview?.threatsBlockedWeek ?? 0),
                color: Colors.cyan,
                icon: AppIcons.calendar,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Severity breakdown
        Row(
          children: [
            Expanded(
              child: _SeverityChip(
                label: 'Critical',
                count: stats?.getCountBySeverity(SeverityLevel.critical) ?? 0,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SeverityChip(
                label: 'High',
                count: stats?.getCountBySeverity(SeverityLevel.high) ?? 0,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SeverityChip(
                label: 'Medium',
                count: stats?.getCountBySeverity(SeverityLevel.medium) ?? 0,
                color: Colors.amber,
              ),
            ),
          ],
        ),
        // Active campaigns indicator
        if ((threatOverview?.activeCampaignsTargetingDevice ?? 0) > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const DuotoneIcon(AppIcons.dangerTriangle, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${threatOverview!.activeCampaignsTargetingDevice} active campaign${threatOverview!.activeCampaignsTargetingDevice > 1 ? 's' : ''} targeting your device',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}

/// Single stat item widget
class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DuotoneIcon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Severity chip widget
class _SeverityChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SeverityChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact threat stats widget for smaller spaces
class ThreatStatsCompact extends StatelessWidget {
  final int blockedToday;
  final int criticalCount;
  final int highCount;
  final VoidCallback? onTap;

  const ThreatStatsCompact({
    super.key,
    required this.blockedToday,
    required this.criticalCount,
    required this.highCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      onTap: onTap,
      borderRadius: GlassTheme.radiusSmall,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMiniStat(AppIcons.shield, blockedToday.toString(), Colors.green),
          const SizedBox(width: 12),
          _buildMiniStat(AppIcons.dangerCircle, criticalCount.toString(), Colors.red),
          const SizedBox(width: 12),
          _buildMiniStat(
              AppIcons.dangerTriangle, highCount.toString(), Colors.orange),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String icon, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Trend indicator widget
class ThreatTrendIndicator extends StatelessWidget {
  final List<ThreatTrend> trends;
  final double height;

  const ThreatTrendIndicator({
    super.key,
    required this.trends,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No trend data',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
      );
    }

    final maxCount =
        trends.map((t) => t.count).reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No threats detected',
            style: TextStyle(color: Colors.green[400], fontSize: 12),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: trends.map((trend) {
          final normalizedHeight = (trend.count / maxCount) * height;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Container(
                height: normalizedHeight.clamp(4.0, height),
                decoration: BoxDecoration(
                  color: _getColorForCount(trend.count, maxCount),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getColorForCount(int count, int max) {
    final ratio = count / max;
    if (ratio > 0.7) return Colors.red;
    if (ratio > 0.4) return Colors.orange;
    if (ratio > 0.1) return Colors.amber;
    return Colors.green;
  }
}
