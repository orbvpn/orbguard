/// SMS Widgets
/// Reusable widgets for SMS protection screens

import 'package:flutter/material.dart';

import '../../models/api/sms_analysis.dart';
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
        color: Color(level.color).withOpacity(0.2),
        borderRadius: BorderRadius.circular(compact ? 4 : 8),
        border: Border.all(
          color: Color(level.color).withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(
            _getIcon(),
            size: compact ? 12 : 14,
            color: Color(level.color),
          ),
          SizedBox(width: compact ? 2 : 4),
          Text(
            level.displayName,
            style: TextStyle(
              color: Color(level.color),
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
    final hasAnalysis = message.analysisResult != null;
    final threatLevel = message.threatLevel;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(12),
          border: hasAnalysis && threatLevel != SmsThreatLevel.safe
              ? Border.all(
                  color: Color(threatLevel.color).withOpacity(0.3),
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
                    color: _getSenderColor().withOpacity(0.2),
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
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Threat badge or analyze button
                if (message.isAnalyzing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF00D9FF)),
                    ),
                  )
                else if (hasAnalysis)
                  ThreatLevelBadge(level: threatLevel, compact: true)
                else if (onAnalyze != null)
                  IconButton(
                    icon: const DuotoneIcon(AppIcons.shieldCheck, size: 20, color: Color(0xFF00D9FF)),
                    color: const Color(0xFF00D9FF),
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
                color: Colors.grey[300],
                fontSize: 14,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),

            // Threat info if dangerous
            if (hasAnalysis && message.analysisResult!.hasThreats) ...[
              const SizedBox(height: 12),
              _buildThreatInfo(),
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

  Widget _buildThreatInfo() {
    final threats = message.analysisResult!.threats;
    if (threats.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color(message.threatLevel.color).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon(
                AppIcons.dangerTriangle,
                size: 16,
                color: Color(message.threatLevel.color),
              ),
              const SizedBox(width: 6),
              Text(
                'Detected Threats',
                style: TextStyle(
                  color: Color(message.threatLevel.color),
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
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
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
                  color: Colors.grey[500],
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
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const DuotoneIcon(AppIcons.urlProtection, size: 14, color: Colors.red),
          const SizedBox(width: 6),
          Text(
            '${maliciousUrls.length} malicious URL${maliciousUrls.length > 1 ? 's' : ''}',
            style: const TextStyle(
              color: Colors.red,
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
    final colors = [
      const Color(0xFF00D9FF),
      const Color(0xFF9C27B0),
      const Color(0xFFFF9800),
      const Color(0xFF4CAF50),
      const Color(0xFFE91E63),
    ];
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
                  color: const Color(0xFF00D9FF).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const DuotoneIcon(
                  AppIcons.chatDots,
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
                      'SMS Protection',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Smishing & phishing detection',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
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
                color: Colors.white,
              ),
              _StatItem(
                label: 'Analyzed',
                value: stats.analyzedMessages.toString(),
                color: const Color(0xFF00D9FF),
              ),
              _StatItem(
                label: 'Threats',
                value: stats.threatsDetected.toString(),
                color: stats.threatsDetected > 0 ? Colors.orange : Colors.green,
              ),
              _StatItem(
                label: 'Blocked',
                value: stats.blockedSenders.toString(),
                color: Colors.red,
              ),
            ],
          ),
          if (stats.criticalThreats > 0 || stats.highThreats > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const DuotoneIcon(AppIcons.dangerCircle, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${stats.criticalThreats} critical, ${stats.highThreats} high severity threats',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
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
    final isSelected = filter == selectedFilter;

    return GestureDetector(
      onTap: () => onSelected(filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00D9FF).withOpacity(0.2)
              : const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00D9FF)
                : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Text(
          _getLabel(),
          style: TextStyle(
            color: isSelected ? const Color(0xFF00D9FF) : Colors.grey[400],
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
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sender Analysis',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: AppIcons.smartphone,
            label: 'Sender',
            value: analysis.sender,
          ),
          if (analysis.isKnownSpammer)
            const _InfoRow(
              icon: AppIcons.forbidden,
              label: 'Status',
              value: 'Known Spammer',
              valueColor: Colors.red,
            ),
          if (analysis.isSpoofed)
            _InfoRow(
              icon: AppIcons.dangerTriangle,
              label: 'Spoofed',
              value: analysis.spoofedBrand ?? 'Yes',
              valueColor: Colors.orange,
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
                      const DuotoneIcon(AppIcons.dangerTriangle,
                          size: 14, color: Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          w,
                          style: TextStyle(
                            color: Colors.grey[400],
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
    if (score >= 0.7) return Colors.red;
    if (score >= 0.4) return Colors.orange;
    return Colors.green;
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          DuotoneIcon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(threat.severity.color).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Color(threat.severity.color).withOpacity(0.3),
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
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(threat.severity.color).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
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
              color: Colors.grey[300],
              fontSize: 13,
            ),
          ),
          if (threat.evidence != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const DuotoneIcon(AppIcons.quoteDown, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      threat.evidence!,
                      style: TextStyle(
                        color: Colors.grey[400],
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
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    t,
                    style: const TextStyle(
                      color: Colors.grey,
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
    final color = url.isMalicious ? Colors.red : Colors.green;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
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
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'SHORTENER',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              url.url,
              style: TextStyle(
                color: Colors.grey[500],
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
                      color: Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        color: Colors.grey[400],
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
            'Check a Message',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Paste a suspicious message to analyze',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _senderController,
            decoration: InputDecoration(
              hintText: 'Sender (optional)',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF0A0E21),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
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
                : const DuotoneIcon(AppIcons.search, size: 20, color: Colors.black),
            label: Text(widget.isAnalyzing ? 'Analyzing...' : 'Analyze'),
          ),
        ],
      ),
    );
  }
}
