// Desktop persistence-scanner configuration.
//
// Backs the Desktop "Persistence Scanner" settings screen. These toggles were
// previously local widget state (cosmetic — never saved, never read). They now
// persist to SharedPreferences and are honored by the platform scanners:
//   - the per-target flags gate which persistence categories are inspected,
//   - deepScan enables the extra/advanced categories,
//   - autoScanOnStartup / scanIntervalHours drive automatic scans.

import 'package:shared_preferences/shared_preferences.dart';

class DesktopScanConfig {
  final bool autoScanOnStartup;
  final int scanIntervalHours;
  final bool scanLaunchAgents;
  final bool scanLaunchDaemons;
  final bool scanLoginItems;
  final bool scanKernelExtensions;
  final bool scanBrowserExtensions;
  final bool scanCronJobs;
  final bool deepScan;
  final bool hashVerification;

  const DesktopScanConfig({
    this.autoScanOnStartup = true,
    this.scanIntervalHours = 24,
    this.scanLaunchAgents = true,
    this.scanLaunchDaemons = true,
    this.scanLoginItems = true,
    this.scanKernelExtensions = true,
    this.scanBrowserExtensions = true,
    this.scanCronJobs = true,
    this.deepScan = false,
    this.hashVerification = true,
  });

  DesktopScanConfig copyWith({
    bool? autoScanOnStartup,
    int? scanIntervalHours,
    bool? scanLaunchAgents,
    bool? scanLaunchDaemons,
    bool? scanLoginItems,
    bool? scanKernelExtensions,
    bool? scanBrowserExtensions,
    bool? scanCronJobs,
    bool? deepScan,
    bool? hashVerification,
  }) {
    return DesktopScanConfig(
      autoScanOnStartup: autoScanOnStartup ?? this.autoScanOnStartup,
      scanIntervalHours: scanIntervalHours ?? this.scanIntervalHours,
      scanLaunchAgents: scanLaunchAgents ?? this.scanLaunchAgents,
      scanLaunchDaemons: scanLaunchDaemons ?? this.scanLaunchDaemons,
      scanLoginItems: scanLoginItems ?? this.scanLoginItems,
      scanKernelExtensions: scanKernelExtensions ?? this.scanKernelExtensions,
      scanBrowserExtensions: scanBrowserExtensions ?? this.scanBrowserExtensions,
      scanCronJobs: scanCronJobs ?? this.scanCronJobs,
      deepScan: deepScan ?? this.deepScan,
      hashVerification: hashVerification ?? this.hashVerification,
    );
  }

  static const _kAuto = 'desktop_scan_auto_startup';
  static const _kInterval = 'desktop_scan_interval_hours';
  static const _kLaunchAgents = 'desktop_scan_launch_agents';
  static const _kLaunchDaemons = 'desktop_scan_launch_daemons';
  static const _kLoginItems = 'desktop_scan_login_items';
  static const _kKernelExt = 'desktop_scan_kernel_ext';
  static const _kBrowserExt = 'desktop_scan_browser_ext';
  static const _kCron = 'desktop_scan_cron';
  static const _kDeep = 'desktop_scan_deep';
  static const _kHash = 'desktop_scan_hash_verify';

  static Future<DesktopScanConfig> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return DesktopScanConfig(
        autoScanOnStartup: p.getBool(_kAuto) ?? true,
        scanIntervalHours: p.getInt(_kInterval) ?? 24,
        scanLaunchAgents: p.getBool(_kLaunchAgents) ?? true,
        scanLaunchDaemons: p.getBool(_kLaunchDaemons) ?? true,
        scanLoginItems: p.getBool(_kLoginItems) ?? true,
        scanKernelExtensions: p.getBool(_kKernelExt) ?? true,
        scanBrowserExtensions: p.getBool(_kBrowserExt) ?? true,
        scanCronJobs: p.getBool(_kCron) ?? true,
        deepScan: p.getBool(_kDeep) ?? false,
        hashVerification: p.getBool(_kHash) ?? true,
      );
    } catch (_) {
      return const DesktopScanConfig();
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAuto, autoScanOnStartup);
    await p.setInt(_kInterval, scanIntervalHours);
    await p.setBool(_kLaunchAgents, scanLaunchAgents);
    await p.setBool(_kLaunchDaemons, scanLaunchDaemons);
    await p.setBool(_kLoginItems, scanLoginItems);
    await p.setBool(_kKernelExt, scanKernelExtensions);
    await p.setBool(_kBrowserExt, scanBrowserExtensions);
    await p.setBool(_kCron, scanCronJobs);
    await p.setBool(_kDeep, deepScan);
    await p.setBool(_kHash, hashVerification);
  }
}
