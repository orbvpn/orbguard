/// URL Widgets
/// Reusable widgets for URL/web protection screens
library url_widgets;

import 'package:flutter/material.dart';

import '../../models/api/url_reputation.dart';
import '../../models/api/threat_indicator.dart';
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
    final color = isSafe ? Colors.green : Color(severity?.color ?? 0xFFE53935);
    final label = isSafe ? 'Safe' : (severity?.displayName ?? 'Unsafe');
    final icon = isSafe ? AppIcons.shieldCheck : AppIcons.dangerTriangle;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(50),
        borderRadius: BorderRadius.circular(compact ? 4 : 8),
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
    final color = _getCategoryColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
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

  Color _getCategoryColor() {
    switch (category) {
      case UrlCategory.safe:
        return Colors.green;
      case UrlCategory.phishing:
      case UrlCategory.malware:
      case UrlCategory.scam:
        return Colors.red;
      case UrlCategory.spam:
      case UrlCategory.suspiciousTld:
      case UrlCategory.typosquatting:
        return Colors.orange;
      case UrlCategory.adult:
      case UrlCategory.gambling:
      case UrlCategory.drugs:
      case UrlCategory.violence:
        return Colors.purple;
      case UrlCategory.ads:
      case UrlCategory.tracking:
        return Colors.amber;
      case UrlCategory.cryptomining:
        return Colors.deepOrange;
      default:
        return Colors.grey;
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
    final borderColor = result.isSafe
        ? Colors.green.withAlpha(75)
        : Color(result.severity.color).withAlpha(75);

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                DuotoneIcon(
                  result.isSafe ? AppIcons.checkCircle : AppIcons.dangerCircle,
                  color: result.isSafe ? Colors.green : Color(result.severity.color),
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
                          color: Colors.grey[500],
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
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const DuotoneIcon(AppIcons.dangerTriangle, size: 16, color: Colors.red),
                        const SizedBox(width: 6),
                        Text(
                          '${result.threats.length} threat${result.threats.length > 1 ? 's' : ''} detected',
                          style: const TextStyle(
                            color: Colors.red,
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
                              color: Colors.grey[400],
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
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.recommendation!,
                      style: TextStyle(
                        color: Colors.grey[400],
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
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: result.riskScore,
                      backgroundColor: Colors.grey.withAlpha(50),
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
    if (score >= 0.7) return Colors.red;
    if (score >= 0.4) return Colors.orange;
    if (score >= 0.2) return Colors.amber;
    return Colors.green;
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
      borderRadius: BorderRadius.circular(8),
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
                      color: Colors.grey[500],
                      fontSize: 11,
                    ),
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
                  icon: const DuotoneIcon(AppIcons.closeCircle, size: 18, color: Colors.grey),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: Colors.grey,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    if (entry.isPending) return const Color(0xFF00D9FF);
    if (entry.result?.isSafe == true) return Colors.green;
    return Colors.red;
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Check URL Safety',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter a URL to check if it\'s safe to visit',
            style: TextStyle(
              color: Colors.grey[500],
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
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF0A0E21),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              prefixIcon: DuotoneIcon(
                AppIcons.urlProtection,
                color: Colors.grey[500],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.isChecking ? null : _handleCheck,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: widget.isChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.black),
                    ),
                  )
                : const DuotoneIcon(AppIcons.search, size: 20, color: Colors.black),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D9FF).withAlpha(50),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const DuotoneIcon(
                  AppIcons.globus,
                  color: Color(0xFF00D9FF),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Web Protection',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'URL scanning & phishing protection',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
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
                color: Colors.white,
              ),
              _StatItem(
                label: 'Safe',
                value: stats.safeSites.toString(),
                color: Colors.green,
              ),
              _StatItem(
                label: 'Blocked',
                value: stats.threatsBlocked.toString(),
                color: Colors.red,
              ),
            ],
          ),
          if (stats.threatsBlocked > 0) ...[
            const SizedBox(height: 16),
            const Text(
              'Threats Blocked',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ThreatTypeChip(
                  label: 'Phishing',
                  count: stats.phishingBlocked,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                _ThreatTypeChip(
                  label: 'Malware',
                  count: stats.malwareBlocked,
                  color: Colors.red,
                ),
                const SizedBox(width: 8),
                _ThreatTypeChip(
                  label: 'Scams',
                  count: stats.scamsBlocked,
                  color: Colors.purple,
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
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
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
        borderRadius: BorderRadius.circular(12),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const DuotoneIcon(AppIcons.infoCircle, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              const Text(
                'Domain Information',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getScoreColor(domain.reputationScore).withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
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
                color: Colors.orange,
              ),
            if (domain.isOnBlocklist)
              _WarningRow(
                text: 'Domain is on blocklists',
                color: Colors.red,
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
    if (score >= 70) return Colors.green;
    if (score >= 40) return Colors.orange;
    return Colors.red;
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
              color: Colors.grey[500],
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.end,
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
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
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
    final color = ssl.hasValidSsl && !ssl.isExpired ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
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
                ),
                if (ssl.issuer != null)
                  Text(
                    'Issued by: ${ssl.issuer}',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (ssl.grade != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(50),
                borderRadius: BorderRadius.circular(4),
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
    return ListTile(
      leading: const DuotoneIcon(AppIcons.globus, color: Colors.grey),
      title: Text(entry.domain),
      subtitle: Text(
        'Added ${_formatDate(entry.addedAt)}',
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 12,
        ),
      ),
      trailing: IconButton(
        icon: const DuotoneIcon(AppIcons.minusCircle, color: Colors.red),
        color: Colors.red,
        onPressed: onRemove,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
