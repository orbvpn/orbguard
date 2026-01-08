/// Scam Detection Screen
/// AI-powered scam detection and analysis interface

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/scam_detection_provider.dart';

class ScamDetectionScreen extends StatefulWidget {
  const ScamDetectionScreen({super.key});

  @override
  State<ScamDetectionScreen> createState() => _ScamDetectionScreenState();
}

class _ScamDetectionScreenState extends State<ScamDetectionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _textController = TextEditingController();
  final _urlController = TextEditingController();
  final _phoneController = TextEditingController();
  ScamContentType _selectedType = ScamContentType.text;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScamDetectionProvider>().init();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    _urlController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScamDetectionProvider>(
      builder: (context, provider, _) {
        return GlassScaffold(
          appBar: GlassAppBar(
            title: 'Scam Detection',
            actions: [
              if (provider.analysisHistory.isNotEmpty)
                IconButton(
                  icon: const DuotoneIcon('trash_bin_minimalistic', size: 24, color: Colors.white),
                  onPressed: () => _confirmClearHistory(context, provider),
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: GlassTheme.primaryAccent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: 'Analyze'),
                Tab(text: 'History'),
                Tab(text: 'Patterns'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildAnalyzeTab(provider),
              _buildHistoryTab(provider),
              _buildPatternsTab(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnalyzeTab(ScamDetectionProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(
            children: [
              _buildStatCard('Scanned', provider.totalScanned.toString(), GlassTheme.primaryAccent),
              const SizedBox(width: 12),
              _buildStatCard('Detected', provider.scamsDetected.toString(), GlassTheme.errorColor),
            ],
          ),
          const SizedBox(height: 24),

          // Content type selector
          const Text(
            'Select Content Type',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ScamContentType.values.map((type) {
                final isSelected = type == _selectedType;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(type.displayName),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedType = type);
                    },
                    backgroundColor: GlassTheme.glassColorDark,
                    selectedColor: GlassTheme.primaryAccent.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: isSelected ? GlassTheme.primaryAccent : Colors.white70,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // Input field based on type
          _buildInputField(provider),
          const SizedBox(height: 16),

          // Analyze button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: provider.isAnalyzing ? null : () => _analyze(provider),
              icon: provider.isAnalyzing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const DuotoneIcon('shield_check', size: 20, color: Colors.white),
              label: Text(provider.isAnalyzing ? 'Analyzing...' : 'Analyze for Scams'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          // Last result
          if (provider.lastResult != null) ...[
            const SizedBox(height: 24),
            _buildResultCard(provider.lastResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(ScamDetectionProvider provider) {
    switch (_selectedType) {
      case ScamContentType.text:
        return GlassContainer(
          padding: const EdgeInsets.all(4),
          child: TextField(
            controller: _textController,
            maxLines: 5,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Paste suspicious message or text...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        );
      case ScamContentType.url:
        return GlassContainer(
          padding: const EdgeInsets.all(4),
          child: TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter URL to check...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: DuotoneIcon('link', color: Colors.white54, size: 24),
              ),
              border: InputBorder.none,
            ),
          ),
        );
      case ScamContentType.phone:
        return GlassContainer(
          padding: const EdgeInsets.all(4),
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter phone number...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: DuotoneIcon('smartphone', color: Colors.white54, size: 24),
              ),
              border: InputBorder.none,
            ),
          ),
        );
      default:
        return GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const DuotoneIcon('info_circle', color: Colors.white54, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This content type analysis is coming soon',
                  style: TextStyle(color: Colors.white.withOpacity(0.6)),
                ),
              ),
            ],
          ),
        );
    }
  }

  void _analyze(ScamDetectionProvider provider) {
    switch (_selectedType) {
      case ScamContentType.text:
        if (_textController.text.isNotEmpty) {
          provider.analyzeText(_textController.text);
        }
        break;
      case ScamContentType.url:
        if (_urlController.text.isNotEmpty) {
          provider.analyzeUrl(_urlController.text);
        }
        break;
      case ScamContentType.phone:
        if (_phoneController.text.isNotEmpty) {
          provider.checkPhone(_phoneController.text);
        }
        break;
      default:
        break;
    }
  }

  Widget _buildResultCard(ScamAnalysisResult result) {
    final riskColor = Color(result.riskColor);

    return GlassCard(
      tintColor: riskColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassDuotoneIconBox(
                icon: result.isScam ? 'danger_triangle' : 'check_circle',
                color: riskColor,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.isScam ? 'Scam Detected' : 'Looks Safe',
                      style: TextStyle(
                        color: riskColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${(result.confidence * 100).toInt()}% confidence',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                    ),
                  ],
                ),
              ),
              GlassBadge(text: result.riskLevel, color: riskColor),
            ],
          ),
          if (result.scamType != null) ...[
            const SizedBox(height: 16),
            GlassContainer(
              padding: const EdgeInsets.all(12),
              withBlur: false,
              child: Row(
                children: [
                  const DuotoneIcon('tag', size: 18, color: Colors.white54),
                  const SizedBox(width: 8),
                  Text(
                    'Type: ${result.scamType!.displayName}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
          if (result.indicators.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Indicators Found',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...result.indicators.take(5).map((indicator) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      DuotoneIcon('alt_arrow_right', size: 16, color: riskColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          indicator,
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (result.recommendations.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Recommendations',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...result.recommendations.map((rec) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DuotoneIcon('lightbulb', size: 16, color: GlassTheme.warningColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          rec,
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
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

  Widget _buildHistoryTab(ScamDetectionProvider provider) {
    if (provider.analysisHistory.isEmpty) {
      return _buildEmptyState(
        icon: 'history',
        title: 'No History',
        subtitle: 'Your scam analysis history will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.analysisHistory.length,
      itemBuilder: (context, index) {
        final result = provider.analysisHistory[index];
        return _buildHistoryCard(result);
      },
    );
  }

  Widget _buildHistoryCard(ScamAnalysisResult result) {
    final riskColor = Color(result.riskColor);

    return GlassCard(
      onTap: () => _showResultDetails(context, result),
      child: Row(
        children: [
          GlassDuotoneIconBox(
            icon: result.isScam ? 'danger_triangle' : 'check_circle',
            color: riskColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.contentType.displayName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
                Text(
                  _truncateContent(result.content),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GlassBadge(text: result.riskLevel, color: riskColor, fontSize: 10),
              const SizedBox(height: 4),
              Text(
                _formatTime(result.analyzedAt),
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPatternsTab(ScamDetectionProvider provider) {
    if (provider.isLoadingPatterns) {
      return const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent));
    }

    if (provider.patterns.isEmpty) {
      return _buildEmptyState(
        icon: 'structure',
        title: 'No Patterns',
        subtitle: 'Scam patterns will be displayed here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.patterns.length,
      itemBuilder: (context, index) {
        final pattern = provider.patterns[index];
        return _buildPatternCard(pattern);
      },
    );
  }

  Widget _buildPatternCard(ScamPattern pattern) {
    final typeColor = _getScamTypeColor(pattern.type);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassDuotoneIconBox(icon: _getScamTypeSvgIcon(pattern.type), color: typeColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pattern.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      pattern.type.displayName,
                      style: TextStyle(color: typeColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatCount(pattern.detectionCount),
                    style: const TextStyle(color: GlassTheme.primaryAccent, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'detections',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pattern.description,
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
          ),
          if (pattern.keywords.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: pattern.keywords.take(5).map((keyword) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    keyword,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 64, color: GlassTheme.primaryAccent.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showResultDetails(BuildContext context, ScamAnalysisResult result) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              _buildResultCard(result),
              const SizedBox(height: 16),
              const Text(
                'Original Content',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  result.content,
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearHistory(BuildContext context, ScamDetectionProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Clear History', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to clear all analysis history?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.clearHistory();
              Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: GlassTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  Color _getScamTypeColor(ScamType type) {
    switch (type) {
      case ScamType.phishing:
        return GlassTheme.errorColor;
      case ScamType.impersonation:
        return const Color(0xFFFF5722);
      case ScamType.advanceFee:
        return const Color(0xFFFF9800);
      case ScamType.techSupport:
        return const Color(0xFF9C27B0);
      case ScamType.romance:
        return const Color(0xFFE91E63);
      case ScamType.investment:
        return const Color(0xFF4CAF50);
      case ScamType.lottery:
        return const Color(0xFFFFEB3B);
      case ScamType.jobOffer:
        return const Color(0xFF2196F3);
      case ScamType.charity:
        return const Color(0xFF00BCD4);
      case ScamType.government:
        return const Color(0xFF3F51B5);
      default:
        return Colors.grey;
    }
  }

  String _getScamTypeSvgIcon(ScamType type) {
    switch (type) {
      case ScamType.phishing:
        return 'danger_triangle';
      case ScamType.impersonation:
        return 'user_cross';
      case ScamType.advanceFee:
        return 'dollar';
      case ScamType.techSupport:
        return 'headphones_round';
      case ScamType.romance:
        return 'heart';
      case ScamType.investment:
        return 'graph_up';
      case ScamType.lottery:
        return 'gift';
      case ScamType.jobOffer:
        return 'user_id';
      case ScamType.charity:
        return 'heart_shine';
      case ScamType.government:
        return 'server_square';
      default:
        return 'danger_triangle';
    }
  }

  String _truncateContent(String content) {
    if (content.length > 50) {
      return '${content.substring(0, 50)}...';
    }
    return content;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
