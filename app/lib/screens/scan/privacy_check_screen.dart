// lib/screens/scan/privacy_check_screen.dart
// Honest scan theatre — shows the REAL work the privacy check does.
//
// Drop-in replacement for ScanningScreen's progress path: it takes the same
// `onScanWithProgress` runner and pops the same [ScanResult], so the parent
// swaps it in 1:1 at the Navigator.push call site.
//
// Honesty contract (inherited from scanning_screen.dart):
// - The ring fraction, checklist states and every count come from real
//   [DeviceScanProgress] events emitted by the scan engine — no timers,
//   no Random(), no invented per-item numbers.
// - The waiting checklist is seeded from the engine's known stage list; if
//   the engine reports a different number of stages, the speculative rows
//   are dropped immediately and only genuinely announced checks (plus the
//   engine's own real remaining count) are shown.
// - A stage that errors or is unsupported shows "Couldn't run on this
//   device" — it is never rendered as a passed check.
// - "N found" chips appear only when the number is real: the change in the
//   engine's threatsFound across a stage's start/finish events.
// - Cancelling pops null (a cancelled check is not an "all clear");
//   failures show an explicit error state and pop null, never an empty
//   success.

import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/theme/spacing.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../services/security/device_scan_service.dart';
import '../scanning_screen.dart' show ScanResult;

enum _CheckState { waiting, running, done, unavailable }

class _CheckRow {
  _CheckRow(this.rawName, this.label);

  final String rawName;
  final String label;
  _CheckState state = _CheckState.waiting;

  /// Whether the engine has emitted at least one event for this stage.
  bool announced = false;

  /// threatsFound when the stage started — used to derive the REAL per-stage
  /// found count. Null until the start event arrives (no start event = no
  /// chip; the delta would be a guess).
  int? threatsBefore;

  /// Real number of findings this stage produced (0 = no chip shown).
  int found = 0;
}

class PrivacyCheckScreen extends StatefulWidget {
  /// Runner that performs the real scan and emits [DeviceScanProgress]
  /// events — same shape as ScanningScreen's `onScanWithProgress`, e.g.
  /// `(onProgress) => DeviceScanService.instance.performScan(onProgress: onProgress, ...)`.
  final Future<List<Map<String, dynamic>>> Function(
      void Function(DeviceScanProgress)) onScanWithProgress;

  /// When true (default) the screen pops itself with the [ScanResult] after
  /// a brief completion beat — identical to ScanningScreen's contract, so
  /// the parent awaits the same `Navigator.push<ScanResult>` result and
  /// decides what to show next (e.g. push FindingsScreen). When false the
  /// screen stays on its completed state and the caller owns dismissal.
  final bool popWithResult;

  const PrivacyCheckScreen({
    super.key,
    required this.onScanWithProgress,
    this.popWithResult = true,
  });

  @override
  State<PrivacyCheckScreen> createState() => _PrivacyCheckScreenState();
}

