/// SMS Detail Screen
/// Detailed view of a single SMS message with threat analysis
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/api/sms_analysis.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/sms_provider.dart';
import '../../widgets/sms/sms_widgets.dart';

/// SMS detail screen
class SmsDetailScreen extends StatefulWidget {
  final SmsMessage message;
  final SmsProvider provider;

  const SmsDetailScreen({
    super.key,
    required this.message,
    required this.provider,
  });

  @override
  State<SmsDetailScreen> createState() => _SmsDetailScreenState();
}

class _SmsDetailScreenState extends State<SmsDetailScreen> {
  late SmsMessage _message;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    widget.provider.addListener(_onProviderChanged);
    widget.provider.markAsRead(_message.id);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    // Find updated message
    final updated = widget.provider.allMessages.firstWhere(
      (m) => m.id == _message.id,
      orElse: () => _message,
    );
    if (mounted) {
      setState(() {
        _message = updated;
      });
    }
  }

  Future<void> _analyzeMessage() async {
    setState(() {
      _isAnalyzing = true;
    });

    await widget.provider.analyzeMessage(_message.id);

    if (mounted) {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  void _blockSender() {
    widget.provider.blockSender(_message.sender);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Blocked ${_message.sender}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.provider.unblockSender(_message.sender),
        ),
      ),
    );
  }

  void _reportFalsePositive() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Report False Positive'),
        content: const Text(
          'Are you sure this message is safe? This helps improve our detection accuracy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.provider.reportFalsePositive(_message.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report submitted. Thank you!')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Brand.onLime,
            ),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  void _deleteMessage() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Delete Message'),
        content: const Text(
          'Are you sure you want to delete this message from OrbGuard?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.provider.deleteMessage(_message.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Brand.onDanger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _copyContent() {
    Clipboard.setData(ClipboardData(text: _message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAnalysis = _message.analysisResult != null;
    final analysis = _message.analysisResult;
    final isBlocked = widget.provider.isSenderBlocked(_message.sender);

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Message Details'),
        actions: [
          PopupMenuButton<String>(
            icon: DuotoneIcon('menu_dots', color: cs.onSurface, size: 24),
            color: cs.surface,
            onSelected: (value) {
              switch (value) {
                case 'copy':
                  _copyContent();
                  break;
                case 'block':
                  _blockSender();
                  break;
                case 'unblock':
                  widget.provider.unblockSender(_message.sender);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Unblocked ${_message.sender}')),
                  );
                  break;
                case 'report':
                  _reportFalsePositive();
                  break;
                case 'delete':
                  _deleteMessage();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: DuotoneIcon('copy', size: 20, color: cs.onSurface),
                  title: const Text('Copy message'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: isBlocked ? 'unblock' : 'block',
                child: ListTile(
                  leading: DuotoneIcon(
                    isBlocked ? 'check_circle' : 'forbidden',
                    size: 20,
                    color: isBlocked ? AppColors.accentInk : AppColors.errorInk,
                  ),
                  title: Text(isBlocked ? 'Unblock sender' : 'Block sender'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (hasAnalysis && _message.hasThreats)
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: DuotoneIcon('flag', size: 20, color: cs.onSurface),
                    title: const Text('Report false positive'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: DuotoneIcon('trash_bin_minimalistic', size: 20, color: AppColors.errorInk),
                  title: Text('Delete', style: TextStyle(color: AppColors.errorInk)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sender info
            _buildSenderCard(isBlocked),
            const SizedBox(height: 24),

            // Message content
            _buildMessageCard(),
            const SizedBox(height: 24),

            // Analysis or analyze button
            if (_isAnalyzing || _message.isAnalyzing)
              _buildAnalyzingCard()
            else if (!hasAnalysis)
              _buildAnalyzeButton()
            else ...[
              // Threat level summary
              _buildThreatSummary(analysis!),
              const SizedBox(height: 24),

              // Detected threats
              if (analysis.threats.isNotEmpty) ...[
                _buildSection('Detected Threats'),
                ...analysis.threats.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ThreatDetailCard(threat: t),
                    )),
                const SizedBox(height: 8),
              ],

              // Extracted URLs
              if (analysis.extractedUrls.isNotEmpty) ...[
                _buildSection('Extracted URLs'),
                ...analysis.extractedUrls.map((url) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: UrlAnalysisCard(url: url),
                    )),
                const SizedBox(height: 8),
              ],

              // Detected intents
              if (analysis.detectedIntents.isNotEmpty) ...[
                _buildSection('Suspicious Intents'),
                _buildIntentsChips(analysis.detectedIntents),
                const SizedBox(height: 24),
              ],

              // Sender analysis
              if (analysis.senderAnalysis != null) ...[
                _buildSection('Sender Analysis'),
                SenderAnalysisCard(analysis: analysis.senderAnalysis!),
                const SizedBox(height: 24),
              ],

              // Matched patterns
              if (analysis.matchedPatterns.isNotEmpty) ...[
                _buildSection('Matched Patterns'),
                _buildPatternChips(analysis.matchedPatterns),
                const SizedBox(height: 24),
              ],

              // Re-analyze button
              OutlinedButton.icon(
                onPressed: _analyzeMessage,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentInk,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: DuotoneIcon('refresh', size: 18, color: AppColors.accentInk),
                label: const Text('Re-analyze'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSenderCard(bool isBlocked) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getSenderColor().withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _getSenderInitial(),
                style: TextStyle(
                  color: _getSenderColor(),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _message.sender,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (isBlocked) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withAlpha(50),
                          borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                        ),
                        child: Text(
                          'BLOCKED',
                          style: TextStyle(
                            color: AppColors.errorInk,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(_message.timestamp), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // Threat badge
          if (_message.analysisResult != null)
            ThreatLevelBadge(level: _message.threatLevel),
        ],
      ),
    );
  }

  Widget _buildMessageCard() {
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
          Row(
            children: [
              const Text(
                'Message',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: DuotoneIcon('copy', size: 18, color: cs.onSurface),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _copyContent,
                tooltip: 'Copy',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            _message.content,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(AppColors.accentInk),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Analyzing message...',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Checking for phishing, malware links, and suspicious patterns',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
        border: Border.all(
          color: AppColors.accentInk.withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          DuotoneIcon(
            'shield_check',
            size: 48,
            color: AppColors.accentInk,
          ),
          const SizedBox(height: 16),
          const Text(
            'Message not analyzed',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Analyze this message to detect phishing and other threats',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _analyzeMessage,
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Brand.onLime,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
            icon: const DuotoneIcon('magnifer', size: 18, color: Brand.onLime),
            label: const Text('Analyze Message'),
          ),
        ],
      ),
    );
  }

  Widget _buildThreatSummary(SmsAnalysisResult analysis) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(analysis.threatLevel.color).withAlpha(25),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
        border: Border.all(
          color: Color(analysis.threatLevel.color).withAlpha(75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThreatLevelBadge(level: analysis.threatLevel),
              const Spacer(),
              Text(
                'Risk: ${(analysis.riskScore * 100).toInt()}%',
                style: TextStyle(
                  color: AppColors.glyphInk(Color(analysis.threatLevel.color)),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (analysis.recommendation != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DuotoneIcon(
                  'lightbulb',
                  color: AppColors.glyphInk(Color(analysis.threatLevel.color)),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    analysis.recommendation!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (analysis.shouldBlock) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(50),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Row(
                children: [
                  DuotoneIcon('danger_triangle', color: AppColors.errorInk, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This message should be blocked',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.errorInk,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (!widget.provider.isSenderBlocked(_message.sender))
                    TextButton(
                      onPressed: _blockSender,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.errorInk,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Block'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildIntentsChips(List<SuspiciousIntent> intents) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: intents.map((intent) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.warning.withAlpha(50),
            borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
            border: Border.all(color: AppColors.warning.withAlpha(75)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DuotoneIcon(
                _getIntentSvgIcon(intent),
                size: 14,
                color: AppColors.secondaryInk,
              ),
              const SizedBox(width: 6),
              Text(
                intent.value.toUpperCase(),
                style: TextStyle(
                  color: AppColors.secondaryInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _getIntentSvgIcon(SuspiciousIntent intent) {
    switch (intent) {
      case SuspiciousIntent.urgency:
        return 'stopwatch';
      case SuspiciousIntent.fear:
        return 'danger_triangle';
      case SuspiciousIntent.reward:
        return 'gift';
      case SuspiciousIntent.curiosity:
        return 'question_circle';
      case SuspiciousIntent.authority:
        return 'clipboard_text';
      case SuspiciousIntent.social:
        return 'users_group_rounded';
      case SuspiciousIntent.greed:
        return 'dollar';
      case SuspiciousIntent.none:
        return 'check_circle';
    }
  }

  Widget _buildPatternChips(List<String> patterns) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: patterns.map((pattern) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
          ),
          child: Text(
            pattern,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _getSenderColor() {
    if (_message.hasThreats) {
      return Color(_message.threatLevel.color);
    }
    final hash = _message.sender.hashCode;
    // Brand spectrum family (chartColors), skipping the danger red so a safe
    // sender never gets a threat-colored avatar.
    final colors = [
      AppColors.chartColors[2], // cyan
      AppColors.chartColors[4], // light-purple
      AppColors.chartColors[5], // gold
      AppColors.chartColors[6], // mint
      AppColors.chartColors[1], // pink
    ];
    return colors[hash.abs() % colors.length];
  }

  String _getSenderInitial() {
    final sender = _message.sender.trim();
    if (sender.isEmpty) return '?';
    if (RegExp(r'^[\d\s\+\-\(\)]+$').hasMatch(sender)) {
      return '#';
    }
    return sender[0].toUpperCase();
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    String time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    if (diff.inDays == 0) {
      return 'Today at $time';
    } else if (diff.inDays == 1) {
      return 'Yesterday at $time';
    } else if (diff.inDays < 7) {
      final weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dt.weekday - 1];
      return '$weekday at $time';
    } else {
      return '${dt.day}/${dt.month}/${dt.year} at $time';
    }
  }
}
