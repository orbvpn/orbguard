/// URL Widgets
/// Reusable widgets for URL/web protection screens
library;

import 'package:flutter/material.dart';

import '../../models/api/url_reputation.dart';
import '../../models/api/threat_indicator.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/url_provider.dart';

/// URL safety badge
class UrlSafetyBadge extends StatelessWidget {
  final bool isSafe;
  final SeverityLevel? severity;
  final bool compact;

  const UrlSafetyBadge({
    super.key,
    required this.isSafe,
    this.severity,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSafe
        ? AppColors.accentInk
        : (severity != null ? Color(severity!.color) : AppColors.error);
    final label = isSafe ? 'Safe' : (severity?.displayName ?? 'Unsafe');
    final icon = isSafe ? AppIcons.shieldCheck : AppIcons.dangerTriangle;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(50),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: compact ? 14 : 16, color: color),
          SizedBox(width: compact ? 4 : 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// URL category chip
class UrlCategoryChip extends StatelessWidget {
  final UrlCategory category;

  const UrlCategoryChip({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final color = _getCategoryColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      ),
      child: Text(
        category.displayName,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getCategoryColor(BuildContext context) {
    switch (category) {
      case UrlCategory.safe:
        return AppColors.accentInk;
      case UrlCategory.phishing:
      case UrlCategory.malware:
      case UrlCategory.scam:
        return AppColors.errorInk;
      case UrlCategory.spam:
      case UrlCategory.suspiciousTld:
      case UrlCategory.typosquatting:
        return AppColors.secondaryInk;
      case UrlCategory.adult:
      case UrlCategory.gambling:
      case UrlCategory.drugs:
      case UrlCategory.violence:
        return AppColors.chartColors[4];
      case UrlCategory.ads:
      case UrlCategory.tracking:
        return AppColors.amberInk;
      case UrlCategory.cryptomining:
        return AppColors.errorInk;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}

/// URL check result card
class UrlResultCard extends StatelessWidget {
  final UrlReputationResult result;
  final VoidCallback? onTap;
  final VoidCallback? onWhitelist;
  final VoidCallback? onBlacklist;

  const UrlResultCard({
    super.key,
    required this.result,
    this.onTap,
    this.onWhitelist,
    this.onBlacklist,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = result.isSafe
        ? AppColors.accentInk.withAlpha(75)
        : Color(result.severity.color).withAlpha(75);

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
                DuotoneIcon(
                  result.isSafe ? AppIcons.checkCircle : AppIcons.dangerCircle,
                  color: result.isSafe
                      ? AppColors.accentInk
                      : Color(result.severity.color),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.domain,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.url,
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
                UrlSafetyBadge(
                  isSafe: result.isSafe,
                  severity: result.severity,
                  compact: true,
                ),
              ],
            ),

            // Categories
            if (result.categories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: result.categories.take(4).map((c) {
                  return UrlCategoryChip(category: c);
                }).toList(),
              ),
            ],

            // Threats
            if (result.threats.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(25),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DuotoneIcon(AppIcons.dangerTriangle,
                            size: 16, color: AppColors.errorInk),
                        const SizedBox(width: 6),
                        Text(
                          '${result.threats.length} threat${result.threats.length > 1 ? 's' : ''} detected',
                          style: TextStyle(
                            color: AppColors.errorInk,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    ...result.threats.take(2).map((t) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '• ${t.description}',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                ),
              ),
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
                      backgroundColor: cs.onSurface.withValues(alpha: 0.06),
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
          ],
        ),
      ),
    );
  }

  Color _getRiskColor(double score) {
    if (score >= 0.7) return AppColors.errorInk;
    if (score >= 0.4) return AppColors.amberInk;
    if (score >= 0.2) return AppColors.amberInk;
    return AppColors.accentInk;
  }
}

/// URL history item
class UrlHistoryItem extends StatelessWidget {
  final UrlCheckEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const UrlHistoryItem({
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
                        result?.isSafe == true ? AppIcons.checkCircle : AppIcons.dangerTriangle,
                        size: 18,
                        color: _getStatusColor(),
                      ),
              ),
            ),
            const SizedBox(width: 12),

            // URL info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result?.domain ?? _extractDomain(entry.url),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(entry.checkedAt),
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

            // Actions
            if (result != null && !entry.isPending) ...[
              UrlSafetyBadge(
                isSafe: result.isSafe,
                severity: result.severity,
                compact: true,
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: DuotoneIcon(AppIcons.closeCircle,
                      size: 18,
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
    if (entry.result?.isSafe == true) return AppColors.accentInk;
    return AppColors.errorInk;
  }

  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return url;
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

/// URL input widget
class UrlInputWidget extends StatefulWidget {
  final Function(String url) onCheck;
  final bool isChecking;

  const UrlInputWidget({
    super.key,
    required this.onCheck,
    this.isChecking = false,
  });

  @override
  State<UrlInputWidget> createState() => _UrlInputWidgetState();
}

class _UrlInputWidgetState extends State<UrlInputWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleCheck() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onCheck(_controller.text.trim());
    }
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
            'Check URL Safety',
            style: BrandText.title(size: 16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter a URL to check if it\'s safe to visit',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _handleCheck(),
            decoration: InputDecoration(
              hintText: 'example.com or https://...',
              hintStyle: TextStyle(color: cs.onSurfaceVariant),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              prefixIcon: DuotoneIcon(
                AppIcons.urlProtection,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.isChecking ? null : _handleCheck,
            style: ElevatedButton.styleFrom(
              backgroundColor: Brand.lime,
              foregroundColor: Brand.onLime,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
            ),
            icon: widget.isChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Brand.onLime),
                    ),
                  )
                : const DuotoneIcon(AppIcons.search, size: 20, color: Brand.onLime),
            label: Text(widget.isChecking ? 'Checking...' : 'Check URL'),
          ),
        ],
      ),
    );
  }
}