class _PrivacyCheckScreenState extends State<PrivacyCheckScreen>
    with SingleTickerProviderStateMixin {
  /// The scan engine's stage list, in its real execution order
  /// (see DeviceScanService.performScan). Used only to name the waiting
  /// rows up-front; every state change still requires a real event.
  static const List<String> _expectedCheckOrder = [
    'Network connections',
    'Running processes',
    'File system',
    'App databases',
    'Memory',
    'Behavioral analysis',
    'Certificate analysis',
    'Permission abuse',
    'Accessibility abuse',
    'Keylogger detection',
    'Location stalkers',
  ];

  /// Plain-language names for each real scan stage — same translations as
  /// ScanningScreen's private `_friendlyStages` map (kept in sync by
  /// test/screens/privacy_check_flow_test.dart): the checkup should read
  /// like "scanning for spyware", not "Accessibility abuse".
  static const Map<String, String> _friendlyChecks = {
    'Network connections': 'Inspecting network connections',
    'Running processes': 'Checking active apps',
    'File system': 'Scanning files',
    'App databases': 'Checking app data',
    'Memory': 'Inspecting device memory',
    'Behavioral analysis': 'Watching for suspicious activity',
    'Certificate analysis': 'Testing for network interception',
    'Permission abuse': 'Auditing app permissions',
    'Accessibility abuse': 'Scanning for spyware & stalkerware',
    'Keylogger detection': 'Checking for keyloggers',
    'Location stalkers': 'Checking for location tracking',
  };

  static String _friendlyLabel(String raw) {
    final mapped = _friendlyChecks[raw];
    if (mapped != null) return mapped;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Device check';
    // Sensible Title Case fallback for stages added to the engine later.
    return trimmed
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  late final AnimationController _rotationController;
  bool _animationsEnabled = true;

  late List<_CheckRow> _rows;

  // Real progress state — only ever written from DeviceScanProgress events.
  int _stagesCompleted = 0;
  int _totalStages = 0;
  int _threatsSoFar = 0;
  bool _sawFirstEvent = false;

  /// True when the engine's stage count didn't match the seeded list, so the
  /// speculative named rows were dropped in favour of announced-only rows.
  bool _collapsed = false;

  bool _scanComplete = false;
  bool _scanFailed = false;
  String _failureMessage = '';
  List<Map<String, dynamic>> _threats = [];
  late DateTime _scanStartTime;

  double get _fraction => _scanComplete
      ? 1.0
      : (_totalStages == 0 ? 0.0 : _stagesCompleted / _totalStages);

  /// Engine-reported checks not yet announced (collapsed mode only) — a real
  /// count from totalStages, never an invented list of names.
  int get _queuedCount {
    if (!_collapsed || _totalStages == 0 || _scanComplete) return 0;
    final remaining = _totalStages - _rows.where((r) => r.announced).length;
    return remaining > 0 ? remaining : 0;
  }

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final raw in _expectedCheckOrder) _CheckRow(raw, _friendlyLabel(raw))
    ];
    _rotationController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );
    _startScan();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsEnabled = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _syncRotation();
  }

  void _syncRotation() {
    final shouldSpin = _animationsEnabled && !_scanComplete && !_scanFailed;
    if (shouldSpin && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!shouldSpin && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  _CheckRow? _rowFor(String rawName) {
    for (final row in _rows) {
      if (row.rawName == rawName) return row;
    }
    return null;
  }

  void _onProgress(DeviceScanProgress update) {
    if (!mounted) return;
    setState(() {
      if (!_sawFirstEvent) {
        _sawFirstEvent = true;
        if (update.totalStages != _rows.length) {
          // The engine is running a different set of checks than the
          // well-known list — drop the speculative waiting rows and only
          // show checks the engine genuinely announces.
          _collapsed = true;
          _rows.removeWhere((r) => !r.announced);
        }
      }

      _totalStages = update.totalStages;
      _threatsSoFar = update.threatsFound;

      var row = _rowFor(update.stageName);
      if (row == null) {
        row = _CheckRow(update.stageName, _friendlyLabel(update.stageName));
        _rows.add(row);
      }
      row.announced = true;

      if (update.stageCompleted) {
        // Mirrors ScanningScreen: completed stages (including unavailable
        // ones) advance the honest "stages completed" counter.
        _stagesCompleted = update.stageIndex + 1;
        row.state = update.stageError == null
            ? _CheckState.done
            : _CheckState.unavailable;
        final before = row.threatsBefore;
        if (before != null) {
          final delta = update.threatsFound - before;
          row.found = delta > 0 ? delta : 0;
        }
      } else {
        row.state = _CheckState.running;
        row.threatsBefore = update.threatsFound;
      }
    });
  }

  Future<void> _startScan() async {
    _scanStartTime = DateTime.now();

    try {
      _threats = await widget.onScanWithProgress(_onProgress);
    } on DeviceScanUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _scanFailed = true;
        _failureMessage = e.message;
      });
      _syncRotation();
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanFailed = true;
        _failureMessage = 'Scan failed: $e';
      });
      _syncRotation();
      return;
    }

    if (!mounted) return;
    setState(() {
      _scanComplete = true;
      // Rows the engine never announced didn't run — drop them rather than
      // leave a named check that silently never happened.
      _rows.removeWhere((r) => !r.announced);
    });
    _syncRotation();

    HapticFeedback.mediumImpact();

    // Brief completion beat: ring at 100%, checklist fully settled.
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted || !widget.popWithResult) return;

    // Same ScanResult construction as ScanningScreen: threats, the number of
    // stages that genuinely completed, and the real duration. The PARENT
    // decides what screen shows the results (e.g. FindingsScreen).
    Navigator.pop(
      context,
      ScanResult(
        threats: _threats,
        itemsScanned: _stagesCompleted,
        scanDuration: DateTime.now().difference(_scanStartTime),
      ),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Privacy check',
      // Cancelling is NOT an "all clear": pop null so the caller never
      // mistakes a dismissed check for a clean result.
      onBack: () => Navigator.pop(context, null),
      body: _scanFailed ? _buildFailureBody(context) : _buildScanBody(context),
    );
  }

  // ---------------------------------------------------------------------
  // Running / complete
  // ---------------------------------------------------------------------

  Widget _buildScanBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.md),
        _buildRing(context),
        const SizedBox(height: AppSpacing.xl),
        Text(
          _scanComplete ? 'Check complete' : 'Running your privacy check',
          style: BrandText.heading(size: 18, color: scheme.onSurface),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_totalStages > 0)
          Text(
            '$_stagesCompleted of $_totalStages checks done',
            style: BrandText.body(size: 13.5, color: scheme.onSurfaceVariant),
          ),
        if (_threatsSoFar > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '$_threatsSoFar found so far',
              style: BrandText.label(size: 12.5, color: AppColors.secondaryInk),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              0,
              AppSpacing.screenHorizontal,
              AppSpacing.xxl,
            ),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final row in _rows) _buildCheckRow(context, row),
                  if (_queuedCount > 0) _buildQueuedRow(context, _queuedCount),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRing(BuildContext context) {
    final fraction = _fraction;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 176,
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Decorative slow sweep while running (cosmetic, not a progress
          // claim) — skipped entirely when the OS asks for no animations.
          if (!_scanComplete && _animationsEnabled)
            AnimatedBuilder(
              animation: _rotationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotationController.value * 2 * pi,
                  child: Container(
                    width: 176,
                    height: 176,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0),
                          AppColors.accent.withValues(alpha: 0.08),
                          AppColors.accent.withValues(alpha: 0.22),
                          AppColors.accent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Real progress arc: stagesCompleted / totalStages — lime arc on a
          // low-alpha track.
          SizedBox(
            width: 150,
            height: 150,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: fraction),
              duration: _animationsEnabled
                  ? const Duration(milliseconds: 400)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return CircularProgressIndicator(
                  value: value,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.idle.withValues(alpha: 0.2),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.accentInk),
                );
              },
            ),
          ),

          Text(
            '${(fraction * 100).round()}%',
            style: BrandText.display(
              size: 36,
              color: _scanComplete ? AppColors.accentInk : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckRow(BuildContext context, _CheckRow row) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    final Widget leading = switch (row.state) {
      _CheckState.done =>
        DuotoneIcon('check_circle', size: 20, color: AppColors.accentInk),
      _CheckState.running => SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accentInk,
          ),
        ),
      _CheckState.unavailable =>
        DuotoneIcon('minus_circle', size: 20, color: muted),
      _CheckState.waiting => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: muted.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
        ),
    };

    final nameColor = (row.state == _CheckState.waiting ||
            row.state == _CheckState.unavailable)
        ? muted
        : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(width: 22, height: 22, child: Center(child: leading)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: BrandText.body(
                    size: 14.5,
                    weight: FontWeight.w500,
                    color: nameColor,
                  ),
                ),
                if (row.state == _CheckState.unavailable)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      "Couldn't run on this device",
                      style: BrandText.label(
                        size: 11,
                        color: AppColors.amberInk,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (row.found > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            _buildFoundChip(row.found),
          ],
        ],
      ),
    );
  }

  /// Honest count chip: only rendered when the engine reported the number.
  Widget _buildFoundChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      ),
      child: Text(
        '$count found',
        style: BrandText.label(size: 11, color: AppColors.secondaryInk),
      ),
    );
  }

  /// Collapsed mode only: the engine said there are more checks than it has
  /// announced so far — show its real remaining count, not invented names.
  Widget _buildQueuedRow(BuildContext context, int count) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Center(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: muted.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '$count more ${count == 1 ? 'check' : 'checks'} queued',
              style: BrandText.body(size: 14.5, color: muted),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Failure — explicit, never an empty success
  // ---------------------------------------------------------------------

  Widget _buildFailureBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon('danger_circle', size: 56, color: AppColors.errorInk),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "The check couldn't run",
              textAlign: TextAlign.center,
              style: BrandText.heading(size: 20, color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _failureMessage,
              textAlign: TextAlign.center,
              style: BrandText.body(size: 14, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xxl),
            BrandButton.secondary(
              label: 'Close',
              expand: false,
              onPressed: () => Navigator.pop(context, null),
            ),
          ],
        ),
      ),
    );
  }
}
