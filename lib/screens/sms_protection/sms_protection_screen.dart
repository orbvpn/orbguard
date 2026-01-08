/// SMS Protection Screen
/// Main screen for SMS/smishing protection

library sms_protection_screen;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../models/api/sms_analysis.dart';
import '../../providers/sms_provider.dart';
import '../../widgets/sms/sms_widgets.dart';
import 'sms_detail_screen.dart';

/// Main SMS protection screen
class SmsProtectionScreen extends StatefulWidget {
  const SmsProtectionScreen({super.key});

  @override
  State<SmsProtectionScreen> createState() => _SmsProtectionScreenState();
}

class _SmsProtectionScreenState extends State<SmsProtectionScreen>
    with SingleTickerProviderStateMixin {
  final SmsProvider _provider = SmsProvider();
  late TabController _tabController;
  bool _isInitialized = false;
  SmsAnalysisResult? _manualAnalysisResult;
  bool _isManualAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initProvider();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _provider.dispose();
    super.dispose();
  }

  Future<void> _initProvider() async {
    await _provider.init();
    _provider.addListener(_onProviderChanged);
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onRefresh() async {
    await _provider.loadMessages();
  }

  void _navigateToDetail(SmsMessage message) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SmsDetailScreen(
          message: message,
          provider: _provider,
        ),
      ),
    );
  }

  Future<void> _analyzeManual(String content, String? sender) async {
    setState(() {
      _isManualAnalyzing = true;
      _manualAnalysisResult = null;
    });

    final result = await _provider.analyzeContent(content, sender: sender);

    if (mounted) {
      setState(() {
        _isManualAnalyzing = false;
        _manualAnalysisResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'SMS Protection',
        showBackButton: true,
        actions: [
          if (_provider.unanalyzedCount > 0)
            TextButton.icon(
              onPressed:
                  _provider.isAnalyzing ? null : _provider.analyzeAllMessages,
              icon: _provider.isAnalyzing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const DuotoneIcon('shield_check', size: 18),
              label: Text(
                _provider.isAnalyzing
                    ? 'Scanning...'
                    : 'Scan All (${_provider.unanalyzedCount})',
              ),
            ),
          GlassAppBarAction(
            svgIcon: 'forbidden',
            onTap: () => _showBlockedSendersSheet(),
            tooltip: 'Blocked Senders',
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
              child: Container(
                decoration: GlassTheme.glassDecoration(),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: GlassTheme.primaryAccent,
                  labelColor: GlassTheme.primaryAccent,
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(text: 'Inbox'),
                    Tab(text: 'Check'),
                    Tab(text: 'Stats'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: !_isInitialized
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // Inbox tab
                    _buildInboxTab(),

                    // Check tab
                    _buildCheckTab(),

                    // Stats tab
                    _buildStatsTab(),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildInboxTab() {
    final messages = _provider.messages;

    return Column(
      children: [
        // Filter chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: SmsFilter.values.map((filter) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SmsFilterChip(
                    filter: filter,
                    selectedFilter: _provider.filter,
                    onSelected: _provider.setFilter,
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Message list
        Expanded(
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: const Color(0xFF00D9FF),
            child: messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SmsCard(
                          message: message,
                          onTap: () => _navigateToDetail(message),
                          onAnalyze: message.analysisResult == null
                              ? () => _provider.analyzeMessage(message.id)
                              : null,
                          onBlock: () => _provider.blockSender(message.sender),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DuotoneIcon(
                'chat_dots',
                size: 64,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 16),
              Text(
                'No Messages',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _getEmptyStateMessage(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              if (_provider.filter != SmsFilter.all)
                OutlinedButton(
                  onPressed: () => _provider.setFilter(SmsFilter.all),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00D9FF),
                  ),
                  child: const Text('Show All Messages'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getEmptyStateMessage() {
    switch (_provider.filter) {
      case SmsFilter.all:
        return 'Grant SMS permission to start protecting your messages, or use the Check tab to analyze messages manually.';
      case SmsFilter.safe:
        return 'No safe messages found.';
      case SmsFilter.suspicious:
        return 'No suspicious messages detected.';
      case SmsFilter.dangerous:
        return 'No dangerous messages found. Great!';
      case SmsFilter.unanalyzed:
        return 'All messages have been analyzed.';
    }
  }

  Widget _buildCheckTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Manual input
          SmsInputWidget(
            onAnalyze: _analyzeManual,
            isAnalyzing: _isManualAnalyzing,
          ),

          // Result
          if (_manualAnalysisResult != null) ...[
            const SizedBox(height: 20),
            _buildManualAnalysisResult(),
          ],
        ],
      ),
    );
  }

  Widget _buildManualAnalysisResult() {
    final result = _manualAnalysisResult!;

    return GlassCard(
      tintColor: Color(result.threatLevel.color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              ThreatLevelBadge(level: result.threatLevel),
              const Spacer(),
              Text(
                'Risk: ${(result.riskScore * 100).toInt()}%',
                style: TextStyle(
                  color: Color(result.threatLevel.color),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Recommendation
          if (result.recommendation != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(result.threatLevel.color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  DuotoneIcon(
                    'lightbulb',
                    color: Color(result.threatLevel.color),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      result.recommendation!,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Threats
          if (result.threats.isNotEmpty) ...[
            const Text(
              'Detected Threats',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            ...result.threats
                .map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ThreatDetailCard(threat: t),
                    ))
                .toList(),
          ],

          // Detected intents
          if (result.detectedIntents.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Suspicious Intents',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: result.detectedIntents.map((intent) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    intent.value.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // URLs
          if (result.extractedUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Extracted URLs',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            ...result.extractedUrls
                .map((url) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: UrlAnalysisCard(url: url),
                    ))
                .toList(),
          ],

          // Sender analysis
          if (result.senderAnalysis != null) ...[
            const SizedBox(height: 16),
            SenderAnalysisCard(analysis: result.senderAnalysis!),
          ],

          // Matched patterns
          if (result.matchedPatterns.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Matched Patterns',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: result.matchedPatterns.map((p) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    p,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
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

  Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Stats card
          SmsStatsCard(
            stats: _provider.stats,
            onScanAll:
                _provider.unanalyzedCount > 0 ? _provider.analyzeAllMessages : null,
            isScanning: _provider.isAnalyzing,
          ),
          const SizedBox(height: 20),

          // Protection status
          _buildProtectionStatus(),
          const SizedBox(height: 20),

          // Recent threats
          _buildRecentThreats(),
        ],
      ),
    );
  }

  Widget _buildProtectionStatus() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Protection Status',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          _StatusRow(
            icon: 'chat_dots',
            label: 'SMS Monitoring',
            status: 'Active',
            statusColor: Colors.green,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: 'shield_check',
            label: 'Real-time Analysis',
            status: 'Enabled',
            statusColor: Colors.green,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: 'cloud_storage',
            label: 'Cloud Intelligence',
            status: 'Connected',
            statusColor: Colors.green,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: 'forbidden',
            label: 'Blocked Senders',
            status: '${_provider.blockedSenders.length}',
            statusColor: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentThreats() {
    final threats = _provider.allMessages
        .where((m) => m.hasThreats)
        .take(5)
        .toList();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Recent Threats',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (threats.isNotEmpty)
                TextButton(
                  onPressed: () {
                    _provider.setFilter(SmsFilter.dangerous);
                    _tabController.animateTo(0);
                  },
                  child: const Text('View All'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (threats.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    DuotoneIcon(
                      'shield_check',
                      size: 48,
                      color: Colors.green[700],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No threats detected',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...threats.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ThreatListItem(
                    message: m,
                    onTap: () => _navigateToDetail(m),
                  ),
                )),
        ],
      ),
    );
  }

  void _showBlockedSendersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _BlockedSendersSheet(
        blockedSenders: _provider.blockedSenders,
        onUnblock: _provider.unblockSender,
      ),
    );
  }
}

/// Status row widget
class _StatusRow extends StatelessWidget {
  final String icon;
  final String label;
  final String status;
  final Color statusColor;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DuotoneIcon(icon, size: 20, color: Colors.grey[500]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Threat list item
class _ThreatListItem extends StatelessWidget {
  final SmsMessage message;
  final VoidCallback? onTap;

  const _ThreatListItem({
    required this.message,
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
          color: Color(message.threatLevel.color).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(message.threatLevel.color).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: DuotoneIcon(
                  _getThreatIcon(),
                  size: 16,
                  color: Color(message.threatLevel.color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.sender,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    message.analysisResult?.threats.first.type.displayName ??
                        'Unknown threat',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            ThreatLevelBadge(level: message.threatLevel, compact: true),
          ],
        ),
      ),
    );
  }

  String _getThreatIcon() {
    if (message.analysisResult?.threats.isEmpty ?? true) {
      return 'danger_triangle';
    }

    final threatType = message.analysisResult!.threats.first.type;
    switch (threatType) {
      case SmsThreatType.phishing:
        return 'danger_triangle';
      case SmsThreatType.smishing:
        return 'chat_dots';
      case SmsThreatType.bankingFraud:
        return 'wallet';
      case SmsThreatType.packageDeliveryScam:
        return 'box';
      default:
        return 'danger_triangle';
    }
  }
}

/// Blocked senders sheet
class _BlockedSendersSheet extends StatelessWidget {
  final List<String> blockedSenders;
  final Function(String) onUnblock;

  const _BlockedSendersSheet({
    required this.blockedSenders,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const DuotoneIcon('forbidden', color: Colors.red, size: 24),
              const SizedBox(width: 10),
              const Text(
                'Blocked Senders',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              Text(
                '${blockedSenders.length}',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // List
          if (blockedSenders.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No blocked senders',
                  style: TextStyle(
                    color: Colors.grey[500],
                  ),
                ),
              ),
            )
          else
            ...blockedSenders.map((sender) => ListTile(
                  leading: const DuotoneIcon('smartphone', color: Colors.grey, size: 24),
                  title: Text(sender),
                  trailing: IconButton(
                    icon: const DuotoneIcon('minus_circle', color: Colors.red, size: 24),
                    onPressed: () {
                      onUnblock(sender);
                      Navigator.pop(context);
                    },
                  ),
                )),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