/// URL protection stats card
class UrlStatsCard extends StatelessWidget {
  final UrlStats stats;

  const UrlStatsCard({super.key, required this.stats});

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
                  color: AppColors.primary.withAlpha(50),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: DuotoneIcon(
                  AppIcons.globus,
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
                      'Web Protection',
                      style: BrandText.title(size: 16, weight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'URL scanning & phishing protection',
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
                label: 'Checked',
                value: stats.totalChecked.toString(),
                color: cs.onSurface,
              ),
              _StatItem(
                label: 'Safe',
                value: stats.safeSites.toString(),
                color: AppColors.accentInk,
              ),
              _StatItem(
                label: 'Blocked',
                value: stats.threatsBlocked.toString(),
                color: AppColors.errorInk,
              ),
            ],
          ),
          if (stats.threatsBlocked > 0) ...[
            const SizedBox(height: 16),
            Text(
              'Threats Blocked',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ThreatTypeChip(
                  label: 'Phishing',
                  count: stats.phishingBlocked,
                  color: AppColors.secondaryInk,
                ),
                const SizedBox(width: 8),
                _ThreatTypeChip(
                  label: 'Malware',
                  count: stats.malwareBlocked,
                  color: AppColors.errorInk,
                ),
                const SizedBox(width: 8),
                _ThreatTypeChip(
                  label: 'Scams',
                  count: stats.scamsBlocked,
                  color: AppColors.chartColors[4],
                ),
              ],
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

class _ThreatTypeChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _ThreatTypeChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Domain details card
class DomainDetailsCard extends StatelessWidget {
  final DomainReputation domain;

  const DomainDetailsCard({super.key, required this.domain});

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              DuotoneIcon(AppIcons.infoCircle,
                  size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Domain Information',
                style: BrandText.title(size: 14, weight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getScoreColor(domain.reputationScore).withAlpha(40),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
                child: Text(
                  '${domain.reputationScore.toInt()}/100',
                  style: TextStyle(
                    color: _getScoreColor(domain.reputationScore),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Info rows
          _InfoRow(label: 'Domain', value: domain.domain),
          if (domain.registrar != null)
            _InfoRow(label: 'Registrar', value: domain.registrar!),
          _InfoRow(label: 'Age', value: '${domain.ageInDays} days'),
          if (domain.registrantCountry != null)
            _InfoRow(label: 'Country', value: domain.registrantCountry!),
          if (domain.asnOrg != null)
            _InfoRow(label: 'ASN Org', value: domain.asnOrg!),

          // Warnings
          if (domain.isNewlyRegistered ||
              domain.isOnBlocklist ||
              domain.isSuspicious) ...[
            const SizedBox(height: 12),
            if (domain.isNewlyRegistered)
              _WarningRow(
                text: 'Newly registered domain (< 30 days)',
                color: AppColors.secondaryInk,
              ),
            if (domain.isOnBlocklist)
              _WarningRow(
                text: 'Domain is on blocklists',
                color: AppColors.errorInk,
              ),
          ],

          // SSL info
          if (domain.ssl != null) ...[
            const SizedBox(height: 12),
            _SslSection(ssl: domain.ssl!),
          ],
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 70) return AppColors.accentInk;
    if (score >= 40) return AppColors.amberInk;
    return AppColors.errorInk;
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label:',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningRow extends StatelessWidget {
  final String text;
  final Color color;

  const _WarningRow({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          DuotoneIcon(AppIcons.dangerTriangle, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SslSection extends StatelessWidget {
  final SslInfo ssl;

  const _SslSection({required this.ssl});

  @override
  Widget build(BuildContext context) {
    final color = ssl.hasValidSsl && !ssl.isExpired
        ? AppColors.accentInk
        : AppColors.errorInk;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      ),
      child: Row(
        children: [
          DuotoneIcon(
            ssl.hasValidSsl ? AppIcons.lock : AppIcons.lockUnlocked,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ssl.hasValidSsl ? 'Valid SSL Certificate' : 'No SSL Certificate',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ssl.issuer != null)
                  Text(
                    'Issued by: ${ssl.issuer}',
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
          if (ssl.grade != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(50),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Text(
                ssl.grade!,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// List management widget (whitelist/blacklist)
class UrlListTile extends StatelessWidget {
  final UrlListEntry entry;
  final VoidCallback? onRemove;

  const UrlListTile({
    super.key,
    required this.entry,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: DuotoneIcon(AppIcons.globus, color: cs.onSurfaceVariant),
      title: Text(
        entry.domain,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Added ${_formatDate(entry.addedAt)}',
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 12,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: DuotoneIcon(AppIcons.minusCircle, color: AppColors.errorInk),
        color: AppColors.errorInk,
        onPressed: onRemove,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
