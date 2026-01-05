/// QR Widgets
/// Reusable widgets for QR code scanning screens
library qr_widgets;

import 'package:flutter/material.dart';

import '../../models/api/sms_analysis.dart';
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
    final borderColor = result.threatLevel == SmsThreatLevel.safe
        ? Colors.green.withAlpha(75)
        : Color(result.threatLevel.color).withAlpha(75);

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
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatContent(result.content),
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
                  Icon(
                    Icons.lightbulb_outline,
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
                        foregroundColor: Colors.red,
                      ),
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Block'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                      ),
                      icon: const Icon(Icons.copy, size: 18),
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
    if (score >= 0.7) return Colors.red;
    if (score >= 0.4) return Colors.orange;
    if (score >= 0.2) return Colors.amber;
    return Colors.green;
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
        borderRadius: BorderRadius.circular(compact ? 4 : 8),
        border: Border.all(color: Color(level.color).withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
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

  IconData _getIcon() {
    switch (level) {
      case SmsThreatLevel.safe:
        return Icons.verified_user;
      case SmsThreatLevel.suspicious:
        return Icons.warning;
      case SmsThreatLevel.dangerous:
        return Icons.dangerous;
      case SmsThreatLevel.critical:
        return Icons.error;
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
        color: const Color(0xFF00D9FF).withAlpha(40),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Icon(
          _getIcon(),
          color: const Color(0xFF00D9FF),
          size: 22,
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (contentType.toLowerCase()) {
      case 'url':
        return Icons.link;
      case 'text':
        return Icons.text_fields;
      case 'email':
        return Icons.email;
      case 'phone':
        return Icons.phone;
      case 'sms':
        return Icons.sms;
      case 'wifi':
        return Icons.wifi;
      case 'vcard':
        return Icons.contact_page;
      case 'geo':
        return Icons.location_on;
      case 'event':
        return Icons.event;
      case 'crypto':
        return Icons.currency_bitcoin;
      case 'app_link':
        return Icons.apps;
      default:
        return Icons.qr_code;
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
        color: Colors.red.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, size: 16, color: Colors.red),
              const SizedBox(width: 6),
              Text(
                '${threats.length} threat${threats.length > 1 ? 's' : ''} detected',
                style: const TextStyle(
                  color: Colors.red,
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
                          color: Colors.grey[400],
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
                    : Icon(
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
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(entry.scannedAt),
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                    ),
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
                  icon: const Icon(Icons.close, size: 18),
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
    if (entry.isSafe) return Colors.green;
    return Colors.red;
  }

  IconData _getContentIcon() {
    final type = entry.contentType ?? entry.result?.contentType ?? 'unknown';
    switch (type.toLowerCase()) {
      case 'url':
        return Icons.link;
      case 'wifi':
        return Icons.wifi;
      case 'phone':
        return Icons.phone;
      case 'email':
        return Icons.email;
      default:
        return Icons.qr_code;
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
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
                  color: const Color(0xFF00D9FF).withAlpha(50),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
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
                      'QR Security',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Quishing & malicious QR protection',
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
                label: 'Scanned',
                value: stats.totalScanned.toString(),
                color: Colors.white,
              ),
              _StatItem(
                label: 'Safe',
                value: stats.safeScans.toString(),
                color: Colors.green,
              ),
              _StatItem(
                label: 'Flagged',
                value: stats.threatsFlagged.toString(),
                color: stats.threatsFlagged > 0 ? Colors.red : Colors.grey,
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
        Container(color: Colors.black.withAlpha(100)),

        // Scan area
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFF00D9FF),
              width: 3,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        // Corner accents
        Positioned(
          top: (MediaQuery.of(context).size.height - size) / 2 - 20,
          child: Text(
            'Scan QR Code',
            style: TextStyle(
              color: Colors.white.withAlpha(200),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Check QR Content',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Paste QR code content to analyze for threats',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Paste URL, text, or any QR content...',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF0A0E21),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
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
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: widget.isAnalyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.black),
                    ),
                  )
                : const Icon(Icons.search, size: 20),
            label: Text(widget.isAnalyzing ? 'Analyzing...' : 'Analyze'),
          ),
        ],
      ),
    );
  }
}
