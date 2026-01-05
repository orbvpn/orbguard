// lib/screens/scanning_screen.dart
// Modern animated scanning screen

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Result object from scanning screen containing all scan data
class ScanResult {
  final List<Map<String, dynamic>> threats;
  final int itemsScanned;
  final Duration scanDuration;

  ScanResult({
    required this.threats,
    required this.itemsScanned,
    required this.scanDuration,
  });
}

class ScanningScreen extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() onScan;

  const ScanningScreen({super.key, required this.onScan});

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;

  int _currentPhaseIndex = 0;
  double _overallProgress = 0.0;
  bool _scanComplete = false;
  List<Map<String, dynamic>> _threats = [];
  String _currentActivity = '';
  int _itemsScanned = 0;
  Timer? _activityTimer;
  Timer? _countTimer;
  late DateTime _scanStartTime;

  final List<ScanPhase> _phases = [
    ScanPhase(
      name: 'System Analysis',
      icon: Icons.memory,
      description: 'Checking system integrity',
      activities: ['Analyzing boot sequence', 'Checking system partitions', 'Verifying kernel modules', 'Scanning system apps'],
    ),
    ScanPhase(
      name: 'Network Security',
      icon: Icons.wifi_tethering,
      description: 'Monitoring network connections',
      activities: ['Checking active connections', 'Analyzing DNS queries', 'Scanning open ports', 'Detecting suspicious traffic'],
    ),
    ScanPhase(
      name: 'App Inspection',
      icon: Icons.apps,
      description: 'Scanning installed applications',
      activities: ['Analyzing app permissions', 'Checking app signatures', 'Scanning for malware patterns', 'Verifying app sources'],
    ),
    ScanPhase(
      name: 'File System',
      icon: Icons.folder_open,
      description: 'Scanning storage for threats',
      activities: ['Scanning downloads folder', 'Checking hidden files', 'Analyzing file signatures', 'Detecting suspicious files'],
    ),
    ScanPhase(
      name: 'Process Monitor',
      icon: Icons.account_tree,
      description: 'Analyzing running processes',
      activities: ['Checking background services', 'Analyzing process memory', 'Detecting injection attacks', 'Monitoring system calls'],
    ),
    ScanPhase(
      name: 'Threat Intelligence',
      icon: Icons.cloud_sync,
      description: 'Matching against threat database',
      activities: ['Querying threat database', 'Checking known signatures', 'Analyzing behavioral patterns', 'Correlating indicators'],
    ),
  ];

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

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  Future<void> _startScan() async {
    // Record scan start time
    _scanStartTime = DateTime.now();

    // Start activity updates
    _updateActivity();
    _startCountTimer();

    // Run through each phase
    for (int i = 0; i < _phases.length; i++) {
      if (!mounted) return;

      setState(() {
        _currentPhaseIndex = i;
      });

      // Animate progress for this phase
      final phaseProgress = (i + 1) / _phases.length;
      await _animateProgress(phaseProgress);

      // Minimum time per phase for visual effect
      await Future.delayed(Duration(milliseconds: 800 + Random().nextInt(400)));
    }

    // Run actual scan in background
    try {
      _threats = await widget.onScan();
    } catch (e) {
      print('Scan error: $e');
    }

    // Complete
    _activityTimer?.cancel();
    _countTimer?.cancel();

    if (mounted) {
      setState(() {
        _scanComplete = true;
        _overallProgress = 1.0;
      });

      // Haptic feedback
      HapticFeedback.mediumImpact();

      // Wait a moment then show results
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        final scanDuration = DateTime.now().difference(_scanStartTime);
        Navigator.pop(context, ScanResult(
          threats: _threats,
          itemsScanned: _itemsScanned,
          scanDuration: scanDuration,
        ));
      }
    }
  }

  void _updateActivity() {
    _activityTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted || _scanComplete) {
        timer.cancel();
        return;
      }

      final phase = _phases[_currentPhaseIndex];
      final activityIndex = Random().nextInt(phase.activities.length);
      setState(() {
        _currentActivity = phase.activities[activityIndex];
      });
    });
  }

  void _startCountTimer() {
    _countTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || _scanComplete) {
        timer.cancel();
        return;
      }
      setState(() {
        _itemsScanned += Random().nextInt(15) + 5;
      });
    });
  }

  Future<void> _animateProgress(double target) async {
    final startProgress = _overallProgress;
    final steps = 20;
    final stepDuration = 30;

    for (int i = 0; i <= steps; i++) {
      if (!mounted) return;
      await Future.delayed(Duration(milliseconds: stepDuration));
      setState(() {
        _overallProgress = startProgress + (target - startProgress) * (i / steps);
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _progressController.dispose();
    _activityTimer?.cancel();
    _countTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context, ScanResult(
                      threats: [],
                      itemsScanned: 0,
                      scanDuration: Duration.zero,
                    )),
                  ),
                  const Spacer(),
                  Text(
                    _scanComplete ? 'Scan Complete' : 'Scanning...',
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

            // Main scanner animation
            _buildScannerOrb(),

            const SizedBox(height: 40),

            // Progress info
            _buildProgressInfo(),

            const Spacer(),

            // Phase indicators
            _buildPhaseIndicators(),

            const SizedBox(height: 24),

            // Current activity
            _buildCurrentActivity(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerOrb() {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer rotating ring
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
                        Colors.cyan.withOpacity(0),
                        Colors.cyan.withOpacity(0.3),
                        Colors.cyan.withOpacity(0.8),
                        Colors.cyan.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Progress ring
          SizedBox(
            width: 180,
            height: 180,
            child: CircularProgressIndicator(
              value: _overallProgress,
              strokeWidth: 4,
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                _scanComplete ? Colors.green : Colors.cyan,
              ),
            ),
          ),

          // Inner pulsing orb
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scanComplete ? 1.0 : _pulseAnimation.value,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _scanComplete
                            ? Colors.green.withOpacity(0.4)
                            : Colors.cyan.withOpacity(0.4),
                        _scanComplete
                            ? Colors.green.withOpacity(0.1)
                            : Colors.cyan.withOpacity(0.1),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _scanComplete
                            ? Colors.green.withOpacity(0.3)
                            : Colors.cyan.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      _scanComplete ? Icons.check : Icons.shield,
                      size: 60,
                      color: _scanComplete ? Colors.green : Colors.cyan,
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
    return Column(
      children: [
        // Percentage
        Text(
          '${(_overallProgress * 100).toInt()}%',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: _scanComplete ? Colors.green : Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        // Items scanned
        Text(
          '${_formatNumber(_itemsScanned)} items scanned',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  Widget _buildPhaseIndicators() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(_phases.length, (index) {
          final isComplete = index < _currentPhaseIndex || _scanComplete;
          final isCurrent = index == _currentPhaseIndex && !_scanComplete;

          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isComplete
                      ? Colors.green.withOpacity(0.2)
                      : isCurrent
                          ? Colors.cyan.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                  border: Border.all(
                    color: isComplete
                        ? Colors.green
                        : isCurrent
                            ? Colors.cyan
                            : Colors.grey.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  isComplete ? Icons.check : _phases[index].icon,
                  size: 20,
                  color: isComplete
                      ? Colors.green
                      : isCurrent
                          ? Colors.cyan
                          : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 50,
                child: Text(
                  _phases[index].name.split(' ').first,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    color: isComplete || isCurrent ? Colors.white : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCurrentActivity() {
    if (_scanComplete) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(
              _threats.isEmpty ? 'No threats detected' : '${_threats.length} threats found',
              style: TextStyle(
                color: _threats.isEmpty ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Text(
          _phases[_currentPhaseIndex].name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.cyan,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _currentActivity.isEmpty
                ? _phases[_currentPhaseIndex].description
                : _currentActivity,
            key: ValueKey(_currentActivity),
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
            ),
          ),
        ),
      ],
    );
  }
}

class ScanPhase {
  final String name;
  final IconData icon;
  final String description;
  final List<String> activities;

  ScanPhase({
    required this.name,
    required this.icon,
    required this.description,
    required this.activities,
  });
}
