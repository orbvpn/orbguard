// lib/screens/scanning_screen.dart
// Animated scanning screen driven by REAL scan-stage callbacks.
//
// Honesty contract:
// - Progress and stage labels come from DeviceScanProgress events emitted by
//   the actual scan engine (no timers, no Random()).
// - When only a plain `onScan` callback is provided (legacy path from
//   lib/main.dart) the screen shows an indeterminate spinner — it never
//   fabricates percentages or "items scanned" counters.
// - Cancelling pops `null` (a cancelled scan is not an "all clear" result).
// - Scan failures (including "scan engine not available on this build") are
//   shown explicitly and pop `null` instead of an empty success.

import 'dart:async';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../presentation/widgets/duotone_icon.dart';
import '../services/security/device_scan_service.dart';

/// Result object from scanning screen containing all scan data
class ScanResult {
  final List<Map<String, dynamic>> threats;

  /// Number of scan stages that genuinely ran. (The native scanners do not
  /// report per-item counts, so no per-item number is fabricated here.)
  final int itemsScanned;
  final Duration scanDuration;

  ScanResult({
    required this.threats,
    required this.itemsScanned,
    required this.scanDuration,
  });
}

/// Scan runner that reports real per-stage progress.
typedef ProgressScanRunner = Future<List<Map<String, dynamic>>> Function(
    DeviceScanProgressCallback onProgress);

class ScanningScreen extends StatefulWidget {
  /// Legacy runner without progress reporting (used by lib/main.dart).
  /// The screen shows honest indeterminate progress for this path.
  final Future<List<Map<String, dynamic>>> Function()? onScan;

  /// Preferred runner that emits real [DeviceScanProgress] updates.
  final ProgressScanRunner? onScanWithProgress;

  const ScanningScreen({super.key, this.onScan, this.onScanWithProgress})
      : assert(onScan != null || onScanWithProgress != null,
            'Provide onScan or onScanWithProgress');

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;

  // Real progress state (null progress = indeterminate legacy path).
  double? _overallProgress;
  String _stageName = '';
  int _stagesCompleted = 0;
  int _totalStages = 0;
  int _threatsSoFar = 0;
  final List<String> _stageWarnings = [];

  bool _scanComplete = false;
  bool _scanFailed = false;
  String _failureMessage = '';
  List<Map<String, dynamic>> _threats = [];
  late DateTime _scanStartTime;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startScan();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotationController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
  }

  void _onProgress(DeviceScanProgress update) {
    if (!mounted) return;
    setState(() {
      _totalStages = update.totalStages;
      _stageName = update.stageName;
      _threatsSoFar = update.threatsFound;
      if (update.stageCompleted) {
        _stagesCompleted = update.stageIndex + 1;
        if (update.stageError != null) {
          _stageWarnings.add('${update.stageName}: ${update.stageError}');
        }
      }
      _overallProgress = update.fraction;
    });
  }

  Future<void> _startScan() async {
    _scanStartTime = DateTime.now();

    try {
      if (widget.onScanWithProgress != null) {
        _overallProgress = 0.0;
        _threats = await widget.onScanWithProgress!(_onProgress);
      } else {
        // Legacy path: no stage data available — indeterminate, not faked.
        _overallProgress = null;
        _threats = await widget.onScan!();
      }
    } on DeviceScanUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _scanFailed = true;
        _failureMessage = e.message;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanFailed = true;
        _failureMessage = 'Scan failed: $e';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _scanComplete = true;
      _overallProgress = 1.0;
    });

    HapticFeedback.mediumImpact();

    // Brief pause so the completed state is visible, then return results.
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      final scanDuration = DateTime.now().difference(_scanStartTime);
      Navigator.pop(
        context,
        ScanResult(
          threats: _threats,
          itemsScanned: _stagesCompleted,
          scanDuration: scanDuration,
        ),
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: DuotoneIcon('close_circle',
                        size: 24,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    // A cancelled scan is NOT a clean result; pop null so the
                    // caller does not show an "all clear" dialog.
                    onPressed: () => Navigator.pop(context, null),
                  ),
                  const Spacer(),
                  Text(
                    _scanFailed
                        ? 'Scan Unavailable'
                        : _scanComplete
                            ? 'Scan Complete'
                            : 'Scanning...',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            const Spacer(),

            _buildScannerOrb(),

            const SizedBox(height: 40),

            _buildProgressInfo(),

            const Spacer(),

            _buildStatusArea(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Color get _accentColor => _scanFailed
      ? Colors.redAccent
      : _scanComplete
          ? Colors.green
          : Colors.cyan;

  Widget _buildScannerOrb() {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer rotating ring (cosmetic spinner, not a progress claim)
          if (!_scanComplete && !_scanFailed)
            AnimatedBuilder(
              animation: _rotationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotationController.value * 2 * pi,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          Colors.cyan.withValues(alpha: 0),
                          Colors.cyan.withValues(alpha: 0.3),
                          Colors.cyan.withValues(alpha: 0.8),
                          Colors.cyan.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Progress ring: real fraction when stage data exists, otherwise
          // an indeterminate spinner (value: null).
          SizedBox(
            width: 180,
            height: 180,
            child: CircularProgressIndicator(
              value: _scanFailed ? 0 : _overallProgress,
              strokeWidth: 4,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
            ),
          ),

          // Inner pulsing orb
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: (_scanComplete || _scanFailed)
                    ? 1.0
                    : _pulseAnimation.value,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _accentColor.withValues(alpha: 0.4),
                        _accentColor.withValues(alpha: 0.1),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      _scanFailed
                          ? 'danger_circle'
                          : _scanComplete
                              ? 'check_circle'
                              : 'shield_check',
                      size: 60,
                      color: _accentColor,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProgressInfo() {
    if (_scanFailed) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Percentage only when real stage progress exists.
        if (_overallProgress != null)
          Text(
            '${(_overallProgress! * 100).toInt()}%',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: _scanComplete
                  ? Colors.green
                  : Theme.of(context).colorScheme.onSurface,
            ),
          )
        else
          Text(
            'Scanning device…',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        const SizedBox(height: 8),
        if (_totalStages > 0)
          Text(
            '$_stagesCompleted of $_totalStages scan stages completed',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        if (_threatsSoFar > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$_threatsSoFar threat${_threatsSoFar == 1 ? '' : 's'} found so far',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.orange,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusArea() {
    if (_scanFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _failureMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, null),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    if (_scanComplete) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DuotoneIcon('check_circle',
                    size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  _threats.isEmpty
                      ? 'No threats detected'
                      : '${_threats.length} threat${_threats.length == 1 ? '' : 's'} found',
                  style: TextStyle(
                    color: _threats.isEmpty ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (_stageWarnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_stageWarnings.length} scan stage'
                  '${_stageWarnings.length == 1 ? '' : 's'} could not run:\n'
                  '${_stageWarnings.join('\n')}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange[300],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Running: show the real current stage.
    return Column(
      children: [
        if (_stageName.isNotEmpty)
          Text(
            _stageName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.cyan,
            ),
          ),
        if (_stageWarnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _stageWarnings.last,
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[300],
              ),
            ),
          ),
      ],
    );
  }
}
