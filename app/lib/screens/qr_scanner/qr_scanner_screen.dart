// QR Scanner Screen
// Main screen for QR code scanning and security analysis

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/qr_provider.dart';
import '../../widgets/qr/qr_widgets.dart';
import '../../models/api/sms_analysis.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final GlobalKey<GlassTabPageState> _tabKey = GlobalKey<GlassTabPageState>();
  MobileScannerController? _scannerController;
  bool _isCameraActive = false;
  bool _isFlashOn = false;
  bool _isFrontCamera = false;

  @override
  void initState() {
    super.initState();
    // Start camera after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCamera();
    });
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  void _startCamera() {
    _scannerController = MobileScannerController(
      facing: _isFrontCamera ? CameraFacing.front : CameraFacing.back,
      torchEnabled: _isFlashOn,
    );
    setState(() {
      _isCameraActive = true;
    });
  }

  void _toggleFlash() {
    _scannerController?.toggleTorch();
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
  }

  void _switchCamera() {
    _scannerController?.switchCamera();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  Future<void> _onQrDetected(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final content = barcode.rawValue;
    if (content == null || content.isEmpty) return;

    // Pause scanning while processing
    _scannerController?.stop();

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Process QR code
    final provider = context.read<QrProvider>();
    final result = await provider.scanQrCode(
      content,
      contentType: _detectContentType(content),
    );

    if (result != null && mounted) {
      _showResultBottomSheet(result);
    } else {
      // Resume scanning if no result
      _scannerController?.start();
    }
  }

  String? _detectContentType(String content) {
    final lower = content.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return 'url';
    } else if (lower.startsWith('mailto:')) {
      return 'email';
    } else if (lower.startsWith('tel:')) {
      return 'phone';
    } else if (lower.startsWith('sms:') || lower.startsWith('smsto:')) {
      return 'sms';
    } else if (lower.startsWith('wifi:')) {
      return 'wifi';
    } else if (lower.startsWith('begin:vcard')) {
      return 'vcard';
    } else if (lower.startsWith('geo:')) {
      return 'geo';
    } else if (lower.startsWith('begin:vevent')) {
      return 'event';
    } else if (lower.startsWith('bitcoin:') ||
        lower.startsWith('ethereum:') ||
        lower.startsWith('litecoin:')) {
      return 'crypto';
    }
    return 'text';
  }

  void _showResultBottomSheet(QrScanResult result) {
    final content = result.content;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(GlassTheme.radiusLarge),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.outline,
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    children: [
                      QrResultCard(result: result),
                      const SizedBox(height: 16),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: content));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Copied to clipboard'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const DuotoneIcon('copy', size: 18),
                              label: const Text('Copy'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.colors.onSurfaceVariant,
                                side: BorderSide(color: context.colors.outline),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _scannerController?.start();
                              },
                              icon: const DuotoneIcon('qr_code', size: 18),
                              label: const Text('Scan Again'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Brand.lime,
                                foregroundColor: Brand.onLime,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (result.threatLevel.index > 1) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _reportFalsePositive(context, content),
                            icon: const DuotoneIcon('flag', size: 18),
                            label: const Text('Report False Positive'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning.withAlpha(51),
                              foregroundColor: AppColors.secondaryInk,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      // Resume scanning when bottom sheet is dismissed
      _scannerController?.start();
    });
  }

  /// Submit a real false-positive report via POST /qr/report-false-positive
  /// and surface the actual outcome — no fake "submitted" confirmation.
  Future<void> _reportFalsePositive(
      BuildContext sheetContext, String content) async {
    final provider = context.read<QrProvider>();
    Navigator.pop(sheetContext);

    final success = await provider.reportFalsePositive(
      content,
      reason: 'User marked the scan verdict as a false positive',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'False positive reported'
              : provider.error ?? 'Failed to submit report',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
    _scannerController?.start();
  }

  void _onManualInput(String content) async {
    if (content.isEmpty) return;

    final provider = context.read<QrProvider>();
    final result = await provider.scanQrCode(
      content,
      contentType: _detectContentType(content),
    );

    if (result != null && mounted) {
      _showResultBottomSheet(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<QrProvider>(
      builder: (context, provider, child) {
        return GlassTabPage(
          key: _tabKey,
          title: 'QR Scanner',
          hasSearch: true,
          searchHint: 'Search history...',
          headerContent: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _isCameraActive ? _toggleFlash : null,
                  icon: DuotoneIcon(
                    'bolt',
                    size: 22,
                    color: _isFlashOn ? AppColors.accentInk : context.colors.onSurface,
                  ),
                  tooltip: 'Flash',
                ),
                IconButton(
                  onPressed: _isCameraActive ? _switchCamera : null,
                  icon: DuotoneIcon(
                    'camera',
                    size: 22,
                    color: context.colors.onSurface,
                  ),
                  tooltip: 'Switch Camera',
                ),
              ],
            ),
          ),
          tabs: [
            GlassTab(
              label: 'Scan',
              iconPath: 'camera',
              content: _buildScannerTab(provider),
            ),
            GlassTab(
              label: 'History',
              iconPath: 'history',
              content: _buildHistoryTab(provider),
            ),
            GlassTab(
              label: 'Stats',
              iconPath: 'chart',
              content: _buildStatsTab(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScannerTab(QrProvider provider) {
    return Column(
      children: [
        // Camera view
        SizedBox(
          height: 300,
          child: Stack(
            children: [
              if (_isCameraActive && _scannerController != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  child: MobileScanner(
                    controller: _scannerController!,
                    onDetect: _onQrDetected,
                  ),
                )
              else
                Container(
                  // Camera-off viewport stays obsidian in both themes.
                  color: AppColors.backgroundDark,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DuotoneIcon(
                          'camera',
                          size: 64,
                          color: AppColors.textPrimaryDark.withAlpha(61),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _startCamera,
                          icon: const DuotoneIcon('camera', size: 18),
                          label: const Text('Start Camera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Brand.lime,
                            foregroundColor: Brand.onLime,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Scan overlay
              const QrScanOverlay(),
              // Loading indicator
              if (provider.isScanning)
                Container(
                  color: AppColors.overlay,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: Brand.lime,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Analyzing QR code...',
                          style: TextStyle(color: AppColors.textPrimaryDark),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Manual input section
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Or enter content manually:',
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                QrManualInput(
                  onAnalyze: _onManualInput,
                  isAnalyzing: provider.isScanning,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(QrProvider provider) {
    final history = provider.history;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon(
              'qr_code',
              size: 64,
              color: context.colors.onSurface.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 16),
            Text(
              'No QR codes scanned yet',
              style: TextStyle(
                color: context.colors.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a QR code to see it here',
              style: TextStyle(
                color: context.colors.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header with clear button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${history.length} scans',
                style: TextStyle(
                  color: context.colors.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: context.colors.surface,
                      title: Text(
                        'Clear History',
                        style: TextStyle(color: context.colors.onSurface),
                      ),
                      content: Text(
                        'Are you sure you want to clear all scan history?',
                        style: TextStyle(color: context.colors.onSurfaceVariant),
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
                          child: Text(
                            'Clear',
                            style: TextStyle(color: AppColors.errorInk),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                icon: const DuotoneIcon('trash_bin_minimalistic', size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // History list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: QrHistoryItem(
                  entry: entry,
                  onTap: () {
                    if (entry.result != null) {
                      _showResultBottomSheet(entry.result!);
                    }
                  },
                  onDelete: () {
                    provider.removeFromHistory(entry.id);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTab(QrProvider provider) {
    final stats = provider.stats;
    final recentThreats = provider.recentThreats;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats card
          QrStatsCard(stats: stats),
          const SizedBox(height: 24),
          // Recent threats section
          if (recentThreats.isNotEmpty) ...[
            Text(
              'Recent Threats',
              style: BrandText.title(
                size: 18,
                color: context.colors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ...recentThreats.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: QrHistoryItem(
                    entry: entry,
                    onTap: () {
                      if (entry.result != null) {
                        _showResultBottomSheet(entry.result!);
                      }
                    },
                  ),
                )),
          ] else ...[
            GlassCard(
              child: Center(
                child: Column(
                  children: [
                    DuotoneIcon(
                      'shield_check',
                      size: 48,
                      color: AppColors.accentInk.withAlpha(179),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No threats detected',
                      style: TextStyle(
                        color: context.colors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'All your scanned QR codes are safe',
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
