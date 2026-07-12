// App Security Widgets
// Reusable widgets for app security screens

import 'package:flutter/material.dart';

import '../../models/api/url_reputation.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/app_security_provider.dart';

/// Risk score gauge widget
class RiskScoreGauge extends StatelessWidget {
  final double score;
  final double size;

  const RiskScoreGauge({
    super.key,
    required this.score,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getScoreColor();
    final percentage = (score * 100).round();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 8,
              backgroundColor: Brand.surface2,
              valueColor: AlwaysStoppedAnimation<Color>(Brand.surface2),
            ),
          ),
          // Progress circle
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: score,
              strokeWidth: 8,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          // Score text
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$percentage',
                style: BrandText.heading(size: size * 0.3, color: color),
              ),
              Text(
                'Risk',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: size * 0.12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getScoreColor() {
    if (score > 0.7) return AppColors.errorInk;
    if (score > 0.4) return AppColors.amberInk;
    return AppColors.accentInk;
  }
}

/// Privacy grade badge
class PrivacyGradeBadge extends StatelessWidget {
  final String grade;
  final bool large;

  const PrivacyGradeBadge({
    super.key,
    required this.grade,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(AppSecurityProvider.getPrivacyGradeColor(grade));
    final size = large ? 48.0 : 32.0;
    final fontSize = large ? 24.0 : 16.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Center(
        child: Text(
          grade.toUpperCase(),
          style: BrandText.heading(size: fontSize, color: color),
        ),
      ),
    );
  }
}

/// Risk level badge
class RiskLevelBadge extends StatelessWidget {
  final String level;
  final bool compact;

