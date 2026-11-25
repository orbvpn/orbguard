// lib/services/security/apk_file_scanner.dart
//
// Scoped APK/file scanner. The user picks the file(s) (SAF via file_picker) and
// the native side inspects each APK with PackageManager WITHOUT installing it —
// package, signer, permissions — then flags spyware-style permission combos,
// debug-signed builds, and package-impersonation (same package, different signer).
//
// Deliberately scoped: only the picked files are read, so this needs NO all-files
// (MANAGE_EXTERNAL_STORAGE) access. Nothing leaves the device.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One risk finding inside a scanned APK.
class ApkFinding {
  const ApkFinding({
    required this.type,
    required this.severity,
    required this.title,
    required this.detail,
  });

  final String type;
  final String severity; // CRITICAL | HIGH | MEDIUM
  final String title;
  final String detail;

  factory ApkFinding.fromMap(Map<dynamic, dynamic> m) => ApkFinding(
        type: (m['type'] ?? '').toString(),
        severity: (m['severity'] ?? 'MEDIUM').toString(),
        title: (m['title'] ?? '').toString(),
        detail: (m['detail'] ?? '').toString(),
      );
}

/// Result of scanning one APK file.
class ApkScanResult {
  const ApkScanResult({
    required this.path,
    required this.fileName,
    required this.packageName,
    required this.versionName,
    required this.sizeBytes,
    required this.permissionCount,
    required this.severity,
    required this.findings,
    this.error,
  });

  final String path;
  final String fileName;
  final String packageName;
  final String versionName;
  final int sizeBytes;
  final int permissionCount;

  /// CRITICAL | HIGH | MEDIUM | CLEAN
  final String severity;
  final List<ApkFinding> findings;

  /// Set when the file could not be parsed (not an APK, unreadable…).
  final String? error;

  bool get isClean => error == null && severity == 'CLEAN';
  bool get failed => error != null;

  factory ApkScanResult.fromMap(Map<dynamic, dynamic> m) {
    final err = m['error']?.toString();
    return ApkScanResult(
      path: (m['path'] ?? '').toString(),
      fileName: (m['fileName'] ?? '').toString(),
      packageName: (m['packageName'] ?? '').toString(),
      versionName: (m['versionName'] ?? '').toString(),
      sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
      permissionCount: (m['permissionCount'] as num?)?.toInt() ?? 0,
      severity: (m['severity'] ?? (err != null ? 'ERROR' : 'CLEAN')).toString(),
      findings: ((m['findings'] as List?) ?? const [])
          .whereType<Map>()
          .map(ApkFinding.fromMap)
          .toList(),
      error: err,
    );
  }
}

class ApkFileScannerService {
  ApkFileScannerService._();
  static final ApkFileScannerService instance = ApkFileScannerService._();

  static const MethodChannel _channel = MethodChannel('com.orb.guard/system');

  /// Let the user pick APK file(s), then scan them. Returns an empty list when
  /// the user cancels. Never throws.
  Future<List<ApkScanResult>> pickAndScan() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );
      final paths = picked?.files
              .map((f) => f.path)
              .whereType<String>()
              .where((p) => p.toLowerCase().endsWith('.apk'))
              .toList() ??
          const <String>[];
      if (paths.isEmpty) return const [];
      return scanPaths(paths);
    } catch (e) {
      debugPrint('[OrbGuard] APK pick failed: $e');
      return const [];
    }
  }

  /// Scan APKs already on disk at [paths].
  Future<List<ApkScanResult>> scanPaths(List<String> paths) async {
    if (paths.isEmpty) return const [];
    try {
      final res = await _channel.invokeMethod<Map>(
        'scanApkFiles',
        {'paths': paths},
      );
      final list = (res?['results'] as List?) ?? const [];
      return list.whereType<Map>().map(ApkScanResult.fromMap).toList();
    } on PlatformException catch (e) {
      debugPrint('[OrbGuard] APK scan failed: ${e.code}');
      return const [];
    } catch (e) {
      debugPrint('[OrbGuard] APK scan error: $e');
      return const [];
    }
  }
}
