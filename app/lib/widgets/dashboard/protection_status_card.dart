// Protection Status Card Widget
// Displays device protection status and feature overview

import 'package:flutter/material.dart';

import '../../models/api/threat_stats.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/theme/protection_verdict.dart';
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
      // Spacing comes from the parent screen's section gaps.
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (isLoading)
            _buildLoadingState()
          else
            _buildProtectionStatus(context),
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

  Widget _buildProtectionStatus(BuildContext context) {
    // Not-assessed sentinel (-1) when the backend has no assessment yet, so a
    // fresh device reads "Not assessed yet" instead of a misleading "At risk".
    final available = protection?.available ?? status?.isActive ?? false;
    final score = available
        ? (protection?.protectionScore ?? status?.score ?? 0.0)
        : -1.0;

    // Wording + colors from the ONE shared verdict source (matches the home).
    final verdict = ProtectionVerdict.fromScore(score);
    final statusColor = verdict.ink;
    final statusText = verdict.label;
    final statusIcon = switch (verdict.level) {
      ProtectionLevel.excellent || ProtectionLevel.good => AppIcons.shieldCheck,
      ProtectionLevel.attention => AppIcons.shield,
      ProtectionLevel.atRisk => AppIcons.dangerTriangle,
      ProtectionLevel.notAssessed => AppIcons.shield,
    };

    return Column(
      children: [
        // Protection score circle
        _ProtectionScoreCircle(
          score: score,
          color: statusColor,
          icon: statusIcon,
        ),
        const SizedBox(height: 16),
        // Status text
        Text(
          statusText,
          style: BrandText.heading(size: 22, color: statusColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        // Last scan info
        if (protection?.lastScan != null)
          Text(
            'Last scan: ${_formatTime(protection!.lastScan)}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              icon: const DuotoneIcon(AppIcons.search,
                  size: 20, color: Brand.onLime),
              label: const Text('Start Scan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Brand.onLime,
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
  final Color color;
  final String icon;

  const _ProtectionScoreCircle({
    required this.score,
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
              backgroundColor: Brand.surface2,
              valueColor: AlwaysStoppedAnimation(Brand.border),
            ),
          ),
          // Progress circle (empty when the device is not assessed yet)
          SizedBox(
            width: 140,
            height: 140,
            child: CircularProgressIndicator(
              value: score < 0 ? 0 : score / 100,
              strokeWidth: 8,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          // Inner content — the score itself (no more confusing "U" grade)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DuotoneIcon(icon, size: 32, color: color),
              const SizedBox(height: 6),
              Text(
                score < 0 ? '—' : '${score.round()}%',
                style: BrandText.heading(size: 26, color: color),
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
      color = AppColors.idle;
    } else if (!isHealthy) {
      color = AppColors.secondaryInk;
    } else {
      color = AppColors.accentInk;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5)),
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
      color = AppColors.errorInk;
      icon = AppIcons.shield;
    } else if (score >= 80) {
      color = AppColors.accentInk;
      icon = AppIcons.shieldCheck;
    } else if (score >= 50) {
      color = AppColors.amberInk;
      icon = AppIcons.shield;
    } else {
      color = AppColors.errorInk;
      icon = AppIcons.dangerTriangle;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTheme.radiusLarge),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(GlassTheme.radiusLarge),
          border: Border.all(color: color.withValues(alpha: 0.5)),
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
      // Spacing comes from the parent screen's section gaps.
      margin: EdgeInsets.zero,
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
            _buildHealth(context)
          else
            _buildEmptyState(context),
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
                ? AppColors.success.withValues(alpha: 0.2)
                : AppColors.warning.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
          ),
          child: DuotoneIcon(
            AppIcons.smartphone,
            color: (health?.isHealthy ?? true)
                ? AppColors.accentInk
                : AppColors.secondaryInk,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Device Health',
            style: BrandText.title(),
          ),
        ),
        if (health != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getGradeColor(health!.grade).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
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

  Widget _buildHealth(BuildContext context) {
    return Column(
      children: [
        // Health checks
        _buildHealthCheck(
            context, 'Secure Screen Lock', health!.hasSecureScreenLock),
        _buildHealthCheck(context, 'Device Encrypted', health!.isEncrypted),
        _buildHealthCheck(
            context, 'Security Patch', health!.hasLatestSecurityPatch),
        _buildHealthCheck(context, 'Not Rooted', !health!.isRooted),
        _buildHealthCheck(
            context, 'Dev Options Off', !health!.developerOptionsEnabled),
        // Issues
        if (health!.hasIssues) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DuotoneIcon(AppIcons.infoCircle,
                        color: AppColors.secondaryInk, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${health!.issues.length} issue${health!.issues.length > 1 ? 's' : ''} found',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.secondaryInk,
                          fontWeight: FontWeight.w500,
                        ),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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

  Widget _buildHealthCheck(BuildContext context, String label, bool passed) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          DuotoneIcon(
            passed ? AppIcons.checkCircle : AppIcons.closeCircle,
            size: 18,
            color: passed ? AppColors.accentInk : AppColors.errorInk,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: passed ? cs.onSurfaceVariant : cs.error,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            DuotoneIcon(AppIcons.questionCircle,
                size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'Health status unavailable',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'A':
        return AppColors.accentInk;
      case 'B':
        return AppColors.accentInk;
      case 'C':
        return AppColors.amberInk;
      case 'D':
        return AppColors.secondaryInk;
      case 'F':
        return AppColors.errorInk;
      default:
        return AppColors.idle;
    }
  }
}
