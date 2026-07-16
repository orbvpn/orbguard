// Scam Detection Screen
// AI-powered scam detection and analysis interface

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/scam_detection_provider.dart';

class ScamDetectionScreen extends StatefulWidget {
  const ScamDetectionScreen({super.key});

  @override
  State<ScamDetectionScreen> createState() => _ScamDetectionScreenState();
}

class _ScamDetectionScreenState extends State<ScamDetectionScreen> {
  final _textController = TextEditingController();
  final _urlController = TextEditingController();
  final _phoneController = TextEditingController();
  ScamContentType _selectedType = ScamContentType.text;

  /// Image/voice file selected for analysis (bytes loaded in memory).
  PlatformFile? _pickedMediaFile;
  bool _isPickingFile = false;

  /// Set after an image/voice analysis attempt fails server-side: the
  /// backend's vision/speech analyzers are config-gated and the analyze
  /// endpoint fails when they are disabled.
  String? _mediaCapabilityNotice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScamDetectionProvider>().init();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _urlController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScamDetectionProvider>(
      builder: (context, provider, _) {
        return GlassTabPage(
          title: 'Scam Detection',
          hasSearch: true,
          searchHint: 'Search scams...',
          tabs: [
            GlassTab(
              label: 'Analyze',
              iconPath: 'magnifer',
              content: _buildAnalyzeTab(provider),
            ),
            GlassTab(
              label: 'History',
              iconPath: 'chart',
              content: _buildHistoryTab(provider),
            ),
            GlassTab(
              label: 'Patterns',
              iconPath: 'link_round',
              content: _buildPatternsTab(provider),
            ),
          ],
          actions: [
            if (provider.analysisHistory.isNotEmpty)
              GestureDetector(
                onTap: () => _confirmClearHistory(context, provider),
                child: DuotoneIcon('trash_bin_minimalistic', size: 22, color: Theme.of(context).colorScheme.onSurface),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAnalyzeTab(ScamDetectionProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(
            children: [
              _buildStatCard('Scanned', provider.totalScanned.toString(), AppColors.accentInk),
              const SizedBox(width: 12),
              _buildStatCard('Detected', provider.scamsDetected.toString(), GlassTheme.errorColor),
            ],
          ),
          const SizedBox(height: 24),

          // Content type selector
          Text(
            'Select Content Type',
            style: BrandText.title(color: cs.onSurface),
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
                      if (selected) {
                        setState(() {
                          _selectedType = type;
                          _pickedMediaFile = null;
                          _mediaCapabilityNotice = null;
                        });
                      }
                    },
                    backgroundColor: GlassTheme.glassColor(
                        Theme.of(context).brightness == Brightness.dark),
                    selectedColor: GlassTheme.primaryAccent.withValues(alpha: 0.3),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.accentInk
                          : cs.onSurfaceVariant,
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
              onPressed: provider.isAnalyzing ||
                      ((_selectedType == ScamContentType.image ||
                              _selectedType == ScamContentType.voice) &&
                          _pickedMediaFile == null)
                  ? null
                  : () => _analyze(provider),
              icon: provider.isAnalyzing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.onLime),
                    )
                  : const DuotoneIcon('shield_check',
                      size: 20, color: Brand.onLime),
              label: Text(provider.isAnalyzing ? 'Analyzing...' : 'Analyze for Scams'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Brand.onLime,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          // Analysis errors — surfaced, never swallowed.
          if (provider.error != null) ...[
            const SizedBox(height: 24),
            _buildErrorCard(provider),
          ],

          // Last result
          if (provider.lastResult != null) ...[
            const SizedBox(height: 24),
            _buildResultCard(provider.lastResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorCard(ScamDetectionProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      tintColor: GlassTheme.errorColor,
      child: Row(
        children: [
          const DuotoneIcon('danger_circle',
              size: 22, color: GlassTheme.errorColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              provider.error!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurface, fontSize: 13),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
            onPressed: provider.clearError,
          ),
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
              style: BrandText.heading(size: 28, color: color),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(ScamDetectionProvider provider) {
    final cs = Theme.of(context).colorScheme;
    switch (_selectedType) {
      case ScamContentType.text:
        return GlassContainer(
          padding: const EdgeInsets.all(4),
          child: TextField(
            controller: _textController,
            maxLines: 5,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Paste suspicious message or text...',
              hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
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
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Enter URL to check...',
              hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: DuotoneIcon('link', color: cs.onSurfaceVariant, size: 24),
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
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Enter phone number...',
              hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: DuotoneIcon('smartphone',
                    color: cs.onSurfaceVariant, size: 24),
              ),
              border: InputBorder.none,
            ),
          ),
        );
      case ScamContentType.image:
      case ScamContentType.voice:
        return _buildMediaPickerField();
    }
  }

  /// Picker UI for image/voice analysis. The selected file is uploaded as
  /// base64 in the `content` field (the backend ScamAnalysisRequest documents
  /// `content` as "text content or base64 for images").
  Widget _buildMediaPickerField() {
    final cs = Theme.of(context).colorScheme;
    final isImage = _selectedType == ScamContentType.image;
    final file = _pickedMediaFile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              DuotoneIcon(
                isImage ? 'gallery' : 'microphone',
                color: cs.onSurfaceVariant,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: file == null
                    ? Text(
                        isImage
                            ? 'Select a screenshot or image to analyze'
                            : 'Select a voice message or audio file to analyze',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      )
                    : Text(
                        '${file.name} (${_formatBytes(file.size)})',
                        style: TextStyle(color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              TextButton(
                onPressed: _isPickingFile ? null : _pickMediaFile,
                child: Text(file == null ? 'Choose' : 'Change'),
              ),
            ],
          ),
        ),
        if (_mediaCapabilityNotice != null) ...[
          const SizedBox(height: 12),
          GlassContainer(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const DuotoneIcon('info_circle',
                    color: GlassTheme.warningColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _mediaCapabilityNotice!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: GlassTheme.warningColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickMediaFile() async {
    setState(() => _isPickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: _selectedType == ScamContentType.image
            ? FileType.image
            : FileType.audio,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pickedMediaFile = result.files.first;
          _mediaCapabilityNotice = null;
        });
      }
    } finally {
      if (mounted) setState(() => _isPickingFile = false);
    }
  }

  Future<void> _analyzeMedia(ScamDetectionProvider provider) async {
    final bytes = _pickedMediaFile?.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final result = await provider.analyzeContent(
      type: _selectedType,
      content: base64Encode(bytes),
    );

    if (!mounted) return;
    if (result == null && provider.error != null) {
      // The backend vision/speech analyzers are config-gated; when disabled
      // the analyze endpoint fails server-side ("scam analysis failed").
      // Surface that honestly instead of pretending the upload was bad.
      final err = provider.error!;
      if (err.contains('scam analysis failed') ||
          err.contains('503') ||
          err.contains('Service Unavailable')) {
        setState(() {
          _mediaCapabilityNotice = _selectedType == ScamContentType.image
              ? 'Image analysis isn\'t available right now — it isn\'t '
                  'enabled on our servers.'
              : 'Voice analysis isn\'t available right now — it isn\'t '
                  'enabled on our servers.';
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
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
      case ScamContentType.image:
      case ScamContentType.voice:
        _analyzeMedia(provider);
        break;
    }
  }

  Widget _buildResultCard(ScamAnalysisResult result) {
    final cs = Theme.of(context).colorScheme;
    final riskColor = Color(result.riskColor);

    return GlassCard(
      margin: EdgeInsets.zero,
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
                      result.isScam ? 'Scam Detected' : 'Looks Safe', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: BrandText.title(size: 18, color: riskColor),
                    ),
                    Text(
                      '${(result.confidence * 100).toInt()}% sure', maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GlassBadge(text: result.riskLevel, color: riskColor),
                  if (result.offline) ...[
                    const SizedBox(height: 4),
                    const GlassBadge(
                      text: 'Offline analysis',
                      color: GlassTheme.warningColor,
                      fontSize: 10,
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (result.offline) ...[
            const SizedBox(height: 12),
            Text(
              'We couldn\'t reach our servers, so this result comes from '
              'limited checks on your device instead of our full analysis.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
          if (result.scamType != null) ...[
            const SizedBox(height: 16),
            GlassContainer(
              padding: const EdgeInsets.all(12),
              blur: false,
              child: Row(
                children: [
                  DuotoneIcon('tag', size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Type: ${result.scamType!.displayName}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
          if (result.indicators.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Warning Signs Found',
              style: BrandText.title(size: 14, color: cs.onSurface),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (result.recommendations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Recommendations',
              style: BrandText.title(size: 14, color: cs.onSurface),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
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
        icon: 'chart',
        title: 'No History',
        subtitle: 'Your scam analysis history will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.analysisHistory.length,
      itemBuilder: (context, index) {
        final result = provider.analysisHistory[index];
        return _buildHistoryCard(result);
      },
    );
  }

  Widget _buildHistoryCard(ScamAnalysisResult result) {
    final cs = Theme.of(context).colorScheme;
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
                  result.contentType.displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500),
                ),
                Text(
                  _truncateContent(result.content),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
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
              if (result.offline) ...[
                const SizedBox(height: 4),
                const GlassBadge(
                  text: 'Offline analysis',
                  color: GlassTheme.warningColor,
                  fontSize: 9,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _formatTime(result.analyzedAt),
                style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPatternsTab(ScamDetectionProvider provider) {
    if (provider.isLoadingPatterns) {
      return Center(child: CircularProgressIndicator(color: AppColors.accentInk));
    }

    if (provider.patterns.isEmpty) {
      if (provider.error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DuotoneIcon('danger_circle',
                    size: 48, color: GlassTheme.errorColor),
                const SizedBox(height: 12),
                Text(
                  provider.error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => provider.loadPatterns(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      return _buildEmptyState(
        icon: 'link_round',
        title: 'No Patterns',
        subtitle: 'Scam patterns will be displayed here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.patterns.length,
      itemBuilder: (context, index) {
        final pattern = provider.patterns[index];
        return _buildPatternCard(pattern);
      },
    );
  }

  Widget _buildPatternCard(ScamPattern pattern) {
    final cs = Theme.of(context).colorScheme;
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
                      pattern.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: BrandText.title(size: 14, color: cs.onSurface),
                    ),
                    Text(
                      pattern.type.displayName, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: typeColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            pattern.description,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
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
                    color: Brand.glassFill,
                    borderRadius:
                        BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                  child: Text(
                    keyword,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
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
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 64, color: AppColors.accentInk.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            title,
            style: BrandText.title(size: 18, color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showResultDetails(BuildContext context, ScamAnalysisResult result) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(isDark: isDark),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(GlassTheme.radiusLarge),
            ),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              _buildResultCard(result),
              const SizedBox(height: 16),
              Text(
                'Original Content',
                style: BrandText.title(size: 14, color: cs.onSurface),
              ),
              const SizedBox(height: 8),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  result.content,
                  style: TextStyle(color: cs.onSurface, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearHistory(BuildContext context, ScamDetectionProvider provider) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        title: Text('Clear History', style: TextStyle(color: cs.onSurface)),
        content: Text(
          'Are you sure you want to clear all analysis history?',
          style: TextStyle(color: cs.onSurfaceVariant),
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
            child: Text('Clear', style: TextStyle(color: AppColors.errorInk)),
          ),
        ],
      ),
    );
  }

  Color _getScamTypeColor(ScamType type) {
    switch (type) {
      case ScamType.phishing:
        return AppColors.errorInk;
      case ScamType.impersonation:
        return AppColors.severityCritical;
      case ScamType.advanceFee:
        return AppColors.amberInk;
      case ScamType.techSupport:
        return AppColors.chartColors[4]; // spectrum purple
      case ScamType.romance:
        return AppColors.secondaryInk;
      case ScamType.investment:
        return AppColors.accentInk;
      case ScamType.lottery:
        return AppColors.severityLow;
      case ScamType.jobOffer:
        return AppColors.chartColors[3]; // spectrum periwinkle
      case ScamType.charity:
        return AppColors.chartColors[2]; // spectrum cyan
      case ScamType.government:
        return AppColors.chartColors[6]; // spectrum mint
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
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

}
