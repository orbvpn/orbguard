/// QR Scanner Screen
/// Main screen for QR code scanning and security analysis

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/qr_provider.dart';
import '../../widgets/qr/qr_widgets.dart';
import '../../models/api/sms_analysis.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  MobileScannerController? _scannerController;
  bool _isCameraActive = false;
  bool _isFlashOn = false;
  bool _isFrontCamera = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 0 && !_isCameraActive) {
      _startCamera();
    } else if (_tabController.index != 0 && _isCameraActive) {
      _stopCamera();
    }
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

  void _stopCamera() {
    _scannerController?.dispose();
    _scannerController = null;
    setState(() {
      _isCameraActive = false;
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
            color: GlassTheme.gradientTop,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
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
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white24),
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
                                backgroundColor: const Color(0xFF00D9FF),
                                foregroundColor: Colors.black,
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
                            onPressed: () {
                              // Report false positive
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Report submitted'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              _scannerController?.start();
                            },
                            icon: const DuotoneIcon('flag', size: 18),
                            label: const Text('Report False Positive'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.withAlpha(51),
                              foregroundColor: Colors.orange,
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
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'QR Scanner',
        showBackButton: true,
        actions: [
          if (_tabController.index == 0) ...[
            GestureDetector(
              onTap: _isCameraActive ? _toggleFlash : null,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: DuotoneIcon(
                  'bolt',
                  size: 22,
                  color: _isFlashOn ? GlassTheme.primaryAccent : Colors.white,
                ),
              ),
            ),
            GestureDetector(
              onTap: _isCameraActive ? _switchCamera : null,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: const DuotoneIcon(
                  'camera',
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ],
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
                    Tab(icon: DuotoneIcon('qr_code', size: 24), text: 'Scan'),
                    Tab(icon: DuotoneIcon('history', size: 24), text: 'History'),
                    Tab(icon: DuotoneIcon('chart', size: 24), text: 'Stats'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Consumer<QrProvider>(
              builder: (context, provider, child) {
                return TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildScannerTab(provider),
                    _buildHistoryTab(provider),
                    _buildStatsTab(provider),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerTab(QrProvider provider) {
    return Column(
      children: [
        // Camera view
        Expanded(
          flex: 3,
          child: Stack(
            children: [
              if (_isCameraActive && _scannerController != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    controller: _scannerController!,
                    onDetect: _onQrDetected,
                  ),
                )
              else
                Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DuotoneIcon(
                          'camera',
                          size: 64,
                          color: Colors.white.withAlpha(61),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _startCamera,
                          icon: const DuotoneIcon('camera', size: 18),
                          label: const Text('Start Camera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D9FF),
                            foregroundColor: Colors.black,
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
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: Color(0xFF00D9FF),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Analyzing QR code...',
                          style: TextStyle(color: Colors.white),
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
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Or enter content manually:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: QrManualInput(
                    onAnalyze: _onManualInput,
                    isAnalyzing: provider.isScanning,
                  ),
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
              color: Colors.white.withAlpha(31),
            ),
            const SizedBox(height: 16),
            Text(
              'No QR codes scanned yet',
              style: TextStyle(
                color: Colors.white.withAlpha(128),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a QR code to see it here',
              style: TextStyle(
                color: Colors.white.withAlpha(77),
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
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: GlassTheme.gradientTop,
                      title: const Text(
                        'Clear History',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: const Text(
                        'Are you sure you want to clear all scan history?',
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
                          child: const Text(
                            'Clear',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                icon: const DuotoneIcon('trash_bin_minimalistic', size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                ),
              ),
            ],
          ),
        ),
        // History list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats card
          QrStatsCard(stats: stats),
          const SizedBox(height: 24),
          // Recent threats section
          if (recentThreats.isNotEmpty) ...[
            const Text(
              'Recent Threats',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
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
                      color: Colors.green.withAlpha(179),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No threats detected',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'All your scanned QR codes are safe',
                      style: TextStyle(
                        color: Colors.white.withAlpha(128),
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
