/// App Security Widgets
/// Reusable widgets for app security screens

import 'package:flutter/material.dart';

import '../../models/api/url_reputation.dart';
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
              backgroundColor: Colors.grey.withAlpha(40),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.withAlpha(40)),
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
                style: TextStyle(
                  color: color,
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Risk',
                style: TextStyle(
                  color: Colors.grey[500],
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
    if (score > 0.7) return Colors.red;
    if (score > 0.4) return Colors.orange;
    return Colors.green;
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Center(
        child: Text(
          grade.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
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
        borderRadius: BorderRadius.circular(compact ? 4 : 8),
      ),
      child: Text(
        level.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.bold,
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
    final hasResult = app.result != null;
    final borderColor = hasResult
        ? (app.isHighRisk
            ? Colors.red.withAlpha(75)
            : app.isMediumRisk
                ? Colors.orange.withAlpha(75)
                : Colors.green.withAlpha(75))
        : Colors.white10;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            // App icon placeholder
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2B40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  app.app.appName.isNotEmpty
                      ? app.app.appName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white70,
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
                            color: Colors.orange.withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Sideloaded',
                            style: TextStyle(
                              color: Colors.orange,
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
                      color: Colors.grey[600],
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
                              color: Colors.purple.withAlpha(40),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const DuotoneIcon(
                                  AppIcons.radar,
                                  size: 10,
                                  color: Colors.purple,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${app.result!.detectedTrackers.length}',
                                  style: const TextStyle(
                                    color: Colors.purple,
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
                icon: const DuotoneIcon(AppIcons.search, color: Color(0xFF00D9FF)),
                onPressed: onAnalyze,
                tooltip: 'Analyze',
              )
            else
              const DuotoneIcon(AppIcons.chevronRight, color: Colors.grey),
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
    final color = permission.isDangerous ? Colors.red : Colors.grey;
    final iconName = AppSecurityProvider.getPermissionIcon(permission.permission);

    if (showDescription) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
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
                  ),
                  const SizedBox(height: 2),
                  Text(
                    permission.description,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (permission.isDangerous)
              const DuotoneIcon(AppIcons.dangerTriangle, size: 18, color: Colors.red),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2B40),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.purple.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const DuotoneIcon(
                AppIcons.radar,
                size: 18,
                color: Colors.purple,
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
                  ),
                  if (tracker.company != null)
                    Text(
                      tracker.company!,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            // Category
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getCategoryColor().withAlpha(40),
                borderRadius: BorderRadius.circular(4),
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
        return Colors.blue;
      case 'advertising':
        return Colors.orange;
      case 'social':
        return Colors.pink;
      case 'crash':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

/// App security stats card
class AppSecurityStatsCard extends StatelessWidget {
  final AppSecurityStats stats;

  const AppSecurityStatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Security Overview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          // Stats grid
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Total Apps',
                  stats.totalApps.toString(),
                  AppIcons.smartphone,
                  const Color(0xFF00D9FF),
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Analyzed',
                  stats.analyzedApps.toString(),
                  AppIcons.search,
                  Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'High Risk',
                  stats.highRiskApps.toString(),
                  AppIcons.dangerTriangle,
                  Colors.red,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Sideloaded',
                  stats.sideloadedApps.toString(),
                  AppIcons.fileDownload,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Trackers',
                  stats.trackersFound.toString(),
                  AppIcons.radar,
                  Colors.purple,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Dangerous',
                  stats.dangerousPermissions.toString(),
                  AppIcons.shieldCheck,
                  Colors.deepOrange,
                ),
              ),
            ],
          ),
          if (stats.malwareDetected > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const DuotoneIcon(AppIcons.bug, color: Colors.red, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    '${stats.malwareDetected} malware app${stats.malwareDetected > 1 ? 's' : ''} detected!',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
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

  Widget _buildStatItem(
      String label, String value, String icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
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
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
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
                      const Text(
                        'Scanning Apps...',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(progress * 100).round()}% complete',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00D9FF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white10,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF00D9FF)),
              ),
            ),
          ] else ...[
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App Security Scan',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Analyze installed apps for risks',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onStart,
                  icon: const DuotoneIcon(AppIcons.play, size: 18, color: Colors.black),
                  label: const Text('Scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D9FF),
                    foregroundColor: Colors.black,
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
