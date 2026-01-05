/// SMS Detail Screen
/// Detailed view of a single SMS message with threat analysis

library sms_detail_screen;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/api/sms_analysis.dart';
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
        backgroundColor: const Color(0xFF1D1E33),
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
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.black,
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
        backgroundColor: const Color(0xFF1D1E33),
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
              backgroundColor: Colors.red,
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

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E21),
        elevation: 0,
        title: const Text('Message Details'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: const Color(0xFF1D1E33),
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
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy, size: 20),
                  title: Text('Copy message'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: isBlocked ? 'unblock' : 'block',
                child: ListTile(
                  leading: Icon(
                    isBlocked ? Icons.check_circle : Icons.block,
                    size: 20,
                    color: isBlocked ? Colors.green : Colors.red,
                  ),
                  title: Text(isBlocked ? 'Unblock sender' : 'Block sender'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (hasAnalysis && _message.hasThreats)
                const PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    leading: Icon(Icons.flag, size: 20),
                    title: Text('Report false positive'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete, size: 20, color: Colors.red),
                  title: Text('Delete', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sender info
            _buildSenderCard(isBlocked),
            const SizedBox(height: 16),

            // Message content
            _buildMessageCard(),
            const SizedBox(height: 16),

            // Analysis or analyze button
            if (_isAnalyzing || _message.isAnalyzing)
              _buildAnalyzingCard()
            else if (!hasAnalysis)
              _buildAnalyzeButton()
            else ...[
              // Threat level summary
              _buildThreatSummary(analysis!),
              const SizedBox(height: 16),

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
                const SizedBox(height: 16),
              ],

              // Sender analysis
              if (analysis.senderAnalysis != null) ...[
                _buildSection('Sender Analysis'),
                SenderAnalysisCard(analysis: analysis.senderAnalysis!),
                const SizedBox(height: 16),
              ],

              // Matched patterns
              if (analysis.matchedPatterns.isNotEmpty) ...[
                _buildSection('Matched Patterns'),
                _buildPatternChips(analysis.matchedPatterns),
                const SizedBox(height: 16),
              ],

              // Re-analyze button
              OutlinedButton.icon(
                onPressed: _analyzeMessage,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00D9FF),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Re-analyze'),
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSenderCard(bool isBlocked) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
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
                          color: Colors.red.withAlpha(50),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'BLOCKED',
                          style: TextStyle(
                            color: Colors.red,
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
                  _formatDateTime(_message.timestamp),
                  style: TextStyle(
                    color: Colors.grey[500],
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
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
                icon: const Icon(Icons.copy, size: 18),
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
              color: Colors.grey[300],
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
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(Color(0xFF00D9FF)),
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
              color: Colors.grey[500],
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
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00D9FF).withAlpha(50),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.security,
            size: 48,
            color: Color(0xFF00D9FF),
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
            'Analyze this message to detect phishing, smishing, and other threats',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _analyzeMessage,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
            icon: const Icon(Icons.search, size: 18),
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
        borderRadius: BorderRadius.circular(12),
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
                  color: Color(analysis.threatLevel.color),
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
                Icon(
                  Icons.lightbulb_outline,
                  color: Color(analysis.threatLevel.color),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    analysis.recommendation!,
                    style: TextStyle(
                      color: Colors.grey[300],
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
                color: Colors.red.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This message should be blocked',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (!widget.provider.isSenderBlocked(_message.sender))
                    TextButton(
                      onPressed: _blockSender,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
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
            color: Colors.orange.withAlpha(50),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withAlpha(75)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getIntentIcon(intent),
                size: 14,
                color: Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                intent.value.toUpperCase(),
                style: const TextStyle(
                  color: Colors.orange,
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

  IconData _getIntentIcon(SuspiciousIntent intent) {
    switch (intent) {
      case SuspiciousIntent.urgency:
        return Icons.timer;
      case SuspiciousIntent.fear:
        return Icons.warning;
      case SuspiciousIntent.reward:
        return Icons.card_giftcard;
      case SuspiciousIntent.curiosity:
        return Icons.help;
      case SuspiciousIntent.authority:
        return Icons.gavel;
      case SuspiciousIntent.social:
        return Icons.people;
      case SuspiciousIntent.greed:
        return Icons.attach_money;
      case SuspiciousIntent.none:
        return Icons.check;
    }
  }

  Widget _buildPatternChips(List<String> patterns) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: patterns.map((pattern) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.withAlpha(50),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            pattern,
            style: const TextStyle(
              color: Colors.grey,
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
