/// SMS Protection Screen
/// Main screen for SMS/smishing protection
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
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
    with WidgetsBindingObserver {
  // The provider is owned by the app (registered in main.dart) and only
  // consumed here; this field is re-bound from context.watch in build().
  late SmsProvider _provider;
  final GlobalKey<GlassTabPageState> _tabPageKey = GlobalKey();
  SmsAnalysisResult? _manualAnalysisResult;
  bool _isManualAnalyzing = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Idempotent: loads persisted state, owns the platform service and
      // reads the device inbox (no-op if main.dart already initialized it).
      context.read<SmsProvider>().init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final provider = context.read<SmsProvider>();
      // The Android permission dialog result arrives out-of-band; re-check
      // when the user returns to the app.
      if (provider.platformStatus == SmsPlatformStatus.permissionRequired) {
        provider.loadMessages();
      }
    }
  }

  Future<void> _onRefresh() async {
    await _provider.loadMessages();
  }

  Future<void> _requestPermission() async {
    final provider = context.read<SmsProvider>();
    await provider.requestSmsPermission();
    // Re-check shortly after; the dialog result also triggers a re-check on
    // app resume via didChangeAppLifecycleState.
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      await provider.loadMessages();
    }
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

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  List<SmsMessage> get _filteredMessages {
    var messages = _provider.messages;
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      messages = messages.where((m) =>
        m.sender.toLowerCase().contains(query) ||
        m.content.toLowerCase().contains(query)
      ).toList();
    }
    return messages;
  }

  @override
  Widget build(BuildContext context) {
    _provider = context.watch<SmsProvider>();

    return GlassTabPage(
      key: _tabPageKey,
      title: 'SMS Protection',
      hasSearch: true,
      searchHint: 'Search messages...',
      onSearchChanged: _onSearchChanged,
      headerContent: _buildActionsRow(),
      tabs: [
        GlassTab(
          label: 'Inbox',
          iconPath: 'inbox',
          content: _buildInboxTab(),
        ),
        GlassTab(
          label: 'Check',
          iconPath: 'shield_check',
          content: _buildCheckTab(),
        ),
        GlassTab(
          label: 'Stats',
          iconPath: 'chart',
          content: _buildStatsTab(),
        ),
      ],
    );
  }

  Widget _buildActionsRow() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
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
                  : DuotoneIcon('shield_check', size: 18, color: cs.onSurface),
              label: Text(
                _provider.isAnalyzing
                    ? 'Scanning...'
                    : 'Scan All (${_provider.unanalyzedCount})',
              ),
            ),
          IconButton(
            icon: DuotoneIcon('forbidden', size: 22, color: cs.onSurface),
            onPressed: () => _showBlockedSendersSheet(),
            tooltip: 'Blocked Senders',
          ),
        ],
      ),
    );
  }

  Widget _buildInboxTab() {
    final messages = _filteredMessages;

    return Column(
      children: [
        // Honest pipeline state banner (permission / platform / errors)
        if (_pipelineBanner() != null) _pipelineBanner()!,

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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
    final cs = Theme.of(context).colorScheme;
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
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty ? 'No Results' : 'No Messages',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty
                    ? 'No messages match "$_searchQuery"'
                    : _getEmptyStateMessage(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              if (_searchQuery.isEmpty &&
                  _provider.platformStatus ==
                      SmsPlatformStatus.permissionRequired)
                ElevatedButton.icon(
                  onPressed: _requestPermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D9FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const DuotoneIcon('shield_check',
                      size: 18, color: Colors.black),
                  label: const Text('Grant SMS Permission'),
                ),
              if (_provider.filter != SmsFilter.all && _searchQuery.isEmpty)
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

  /// Banner reflecting the real state of the SMS pipeline. Returns null when
  /// the pipeline is ready (or still being checked) and nothing needs action.
  Widget? _pipelineBanner() {
    switch (_provider.platformStatus) {
      case SmsPlatformStatus.permissionRequired:
        return _InboxBanner(
          icon: 'shield_keyhole_minimalistic',
          color: Colors.orange,
          message: 'SMS permission is required to scan your inbox for '
              'smishing and phishing threats.',
          actionLabel: 'Grant Permission',
          onAction: _requestPermission,
        );
      case SmsPlatformStatus.unsupported:
        return _InboxBanner(
          icon: 'info_circle',
          color: Colors.blueGrey,
          message: _provider.platformStatusDetail ??
              'The SMS inbox is not accessible on this platform. '
                  'Use the Check tab to analyze message text manually.',
        );
      case SmsPlatformStatus.error:
        return _InboxBanner(
          icon: 'danger_triangle',
          color: Colors.red,
          message: _provider.platformStatusDetail ??
              'The SMS pipeline reported an error.',
          actionLabel: 'Retry',
          onAction: _onRefresh,
        );
      case SmsPlatformStatus.ready:
      case SmsPlatformStatus.unknown:
        return null;
    }
  }

  String _getEmptyStateMessage() {
    switch (_provider.filter) {
      case SmsFilter.all:
        switch (_provider.platformStatus) {
          case SmsPlatformStatus.permissionRequired:
            return 'Grant SMS permission to start protecting your messages, '
                'or use the Check tab to analyze messages manually.';
          case SmsPlatformStatus.unsupported:
            return _provider.platformStatusDetail ??
                'The SMS inbox is not accessible on this platform. '
                    'Use the Check tab to analyze messages manually.';
          case SmsPlatformStatus.error:
            return _provider.platformStatusDetail ??
                'Could not read the SMS inbox. Pull down to retry.';
          case SmsPlatformStatus.ready:
            return 'Your SMS inbox is empty.';
          case SmsPlatformStatus.unknown:
            return 'Checking SMS access...';
        }
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
            const SizedBox(height: 24),
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
                color: Color(result.threatLevel.color).withValues(alpha: 0.1),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
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
                    )),
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
                    color: Colors.orange.withValues(alpha: 0.2),
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
                    )),
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    p,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        children: [
          // Stats card
          SmsStatsCard(
            stats: _provider.stats,
            onScanAll:
                _provider.unanalyzedCount > 0 ? _provider.analyzeAllMessages : null,
            isScanning: _provider.isAnalyzing,
          ),
          const SizedBox(height: 24),

          // Protection status
          _buildProtectionStatus(),
          const SizedBox(height: 24),

          // Recent threats
          _buildRecentThreats(),
        ],
      ),
    );
  }

  Widget _buildProtectionStatus() {
    final monitoring = _monitoringStatus();
    final analysis = _analysisStatus();
    final cloud = _cloudStatus();

    return GlassCard(
      margin: EdgeInsets.zero,
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
            status: monitoring.$1,
            statusColor: monitoring.$2,
            onTap: _provider.platformStatus ==
                    SmsPlatformStatus.permissionRequired
                ? _requestPermission
                : null,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: 'shield_check',
            label: 'Real-time Analysis',
            status: analysis.$1,
            statusColor: analysis.$2,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: 'cloud_storage',
            label: 'Cloud Intelligence',
            status: cloud.$1,
            statusColor: cloud.$2,
          ),
          const SizedBox(height: 12),
          _StatusRow(
            icon: 'forbidden',
            label: 'Blocked Senders',
            status: '${_provider.blockedSenders.length}',
            statusColor: _provider.blockedSenders.isEmpty
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Colors.orange,
          ),
          if (_provider.lastAnalyzeSucceeded == false &&
              _provider.lastAnalyzeError != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last analysis error: ${_provider.lastAnalyzeError}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  /// Real SMS monitoring state: platform supported + permission granted +
  /// inbox readable.
  (String, Color) _monitoringStatus() {
    switch (_provider.platformStatus) {
      case SmsPlatformStatus.ready:
        return ('Active', Colors.green);
      case SmsPlatformStatus.permissionRequired:
        return ('Permission Needed', Colors.orange);
      case SmsPlatformStatus.unsupported:
        return ('Unavailable', Colors.blueGrey);
      case SmsPlatformStatus.error:
        return ('Error', Colors.red);
      case SmsPlatformStatus.unknown:
        return ('Checking...', Theme.of(context).colorScheme.onSurfaceVariant);
    }
  }

  /// Real-time analysis state: monitoring must be active AND protection
  /// enabled in settings.
  (String, Color) _analysisStatus() {
    if (_provider.platformStatus != SmsPlatformStatus.ready) {
      return ('Inactive', Theme.of(context).colorScheme.onSurfaceVariant);
    }
    return _provider.protectionEnabled
        ? ('Enabled', Colors.green)
        : ('Disabled', Colors.orange);
  }

  /// Cloud intelligence state: outcome of the most recent backend analyze
  /// call. Never claims "Connected" before a real round-trip succeeded.
  (String, Color) _cloudStatus() {
    final ok = _provider.lastAnalyzeSucceeded;
    if (ok == true) return ('Connected', Colors.green);
    if (ok == false) return ('Error', Colors.red);
    return (
      'Not contacted yet',
      Theme.of(context).colorScheme.onSurfaceVariant
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
                    _tabPageKey.currentState?.animateToTab(0);
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
  final VoidCallback? onTap;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.statusColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final row = Row(
      children: [
        DuotoneIcon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.2),
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

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: row,
    );
  }
}

/// Inline banner shown above the inbox when the SMS pipeline needs attention
/// (missing permission, unsupported platform, channel error).
class _InboxBanner extends StatelessWidget {
  final String icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  const _InboxBanner({
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          DuotoneIcon(icon, size: 22, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => onAction!(),
              style: TextButton.styleFrom(foregroundColor: color),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
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
          color: Color(message.threatLevel.color).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(message.threatLevel.color).withValues(alpha: 0.2),
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
                    message.sender, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    message.analysisResult?.threats.first.type.displayName ??
                        'Unknown threat', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
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
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
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
                  color: cs.onSurfaceVariant,
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
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...blockedSenders.map((sender) => ListTile(
                  leading: DuotoneIcon('smartphone',
                      color: cs.onSurfaceVariant, size: 24),
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
