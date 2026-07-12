/// QR Widgets
/// Reusable widgets for QR code scanning screens
library;

import 'package:flutter/material.dart';

import '../../models/api/sms_analysis.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/qr_provider.dart';

/// QR result card
class QrResultCard extends StatelessWidget {
  final QrScanResult result;
  final VoidCallback? onTap;

  const QrResultCard({
    super.key,
    required this.result,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = result.threatLevel == SmsThreatLevel.safe
        ? AppColors.accentInk.withAlpha(75)
        : Color(result.threatLevel.color).withAlpha(75);

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                _ContentTypeIcon(contentType: result.contentType),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        QrProvider.getContentTypeDisplayName(result.contentType),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatContent(result.content),
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
                QrThreatBadge(level: result.threatLevel),
              ],
            ),

            // Threats
            if (result.hasThreats) ...[
              const SizedBox(height: 12),
              _ThreatsList(threats: result.threats),
            ],

            // Recommendation
            if (result.recommendation != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DuotoneIcon(
                    AppIcons.lightbulb,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.recommendation!,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Risk score
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Risk Score:',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(GlassTheme.radiusXSmall),
                    child: LinearProgressIndicator(
                      value: result.riskScore,
                      backgroundColor: cs.onSurface.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(
                        _getRiskColor(result.riskScore),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(result.riskScore * 100).toInt()}%',
                  style: TextStyle(
                    color: _getRiskColor(result.riskScore),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            // Action buttons
            if (result.shouldBlock ||
                result.threatLevel != SmsThreatLevel.safe) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.errorInk,
                      ),
                      icon: DuotoneIcon(AppIcons.forbidden,
                          size: 18, color: AppColors.errorInk),
                      label: const Text('Block'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.onSurfaceVariant,
                      ),
                      icon: DuotoneIcon(AppIcons.copy, size: 18, color: cs.onSurfaceVariant),
                      label: const Text('Copy'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatContent(String content) {
    if (content.length > 50) {
      return '${content.substring(0, 50)}...';
    }
    return content;
  }

  Color _getRiskColor(double score) {
    if (score >= 0.7) return AppColors.errorInk;
    if (score >= 0.4) return AppColors.amberInk;
    if (score >= 0.2) return AppColors.amberInk;
    return AppColors.accentInk;
  }
}

/// QR threat badge
class QrThreatBadge extends StatelessWidget {
  final SmsThreatLevel level;
  final bool compact;

  const QrThreatBadge({
    super.key,
    required this.level,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: Color(level.color).withAlpha(50),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
        border: Border.all(color: Color(level.color).withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(
            _getIcon(),
            size: compact ? 14 : 16,
            color: Color(level.color),
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            level.displayName,
            style: TextStyle(
              color: Color(level.color),
              fontSize: compact ? 11 : 13,
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
        return AppIcons.shieldCheck;
      case SmsThreatLevel.suspicious:
        return AppIcons.dangerTriangle;
      case SmsThreatLevel.dangerous:
        return AppIcons.dangerCircle;
      case SmsThreatLevel.critical:
        return AppIcons.dangerCircle;
    }
  }
}

/// Content type icon
class _ContentTypeIcon extends StatelessWidget {
  final String contentType;

  const _ContentTypeIcon({required this.contentType});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(40),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Center(
        child: DuotoneIcon(
          _getIcon(),
          color: AppColors.accentInk,
          size: 22,
        ),
      ),
    );
  }

  String _getIcon() {
    switch (contentType.toLowerCase()) {
      case 'url':
        return AppIcons.urlProtection;
      case 'text':
        return AppIcons.fileText;
      case 'email':
        return AppIcons.letter;
      case 'phone':
        return AppIcons.smartphone;
      case 'sms':
        return AppIcons.chatDots;
      case 'wifi':
        return AppIcons.wifi;
      case 'vcard':
        return AppIcons.userId;
      case 'geo':
        return AppIcons.mapPoint;
      case 'event':
        return AppIcons.calendar;
      case 'crypto':
        return AppIcons.wallet;
      case 'app_link':
        return AppIcons.smartphone;
      default:
        return AppIcons.qrCode;
    }
  }
}

/// Threats list widget
class _ThreatsList extends StatelessWidget {
  final List<QrThreat> threats;

  const _ThreatsList({required this.threats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(25),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DuotoneIcon(AppIcons.dangerTriangle,
                  size: 16, color: AppColors.errorInk),
              const SizedBox(width: 6),
              Text(
                '${threats.length} threat${threats.length > 1 ? 's' : ''} detected',
                style: TextStyle(
                  color: AppColors.errorInk,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          ...threats.take(3).map((t) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Color(t.severity.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.description,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// QR history item
class QrHistoryItem extends StatelessWidget {
  final QrScanEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const QrHistoryItem({
    super.key,
    required this.entry,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final result = entry.result;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Status icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _getStatusColor().withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: entry.isPending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : DuotoneIcon(
                        _getContentIcon(),
                        size: 18,
                        color: _getStatusColor(),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // Content info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    QrProvider.getContentTypeDisplayName(
                        entry.contentType ?? result?.contentType ?? 'unknown'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(entry.scannedAt),
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

            // Badge and actions
            if (result != null && !entry.isPending) ...[
              QrThreatBadge(level: result.threatLevel, compact: true),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: DuotoneIcon(AppIcons.closeCircle, size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (entry.isPending) return AppColors.scanning;
    if (entry.isSafe) return AppColors.accentInk;
    return AppColors.errorInk;
  }

  String _getContentIcon() {
    final type = entry.contentType ?? entry.result?.contentType ?? 'unknown';
    switch (type.toLowerCase()) {
      case 'url':
        return AppIcons.urlProtection;
      case 'wifi':
        return AppIcons.wifi;
      case 'phone':
        return AppIcons.smartphone;
      case 'email':
        return AppIcons.letter;
      default:
        return AppIcons.qrCode;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// QR stats card
class QrStatsCard extends StatelessWidget {
  final QrStats stats;

  const QrStatsCard({super.key, required this.stats});

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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(50),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: DuotoneIcon(
                  AppIcons.scanner,
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
                      'QR Security',
                      style: BrandText.title(size: 16, weight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Quishing & malicious QR protection',
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
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _StatItem(
                label: 'Scanned',
                value: stats.totalScanned.toString(),
                color: cs.onSurface,
              ),
              _StatItem(
                label: 'Safe',
                value: stats.safeScans.toString(),
                color: AppColors.accentInk,
              ),
              _StatItem(
                label: 'Flagged',
                value: stats.threatsFlagged.toString(),
                color: stats.threatsFlagged > 0
                    ? AppColors.errorInk
                    : cs.onSurfaceVariant,
              ),
            ],
          ),
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

/// Camera overlay for scanning
class QrScanOverlay extends StatelessWidget {
  final double size;

  const QrScanOverlay({super.key, this.size = 250});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Darkened background
        Container(color: AppColors.overlay),

        // Scan area
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(
              color: Brand.lime,
              width: 3,
            ),
            borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
          ),
        ),

        // Corner accents
        Positioned(
          top: (MediaQuery.of(context).size.height - size) / 2 - 20,
          child: Text(
            'Scan QR Code',
            style: TextStyle(
              // On-dark text token: the camera overlay is always dark.
              color: AppColors.textPrimaryDark.withAlpha(200),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Manual input widget for QR content
class QrManualInput extends StatefulWidget {
  final Function(String content) onAnalyze;
  final bool isAnalyzing;

  const QrManualInput({
    super.key,
    required this.onAnalyze,
    this.isAnalyzing = false,
  });

  @override
  State<QrManualInput> createState() => _QrManualInputState();
}

class _QrManualInputState extends State<QrManualInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Check QR Content',
            style: BrandText.title(size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Paste QR code content to analyze for threats',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Paste URL, text, or any QR content...',
              hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              filled: true,
              fillColor: cs.onSurface.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.isAnalyzing || _controller.text.isEmpty
                ? null
                : () => widget.onAnalyze(_controller.text),
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