  const RiskLevelBadge({
    super.key,
    required this.level,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(AppSecurityProvider.getRiskLevelColor(level));

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 2 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      ),
      child: Text(
        level.toUpperCase(),
        style: BrandText.label(
          color: color,
          size: compact ? 10 : 12,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// App list item card
class AppListCard extends StatelessWidget {
  final AnalyzedApp app;
  final VoidCallback? onTap;
  final VoidCallback? onAnalyze;

  const AppListCard({
    super.key,
    required this.app,
    this.onTap,
    this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasResult = app.result != null;
    final borderColor = hasResult
        ? (app.isHighRisk
            ? AppColors.errorInk.withAlpha(75)
            : app.isMediumRisk
                ? AppColors.amberInk.withAlpha(75)
                : AppColors.accentInk.withAlpha(75))
        : cs.outline;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            // App icon placeholder
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
              ),
              child: Center(
                child: Text(
                  app.app.appName.isNotEmpty
                      ? app.app.appName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // App info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          app.app.appName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (app.app.isSideloaded)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withAlpha(40),
                            borderRadius: BorderRadius.circular(
                                GlassTheme.radiusXSmall),
                          ),
                          child: Text(
                            'Sideloaded',
                            style: TextStyle(
                              color: AppColors.secondaryInk,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    app.app.packageName,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasResult) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        PrivacyGradeBadge(grade: app.privacyGrade),
                        const SizedBox(width: 8),
                        RiskLevelBadge(
                          level: app.riskLevel,
                          compact: true,
                        ),
                        if (app.result!.detectedTrackers.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.chartColors[4].withAlpha(40),
                              borderRadius: BorderRadius.circular(
                                  GlassTheme.radiusXSmall),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DuotoneIcon(
                                  AppIcons.radar,
                                  size: 10,
                                  color: AppColors.chartColors[4],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${app.result!.detectedTrackers.length}',
                                  style: TextStyle(
                                    color: AppColors.chartColors[4],
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Actions
            if (app.isPending)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (!hasResult && onAnalyze != null)
              IconButton(
                icon: DuotoneIcon(AppIcons.search, color: AppColors.accentInk),
                onPressed: onAnalyze,
                tooltip: 'Analyze',
              )
            else
              DuotoneIcon(AppIcons.chevronRight, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Permission chip widget
class PermissionChip extends StatelessWidget {
  final PermissionRisk permission;
  final bool showDescription;

  const PermissionChip({
    super.key,
    required this.permission,
    this.showDescription = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = permission.isDangerous
        ? AppColors.errorInk
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final iconName = AppSecurityProvider.getPermissionIcon(permission.permission);

    if (showDescription) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
          border: Border.all(color: color.withAlpha(50)),
        ),
        child: Row(
          children: [
            DuotoneIcon(_getIconString(iconName), size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatPermissionName(permission.permission),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    permission.description,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (permission.isDangerous)
              DuotoneIcon(AppIcons.dangerTriangle,
                  size: 18, color: AppColors.errorInk),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(_getIconString(iconName), size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            _formatPermissionName(permission.permission),
            style: TextStyle(
              color: color,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPermissionName(String permission) {
    final parts = permission.split('.');
    final name = parts.last.replaceAll('_', ' ');
    return name.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  String _getIconString(String name) {
    switch (name) {
      case 'camera':
        return AppIcons.camera;
      case 'mic':
        return AppIcons.microphone;
      case 'location_on':
        return AppIcons.mapPoint;
      case 'contacts':
        return AppIcons.usersGroup;
      case 'calendar_today':
        return AppIcons.calendar;
      case 'folder':
        return AppIcons.folder;
      case 'sms':
        return AppIcons.chatDots;
      case 'phone':
        return AppIcons.smartphone;
      case 'bluetooth':
        return AppIcons.bluetooth;
      case 'wifi':
        return AppIcons.wifi;
      case 'notifications':
        return AppIcons.bell;
      case 'accessibility':
        return AppIcons.user;
      default:
        return AppIcons.shieldCheck;
    }
  }
}

/// Tracker card widget
class TrackerCard extends StatelessWidget {
  final TrackerInfo tracker;
  final VoidCallback? onTap;

  const TrackerCard({
    super.key,
    required this.tracker,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.chartColors[4].withAlpha(40),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: DuotoneIcon(
                AppIcons.radar,
                size: 18,
                color: AppColors.chartColors[4],
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tracker.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (tracker.company != null)
                    Text(
                      tracker.company!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Category
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getCategoryColor().withAlpha(40),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Text(
                tracker.category,
                style: TextStyle(
                  color: _getCategoryColor(),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor() {
    switch (tracker.category.toLowerCase()) {
      case 'analytics':
        return AppColors.secondaryInk;
      case 'advertising':
        return AppColors.amberInk;
      case 'social':
        return AppColors.secondaryInk;
      case 'crash':
        return AppColors.errorInk;
      default:
        return Brand.text2;
    }
  }
}

/// App security stats card
class AppSecurityStatsCard extends StatelessWidget {
  final AppSecurityStats stats;

  const AppSecurityStatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Security Overview',
            style: BrandText.title(size: 18, weight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          // Stats grid
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  'Total Apps',
                  stats.totalApps.toString(),
                  AppIcons.smartphone,
                  AppColors.accentInk,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Analyzed',
                  stats.analyzedApps.toString(),
                  AppIcons.search,
                  AppColors.secondaryInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  'High Risk',
                  stats.highRiskApps.toString(),
                  AppIcons.dangerTriangle,
                  AppColors.errorInk,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Sideloaded',
                  stats.sideloadedApps.toString(),
                  AppIcons.fileDownload,
                  AppColors.amberInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  'Trackers',
                  stats.trackersFound.toString(),
                  AppIcons.radar,
                  AppColors.chartColors[4],
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Dangerous',
                  stats.dangerousPermissions.toString(),
                  AppIcons.shieldCheck,
                  AppColors.errorInk,
                ),
              ),
            ],
          ),
          if (stats.malwareDetected > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(25),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Row(
                children: [
                  DuotoneIcon(AppIcons.bug, color: AppColors.errorInk, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${stats.malwareDetected} malware app${stats.malwareDetected > 1 ? 's' : ''} detected!',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.errorInk,
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _buildStatItem(BuildContext context, String label, String value,
      String icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Row(
        children: [
          DuotoneIcon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: BrandText.heading(size: 18, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Scan progress indicator
class ScanProgressIndicator extends StatelessWidget {
  final double progress;
  final bool isScanning;
  final VoidCallback? onStart;

  const ScanProgressIndicator({
    super.key,
    required this.progress,
    required this.isScanning,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Column(
        children: [
          if (isScanning) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scanning Apps...',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(progress * 100).round()}% complete',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accentInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: cs.onSurface.withValues(alpha: 0.04),
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.accentInk),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App Security Scan',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Analyze installed apps for risks',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onStart,
                  icon: const DuotoneIcon(AppIcons.play, size: 18, color: Brand.onLime),
                  label: const Text('Scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Brand.lime,
                    foregroundColor: Brand.onLime,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
