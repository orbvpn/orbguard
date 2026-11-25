// Native spyware/stalkerware scanner for Windows.
//
// Implements the `com.orb.guard/system` MethodChannel contract that the Dart
// scan pipeline (lib/services/security/device_scan_service.dart and
// lib/detection/advanced_detection_modules.dart) already speaks on Android and
// iOS. Every method returns REAL findings read from this machine; a check that
// cannot run reports itself as unsupported rather than returning an empty
// "clean" result.
#ifndef RUNNER_ORBGUARD_SCANNER_H_
#define RUNNER_ORBGUARD_SCANNER_H_

#include <flutter/encodable_value.h>

#include <string>

namespace orbguard {

// Severity strings the Dart layer maps onto its own ramp.
inline constexpr const char* kSeverityCritical = "CRITICAL";
inline constexpr const char* kSeverityHigh = "HIGH";
inline constexpr const char* kSeverityMedium = "MEDIUM";
inline constexpr const char* kSeverityLow = "LOW";

// Each Scan* function returns {"threats": [ …threat maps… ]}, matching the
// Android handlers. A threat map carries:
//   id, name, description, severity, type, path, requiresRoot, metadata
flutter::EncodableValue ScanProcesses();
flutter::EncodableValue ScanNetwork();
flutter::EncodableValue ScanFileSystem();
flutter::EncodableValue ScanDatabases();
flutter::EncodableValue ScanMemory();

// Detection-module inputs. Shapes mirror what the Dart modules index into.
flutter::EncodableValue GetInstalledCertificates();  // {"certificates": [...]}
flutter::EncodableValue GetInstalledApps();          // {"apps": [...]}
flutter::EncodableValue GetAccessibilityServices();  // {"services": [...]}
flutter::EncodableValue GetInstalledKeyboards();     // {"keyboards": [...]}
flutter::EncodableValue GetLocationAccessHistory(int hours);  // {"accesses": [...]}

// Invalidates the per-scan caches (process snapshot, signature budget). The
// Dart pipeline calls `initializeScan` before every run, which is where this
// belongs: without it, a second scan reuses the first scan's process list and
// has no signature-check budget left.
void BeginScan();

// {"hasRoot": bool, "method": string} — on Windows "root" means elevated.
flutter::EncodableValue CheckElevatedAccess();

}  // namespace orbguard

#endif  // RUNNER_ORBGUARD_SCANNER_H_
