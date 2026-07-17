// Device Scan Service
//
// Shared on-device threat scan used by the dashboard and the home screen.
// It drives the exact same native scan flow as `lib/main.dart`'s
// `_performScan` (the `com.orb.guard/system` MethodChannel methods plus the
// advanced Dart detection modules) and reports real per-stage progress.
//
// Honesty contract:
// - Progress callbacks are emitted only when a stage genuinely starts or
//   finishes; there are no timers or random counters.
// - When the native scan channel is not registered on this build, the scan
//   throws [DeviceScanUnavailableException] instead of returning an empty
//   "all clear" result.
// - Per-stage failures are recorded and surfaced in the progress stream;
//   they never silently become "0 threats".

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../detection/advanced_detection_modules.dart';
import 'app_malware_scanner.dart';

/// Thrown when the scan engine cannot run at all on this build.
class DeviceScanUnavailableException implements Exception {
  final String message;

  DeviceScanUnavailableException(this.message);

  @override
  String toString() => message;
}

/// Real progress update for a running device scan.
class DeviceScanProgress {
  /// Zero-based index of the stage this update refers to.
  final int stageIndex;

  /// Total number of scan stages.
  final int totalStages;

  /// Human-readable stage name (e.g. "Network connections").
  final String stageName;

  /// Whether the stage has finished (true) or just started (false).
  final bool stageCompleted;

  /// Total threats found so far across all completed stages.
  final int threatsFound;

  /// Error message when this stage failed; null when it ran cleanly.
  final String? stageError;

  const DeviceScanProgress({
    required this.stageIndex,
    required this.totalStages,
    required this.stageName,
    required this.stageCompleted,
    required this.threatsFound,
    this.stageError,
  });

  /// Fraction of stages fully completed (0.0 - 1.0).
  double get fraction => totalStages == 0
      ? 0
      : ((stageIndex + (stageCompleted ? 1 : 0)) / totalStages)
          .clamp(0.0, 1.0);
}

/// Callback type for scan progress updates.
typedef DeviceScanProgressCallback = void Function(DeviceScanProgress update);

class _ScanStage {
  final String name;

  /// Runs the stage and returns the threats it found.
  final Future<List<Map<String, dynamic>>> Function() run;

  /// Whether the stage talks to the native scan channel (used to decide
  /// engine availability).
  final bool isNative;

  const _ScanStage(this.name, this.run, {required this.isNative});
}

/// Shared on-device scan engine wrapper.
class DeviceScanService {
  DeviceScanService._();

  static final DeviceScanService instance = DeviceScanService._();

  /// Same channel `lib/main.dart` uses for its scan flow.
  static const _channel = MethodChannel('com.orb.guard/system');

  final AdvancedDetectionManager _detection = AdvancedDetectionManager();

  /// Run a full device scan, mirroring `_performScan` in `lib/main.dart`.
  ///
  /// Emits a [DeviceScanProgress] when each stage starts and finishes.
  /// Returns the real combined threat list.
  ///
  /// Throws [DeviceScanUnavailableException] when no scan stage could run at
  /// all because the native channel is unregistered on this platform build.
  Future<List<Map<String, dynamic>>> performScan({
    bool deepScan = false,
    bool hasRoot = false,
    DeviceScanProgressCallback? onProgress,
  }) async {
    final allThreats = <Map<String, dynamic>>[];

    Future<List<Map<String, dynamic>>> native(String method) async {
      final result = await _channel.invokeMethod(method);
      final threats = <Map<String, dynamic>>[];
      final rawThreats = (result as Map?)?['threats'];
      if (rawThreats is List) {
        for (final threat in rawThreats) {
          threats.add(Map<String, dynamic>.from(threat as Map));
        }
      }
      return threats;
    }

    final stages = <_ScanStage>[
      _ScanStage('Network connections', () => native('scanNetwork'),
          isNative: true),
      _ScanStage('Running processes', () => native('scanProcesses'),
          isNative: true),
      _ScanStage('File system', () => native('scanFileSystem'),
          isNative: true),
      _ScanStage('App databases', () => native('scanDatabases'),
          isNative: true),
      _ScanStage('Memory', () => native('scanMemory'), isNative: true),
      _ScanStage('Behavioral analysis', () => _detection.runModule('behavioral'),
          isNative: false),
      _ScanStage('Certificate analysis',
          () => _detection.runModule('certificate'),
          isNative: false),
      _ScanStage('Permission abuse', () => _detection.runModule('permission'),
          isNative: false),
      _ScanStage('Accessibility abuse',
          () => _detection.runModule('accessibility'),
          isNative: false),
      _ScanStage('Keylogger detection', () => _detection.runModule('keylogger'),
          isNative: false),
      _ScanStage('Location stalkers', () => _detection.runModule('location'),
          isNative: false),
      // Real malware scan of installed apps (Android only; throws
      // DetectionUnsupportedException on iOS/desktop → honest "not supported").
      _ScanStage('App malware scan', () => AppMalwareScanner().scan(),
          isNative: false),
    ];

    // Initialize the native scan; a MissingPluginException here means the
    // scan engine is not part of this build at all.
    var nativeChannelAvailable = true;
    try {
      await _channel.invokeMethod('initializeScan', {
        'deepScan': deepScan || hasRoot,
        'hasRoot': hasRoot,
      });
    } on MissingPluginException {
      nativeChannelAvailable = false;
      debugPrint('DeviceScanService: native scan channel "com.orb.guard/system" '
          'is not registered on this build');
    } on PlatformException catch (e) {
      // The channel exists but init failed; native stages may still work.
      debugPrint('DeviceScanService: initializeScan failed: ${e.message}');
    }

    var anyStageSucceeded = false;
    for (var i = 0; i < stages.length; i++) {
      final stage = stages[i];

      onProgress?.call(DeviceScanProgress(
        stageIndex: i,
        totalStages: stages.length,
        stageName: stage.name,
        stageCompleted: false,
        threatsFound: allThreats.length,
      ));

      String? stageError;
      if (stage.isNative && !nativeChannelAvailable) {
        stageError = 'unavailable on this build';
      } else {
        try {
          final threats = await stage.run();
          allThreats.addAll(threats);
          anyStageSucceeded = true;
        } on DetectionUnsupportedException catch (e) {
          // The capability doesn't exist on this platform (e.g. iOS can't
          // enumerate installed apps / certs / a11y services / keyboards).
          // Report it honestly rather than as a fake "clean, 0 findings".
          stageError = 'not supported on this device';
          debugPrint('DeviceScanService: stage "${stage.name}" not supported '
              'on this platform: ${e.message}');
        } on MissingPluginException {
          if (stage.isNative) nativeChannelAvailable = false;
          stageError = 'unavailable on this build';
          debugPrint(
              'DeviceScanService: stage "${stage.name}" has no native handler');
        } catch (e) {
          stageError = e.toString();
          debugPrint('DeviceScanService: stage "${stage.name}" failed: $e');
        }
      }

      onProgress?.call(DeviceScanProgress(
        stageIndex: i,
        totalStages: stages.length,
        stageName: stage.name,
        stageCompleted: true,
        threatsFound: allThreats.length,
        stageError: stageError,
      ));
    }

    if (!anyStageSucceeded) {
      throw DeviceScanUnavailableException(
          'Device scan engine is not available on this build: no scan stage '
          'could run (native channel "com.orb.guard/system" is not '
          'registered and the detection modules failed).');
    }

    debugPrint(
        'DeviceScanService: scan complete, ${allThreats.length} threats found');
    return allThreats;
  }
}
