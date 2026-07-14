// SMS Widgets
// Reusable widgets for SMS protection screens

import 'package:flutter/material.dart';

import '../../models/api/sms_analysis.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/sms_provider.dart';

/// Threat level indicator badge
class ThreatLevelBadge extends StatelessWidget {
  final SmsThreatLevel level;
  final bool compact;

  const ThreatLevelBadge({
    super.key,
    required this.level,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: Color(level.color).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
        border: Border.all(
          color: Color(level.color).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(
            _getIcon(),
            size: compact ? 12 : 14,
            color: AppColors.glyphInk(Color(level.color)),
          ),
          SizedBox(width: compact ? 2 : 4),
          Text(
            level.displayName,
            style: TextStyle(
              color: AppColors.glyphInk(Color(level.color)),
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _getIcon() {
    switch (level) {
      case SmsThreatLevel.safe:
        return AppIcons.checkCircle;
      case SmsThreatLevel.suspicious:
        return AppIcons.dangerTriangle;
      case SmsThreatLevel.dangerous:
        return AppIcons.dangerCircle;
      case SmsThreatLevel.critical:
        return AppIcons.dangerCircle;
    }
  }
}

/// SMS message card widget
class SmsCard extends StatelessWidget {
  final SmsMessage message;
  final VoidCallback? onTap;
  final VoidCallback? onAnalyze;
  final VoidCallback? onBlock;

  const SmsCard({
    super.key,
    required this.message,
    this.onTap,
    this.onAnalyze,
    this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasAnalysis = message.analysisResult != null;
    final threatLevel = message.threatLevel;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
          border: hasAnalysis && threatLevel != SmsThreatLevel.safe
              ? Border.all(
                  color: Color(threatLevel.color).withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // Sender avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getSenderColor().withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      _getSenderInitial(),
                      style: TextStyle(
                        color: _getSenderColor(),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Sender and time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.sender,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Threat badge or analyze button
                if (message.isAnalyzing)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.accentInk),
                    ),
                  )
                else if (hasAnalysis)
                  ThreatLevelBadge(level: threatLevel, compact: true)
                else if (onAnalyze != null)
                  IconButton(
                    icon: DuotoneIcon(AppIcons.shieldCheck, size: 20, color: AppColors.accentInk),
                    color: AppColors.accentInk,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onAnalyze,
                    tooltip: 'Analyze',
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Message content
            Text(
              message.content,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),

            // Threat info if dangerous
            if (hasAnalysis && message.analysisResult!.hasThreats) ...[
              const SizedBox(height: 12),
              _buildThreatInfo(context),
            ],

            // Extracted URLs
            if (hasAnalysis &&
                message.analysisResult!.extractedUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildExtractedUrls(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThreatInfo(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final threats = message.analysisResult!.threats;
    if (threats.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color(message.threatLevel.color).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon(
                AppIcons.dangerTriangle,
                size: 16,
                color: AppColors.glyphInk(Color(message.threatLevel.color)),
              ),
              const SizedBox(width: 6),
              Text(
                'Detected Threats',
                style: TextStyle(
                  color: AppColors.glyphInk(Color(message.threatLevel.color)),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...threats.take(2).map((threat) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Color(threat.severity.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        threat.type.displayName,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
          if (threats.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${threats.length - 2} more threats',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExtractedUrls() {
    final urls = message.analysisResult!.extractedUrls;
    final maliciousUrls = urls.where((u) => u.isMalicious).toList();

    if (maliciousUrls.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      ),
      child: Row(
        children: [
          DuotoneIcon(AppIcons.urlProtection, size: 14, color: AppColors.errorInk),
          const SizedBox(width: 6),
          Text(
            '${maliciousUrls.length} malicious URL${maliciousUrls.length > 1 ? 's' : ''}',
            style: TextStyle(
              color: AppColors.errorInk,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSenderColor() {
    if (message.hasThreats) {
      return Color(message.threatLevel.color);
    }
    // Generate color from sender
    final hash = message.sender.hashCode;
    final colors = AppColors.chartColors;
    return colors[hash.abs() % colors.length];
  }

  String _getSenderInitial() {
    final sender = message.sender.trim();
    if (sender.isEmpty) return '?';

    // If it's a phone number
    if (RegExp(r'^[\d\s\+\-\(\)]+$').hasMatch(sender)) {
      return '#';
    }

    return sender[0].toUpperCase();
  }

  String _formatTime() {
    final now = DateTime.now();
    final diff = now.difference(message.timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${message.timestamp.day}/${message.timestamp.month}/${message.timestamp.year}';
    }
  }
}

/// SMS protection stats card
class SmsStatsCard extends StatelessWidget {
  final SmsStats stats;
  final VoidCallback? onScanAll;
  final bool isScanning;

  const SmsStatsCard({
    super.key,
    required this.stats,
    this.onScanAll,
    this.isScanning = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: DuotoneIcon(
                  AppIcons.chatDots,
                  color: AppColors.accentInk,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SMS Protection',
                      style: BrandText.title(size: 16, weight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Smishing & phishing detection',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onScanAll != null)
                TextButton(
                  onPressed: isScanning ? null : onScanAll,
                  child: isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Scan All'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _StatItem(
                label: 'Total',
                value: stats.totalMessages.toString(),
                color: cs.onSurface,
              ),
              _StatItem(
                label: 'Analyzed',
                value: stats.analyzedMessages.toString(),
                color: AppColors.accentInk,
              ),
              _StatItem(
                label: 'Threats',
                value: stats.threatsDetected.toString(),
                color: stats.threatsDetected > 0
                    ? AppColors.amberInk
                    : AppColors.accentInk,
              ),
              _StatItem(
                label: 'Blocked',
                value: stats.blockedSenders.toString(),
                color: AppColors.errorInk,
              ),
            ],
          ),
          if (stats.criticalThreats > 0 || stats.highThreats > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Row(
                children: [
                  DuotoneIcon(AppIcons.dangerCircle, color: AppColors.errorInk, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${stats.criticalThreats} critical, ${stats.highThreats} high severity threats',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.errorInk,
                        fontSize: 12,
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
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: BrandText.heading(size: 24, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Filter chip for SMS list
class SmsFilterChip extends StatelessWidget {
  final SmsFilter filter;
  final SmsFilter selectedFilter;
  final ValueChanged<SmsFilter> onSelected;

  const SmsFilterChip({
    super.key,
    required this.filter,
    required this.selectedFilter,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = filter == selectedFilter;

    return GestureDetector(
      onTap: () => onSelected(filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentPill : cs.surface,
          borderRadius: BorderRadius.circular(GlassTheme.radiusLarge),
          border: Border.all(
            color: isSelected ? AppColors.accentInk : cs.outline,
          ),
        ),
        child: Text(
          _getLabel(),
          style: TextStyle(
            color: isSelected ? AppColors.accentInk : cs.onSurfaceVariant,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  String _getLabel() {
    switch (filter) {
      case SmsFilter.all:
        return 'All';
      case SmsFilter.safe:
        return 'Safe';
      case SmsFilter.suspicious:
        return 'Suspicious';
      case SmsFilter.dangerous:
        return 'Dangerous';
      case SmsFilter.unanalyzed:
        return 'Unanalyzed';
    }
  }
}

/// Sender analysis card
class SenderAnalysisCard extends StatelessWidget {
  final SenderAnalysis analysis;

  const SenderAnalysisCard({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sender Analysis',
            style: BrandText.title(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: AppIcons.smartphone,
            label: 'Sender',
            value: analysis.sender,
          ),
          if (analysis.isKnownSpammer)
            _InfoRow(
              icon: AppIcons.forbidden,
              label: 'Status',
              value: 'Known Spammer',
              valueColor: AppColors.errorInk,
            ),
          if (analysis.isSpoofed)
            _InfoRow(
              icon: AppIcons.dangerTriangle,
              label: 'Spoofed',
              value: analysis.spoofedBrand ?? 'Yes',
              valueColor: AppColors.secondaryInk,
            ),
          if (analysis.isShortCode)
            const _InfoRow(
              icon: AppIcons.chatDots,
              label: 'Type',
              value: 'Short Code',
            ),
          if (analysis.isAlphanumeric)
            const _InfoRow(
              icon: AppIcons.fileText,
              label: 'Type',
              value: 'Alphanumeric ID',
            ),
          _InfoRow(
            icon: AppIcons.chartActivity,
            label: 'Risk Score',
            value: '${(analysis.riskScore * 100).toInt()}%',
            valueColor: _getRiskColor(analysis.riskScore),
          ),
          if (analysis.warnings != null && analysis.warnings!.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...analysis.warnings!.map((w) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      DuotoneIcon(AppIcons.dangerTriangle,
                          size: 14, color: AppColors.secondaryInk),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          w,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
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

  Color _getRiskColor(double score) {
    if (score >= 0.7) return AppColors.errorInk;
    if (score >= 0.4) return AppColors.amberInk;
    return AppColors.accentInk;
  }
}

class _InfoRow extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          DuotoneIcon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? cs.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Threat detail card
class ThreatDetailCard extends StatelessWidget {
  final SmsThreat threat;

  const ThreatDetailCard({super.key, required this.threat});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(threat.severity.color).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
        border: Border.all(
          color: Color(threat.severity.color).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon(
                _getThreatIcon(),
                color: Color(threat.severity.color),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  threat.type.displayName,
                  style: TextStyle(
                    color: Color(threat.severity.color),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(threat.severity.color).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
                child: Text(
                  threat.severity.displayName,
                  style: TextStyle(
                    color: Color(threat.severity.color),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            threat.description,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
            ),
          ),
          if (threat.evidence != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Row(
                children: [
                  DuotoneIcon(AppIcons.quoteDown,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      threat.evidence!,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (threat.mitreTechniques != null &&
              threat.mitreTechniques!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: threat.mitreTechniques!.map((t) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.06),
                    borderRadius:
                        BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _getThreatIcon() {
    switch (threat.type) {
      case SmsThreatType.phishing:
        return AppIcons.hook;
      case SmsThreatType.smishing:
        return AppIcons.chatDots;
      case SmsThreatType.malwareLink:
        return AppIcons.bug;
      case SmsThreatType.scam:
        return AppIcons.wallet;
      case SmsThreatType.spam:
        return AppIcons.dangerTriangle;
      case SmsThreatType.executiveImpersonation:
        return AppIcons.user;
      case SmsThreatType.bankingFraud:
        return AppIcons.wallet;
      case SmsThreatType.packageDeliveryScam:
        return AppIcons.box;
      case SmsThreatType.otpFraud:
        return AppIcons.lock;
      case SmsThreatType.premiumRate:
        return AppIcons.dollarCircle;
      case SmsThreatType.unknown:
        return AppIcons.questionCircle;
    }
  }
}

/// URL analysis card
class UrlAnalysisCard extends StatelessWidget {
  final ExtractedUrl url;
  final VoidCallback? onTap;

  const UrlAnalysisCard({
    super.key,
    required this.url,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = url.isMalicious ? AppColors.errorInk : AppColors.accentInk;
    final tint = url.isMalicious ? AppColors.error : AppColors.success;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: GlassTheme.tintedGlassDecoration(
          tintColor: tint,
          radius: GlassTheme.radiusXSmall,
          opacity: 0.1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DuotoneIcon(
                  url.isMalicious ? AppIcons.urlProtection : AppIcons.urlProtection,
                  color: color,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    url.domain ?? url.url,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (url.isShortener)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.2),
                      borderRadius:
                          BorderRadius.circular(GlassTheme.radiusXSmall),
                    ),
                    child: Text(
                      'SHORTENER',
                      style: BrandText.label(
                        color: AppColors.secondaryInk,
                        size: 9,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              url.url,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (url.categories != null && url.categories!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: url.categories!.take(3).map((c) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.06),
                      borderRadius:
                          BorderRadius.circular(GlassTheme.radiusXSmall),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Manual SMS input widget
class SmsInputWidget extends StatefulWidget {
  final Function(String content, String? sender) onAnalyze;
  final bool isAnalyzing;

  const SmsInputWidget({
    super.key,
    required this.onAnalyze,
    this.isAnalyzing = false,
  });

  @override
  State<SmsInputWidget> createState() => _SmsInputWidgetState();
}

class _SmsInputWidgetState extends State<SmsInputWidget> {
  final _contentController = TextEditingController();
  final _senderController = TextEditingController();

  @override
  void dispose() {
    _contentController.dispose();
    _senderController.dispose();
    super.dispose();
  }

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Check a Message',
            style: BrandText.title(size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Paste a suspicious message to analyze',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _senderController,
            decoration: InputDecoration(
              hintText: 'Sender (optional)',
              hintStyle: TextStyle(color: cs.onSurfaceVariant),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Paste message content here...',
              hintStyle: TextStyle(color: cs.onSurfaceVariant),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.isAnalyzing || _contentController.text.isEmpty
                ? null
                : () {
                    widget.onAnalyze(
                      _contentController.text,
                      _senderController.text.isNotEmpty
                          ? _senderController.text
                          : null,
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Brand.lime,
              foregroundColor: Brand.onLime,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
            ),
            icon: widget.isAnalyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Brand.onLime),
                    ),
                  )
                : const DuotoneIcon(AppIcons.search, size: 20, color: Brand.onLime),
            label: Text(widget.isAnalyzing ? 'Analyzing...' : 'Analyze'),
          ),
        ],
      ),
    );
  }
}
