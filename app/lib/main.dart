// lib/main.dart - OrbGuard with iOS 26 Liquid Glass Design
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'utils/platform_info.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/permission_setup_screen.dart';
import 'screens/scanning_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/onboarding/permission_priming_screen.dart';
import 'screens/home/control_panel_home_screen.dart';
import 'screens/scan/privacy_check_screen.dart';
import 'screens/scan/findings_screen.dart';
import 'services/habit/protection_streak_controller.dart';
import 'services/home/last_scan_verdict_controller.dart';
import 'services/home/guard_status_controller.dart';
import 'services/security/firewall_realtime.dart';
import 'services/security/remediation.dart';
import 'presentation/widgets/app_sheet.dart';
import 'presentation/widgets/sheet_panel.dart';
import 'screens/shields/shields_screen.dart';
import 'screens/sms_protection/sms_protection_screen.dart';
import 'screens/url_protection/url_protection_screen.dart';
import 'screens/qr_scanner/qr_scanner_screen.dart';
import 'screens/darkweb/darkweb_screen.dart';
import 'screens/app_security/app_security_screen.dart';
import 'screens/network/network_security_screen.dart';
import 'screens/mitre/mitre_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/identity/identity_protection_screen.dart';
import 'screens/enterprise/executive_protection_screen.dart';
import 'screens/security/threat_hunting_screen.dart';
import 'screens/supply_chain/supply_chain_screen.dart';
import 'screens/network/network_firewall_screen.dart';
import 'screens/shields/hidden_vpn_proxy_screen.dart';
import 'screens/shields/secure_call_screen.dart';
import 'screens/social_media/social_media_screen.dart';
import 'screens/rogue_ap/rogue_ap_screen.dart';
import 'screens/enterprise/enterprise_policy_screen.dart';
import 'screens/enterprise/enterprise_overview_screen.dart';
import 'screens/enterprise/siem_integration_screen.dart';
import 'screens/enterprise/compliance_reporting_screen.dart';
import 'screens/enterprise/stix_taxii_screen.dart';
import 'screens/intelligence/intelligence_core_screen.dart';
import 'screens/security_center_screen.dart';
import 'screens/desktop/desktop_security_screen.dart';
import 'screens/device_security/device_security_screen.dart';
import 'screens/scam/scam_detection_screen.dart';
import 'screens/forensics/forensics_screen.dart';
import 'screens/graph/threat_graph_screen.dart';
import 'screens/correlation/correlation_screen.dart';
import 'screens/ml/ml_analysis_screen.dart';
import 'screens/campaigns/campaigns_screen.dart';
import 'screens/actors/threat_actors_screen.dart';
import 'screens/privacy/privacy_protection_screen.dart';
import 'screens/playbooks/playbooks_screen.dart';
import 'screens/webhooks/webhooks_screen.dart';
import 'screens/integrations/integrations_screen.dart';
import 'permissions/special_permissions_manager.dart';
import 'detection/advanced_detection_modules.dart';
import 'intelligence/cloud_threat_intelligence.dart';

// Glass Theme & Colors
import 'presentation/theme/glass_theme.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/theme/colors.dart';
import 'presentation/widgets/glass_container.dart';
import 'presentation/widgets/duotone_icon.dart';
import 'presentation/widgets/glass_bottom_nav.dart';

// Providers
import 'providers/qr_provider.dart';
import 'providers/sms_provider.dart';
import 'providers/url_provider.dart';
import 'providers/app_security_provider.dart';
import 'providers/network_provider.dart';
import 'providers/darkweb_provider.dart';
import 'dart:async';

import 'providers/settings_provider.dart';
import 'services/security/auto_scan_scheduler.dart';
import 'services/telemetry/telemetry_service.dart';
import 'providers/mitre_provider.dart';
import 'providers/identity_protection_provider.dart';
import 'providers/executive_protection_provider.dart';
import 'providers/threat_hunting_provider.dart';
import 'providers/supply_chain_provider.dart';
import 'providers/network_firewall_provider.dart';
import 'providers/social_media_provider.dart';
import 'providers/rogue_ap_provider.dart' show RogueAPProvider;
import 'providers/enterprise_policy_provider.dart';
import 'providers/desktop_security_provider.dart';
import 'providers/device_security_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/digital_footprint_provider.dart';
import 'providers/forensics_provider.dart';
import 'providers/privacy_provider.dart';
import 'providers/scam_detection_provider.dart';
import 'providers/account_provider.dart';
import 'services/orbnet/magic_link_deep_link.dart';
import 'providers/scan_credit_provider.dart';
import 'services/ads/rewarded_ad_service.dart';
import 'services/orbnet/ad_api.dart';
import 'services/orbnet/scan_credit_api.dart';
import 'widgets/scan_credits/scan_gate.dart';
import 'models/app_mode.dart';

// API Client
import 'services/api/orbguard_api_client.dart';
import 'services/api/api_config.dart';

// On-device scan engine
import 'services/security/device_scan_service.dart';
import 'services/device_agent/app_lock.dart';

// Firebase Cloud Messaging (anti-theft push wake-ups)
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/device_agent/push_service.dart';

// Global instances
late ThreatIntelligenceManager threatIntel;
late AdvancedDetectionManager advancedDetection;
late SpecialPermissionsManager specialPermissions;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize telemetry first so Crashlytics captures startup errors. It
  // reads the Privacy opt-out toggles and no-ops when they're off (and always
  // in debug for crash reporting).
  await TelemetryService.instance.init();

  // Register the FCM background/terminated-state handler before runApp so a
  // remote anti-theft command (locate/lock/wipe/ring/selfie) wakes the device
  // even when the app is not foregrounded. DevicePushService.init() (called
  // once the device is registered) handles foreground messages + token
  // registration. Guarded so a missing/invalid Firebase config never blocks
  // app startup — the device agent still works via HTTP polling.
  // Web: background isolates/FCM background handlers don't exist in the
  // browser sandbox — skip registration entirely.
  if (kFirebaseEnabled && !PlatformInfo.isWeb) {
    try {
      FirebaseMessaging.onBackgroundMessage(orbGuardFirebaseBackgroundHandler);
    } catch (_) {
      // Firebase not configured for this build — polling remains the fallback.
    }
  }

  // Apply a user-set custom server URL (Settings) before the client inits —
  // otherwise the setting persists but is silently ignored. Validated + falls
  // back to the default on empty/malformed input.
  try {
    final prefs = await SharedPreferences.getInstance();
    // Only override the base URL when the user has explicitly enabled the
    // "Use Custom Server" toggle — otherwise a stored URL would silently win
    // even after the toggle is switched back off.
    final useCustom = prefs.getBool('api_custom') ?? false;
    final customUrl = prefs.getString('api_url')?.trim();
    if (useCustom &&
        customUrl != null &&
        customUrl.isNotEmpty &&
        (Uri.tryParse(customUrl)?.hasScheme ?? false)) {
      ApiConfig.setBaseUrl(customUrl);
    }
    // Apply the user's connection-timeout setting before the client inits.
    final timeoutSeconds = prefs.getInt('api_timeout');
    if (timeoutSeconds != null) {
      ApiConfig.setTimeoutSeconds(timeoutSeconds);
    }
  } catch (_) {
    // Prefs unavailable — keep the default base URL and timeouts.
  }

  // Initialize OrbGuard API Client first
  await OrbGuardApiClient.instance.init(
    baseUrl: ApiConfig.baseUrl,
    enableLogging: true,
  );

  // Initialize threat intelligence
  threatIntel = ThreatIntelligenceManager(
    apiUrl: '${ApiConfig.baseUrl}${ApiConfig.apiVersion}/intelligence',
    apiKey: '', // API key managed by auth interceptor
  );

  // Load threat intelligence in the BACKGROUND — never block first paint on
  // the network. A slow or absent connection must not trap the user on the
  // splash; onboarding and the Guard home don't depend on it. Auto-updates
  // start once the initial load settles.
  unawaited(threatIntel.initialize().then((_) {
    ThreatIntelligenceAutoUpdater(threatIntel).startAutoUpdate();
  }));

  // Initialize advanced detection
  advancedDetection = AdvancedDetectionManager();

  // Initialize special permissions manager
  specialPermissions = SpecialPermissionsManager();
  await specialPermissions.checkPermissions();

  runApp(const AntiSpywareApp());
}

class AntiSpywareApp extends StatelessWidget {
  const AntiSpywareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => QrProvider()),
        ChangeNotifierProvider(create: (_) => SmsProvider()..init()),
        ChangeNotifierProvider(create: (_) => UrlProvider()),
        ChangeNotifierProvider(create: (_) => AppSecurityProvider()..init()),
        ChangeNotifierProvider(create: (_) => NetworkProvider()),
        ChangeNotifierProvider(create: (_) => DarkWebProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..init()),
        ChangeNotifierProvider(
            create: (_) => ProtectionStreakController()..load()),
        ChangeNotifierProvider(
            create: (_) => LastScanVerdictController()..load()),
        ChangeNotifierProvider(create: (_) => MitreProvider()),
        ChangeNotifierProvider(create: (_) => IdentityProtectionProvider()),
        ChangeNotifierProvider(create: (_) => ExecutiveProtectionProvider()),
        ChangeNotifierProvider(create: (_) => ThreatHuntingProvider()),
        ChangeNotifierProvider(create: (_) => SupplyChainProvider()),
        ChangeNotifierProvider(create: (_) => NetworkFirewallProvider()),
        ChangeNotifierProvider(create: (_) => SocialMediaProvider()),
        ChangeNotifierProvider(create: (_) => RogueAPProvider()),
        ChangeNotifierProvider(create: (_) => EnterprisePolicyProvider()),
        ChangeNotifierProvider(create: (_) => DesktopSecurityProvider()),
        ChangeNotifierProvider(
            lazy: false, create: (_) => DeviceSecurityProvider()..init()),
        // These screens read their provider via Consumer/context.read but the
        // providers were never registered — navigating to them threw
        // ProviderNotFoundError. Registered here like the rest.
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => DigitalFootprintProvider()),
        ChangeNotifierProvider(create: (_) => ForensicsProvider()),
        ChangeNotifierProvider(create: (_) => PrivacyProvider()),
        ChangeNotifierProvider(create: (_) => ScamDetectionProvider()),
        // Shared OrbVPN/OrbNet account state. Hydrates from secure storage on
        // start (login is optional; anonymous device registration is untouched).
        ChangeNotifierProvider(create: (_) => AccountProvider()..init()),
        // Scan credits: earn by watching a rewarded ad, spend one per scan.
        // Uses the shared authenticated OrbNet client; reads the account for the
        // "sign in to earn/use credits" rule (registered AFTER AccountProvider
        // so it's resolvable here).
        ChangeNotifierProvider(
          create: (ctx) {
            final account = ctx.read<AccountProvider>();
            return ScanCreditProvider(
              adApi: AdApi(),
              scanCreditApi: ScanCreditApi(),
              adService: DefaultRewardedAdService(),
              isLoggedIn: () => account.isLoggedIn,
            );
          },
        ),
      ],
      child: _PremiumModeSync(
        child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: 'OrbGuard',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: settings.themeMode,
          // Automatic screen-view analytics (no-op when analytics is disabled).
          navigatorObservers: [
            if (TelemetryService.instance.navigatorObserver != null)
              TelemetryService.instance.navigatorObserver!,
          ],
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            // Sync the brand token system with the active theme BEFORE any
            // Brand.*/AppColors.* getter resolves — this is what flips every
            // glass/ink token between light and dark.
            AppColors.uiBrightness =
                isDark ? Brightness.dark : Brightness.light;
            return GlassGradientBackground(
              isDark: isDark,
              child: AppLockGate(child: child ?? const SizedBox.shrink()),
            );
          },
          home: settings.isLoading
              // Prefs still loading — the ambient gradient shows briefly; avoids
              // flashing onboarding at returning users before the flag loads.
              ? const SizedBox.shrink()
              : !settings.hasSeenOnboarding
                  ? OnboardingScreen(onDone: settings.completeOnboarding)
                  : !settings.permissionsPrimed
                      // First-run permission priming: value-first, staged,
                      // skippable — the app finally asks for what it needs.
                      ? PermissionPrimingScreen(onDone: settings.completePriming)
                      : const HomeScreen(),
        ),
        ),
      ),
    );
  }
}

/// Keeps the persisted experience mode honest: Pro/expert is premium-only, so
/// if the account loses entitlement (sign-out or a lapsed subscription) while
/// Pro is still on, revert to the always-free Guard. Watches both providers,
/// reverts on the next frame (guarded on [AccountProvider.isInitialized] so a
/// premium user is never bounced to Guard during the brief startup window
/// before the saved session hydrates), and returns [child] untouched.
class _PremiumModeSync extends StatelessWidget {
  final Widget child;
  const _PremiumModeSync({required this.child});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final account = context.watch<AccountProvider>();
    if (account.isInitialized && settings.isProMode && !account.hasPremium) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (settings.isProMode && !account.hasPremium) {
          settings.setAppMode(AppMode.guard);
        }
      });
    }
    return child;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.orb.guard/system');

  // Bottom navigation state
  int _currentNavIndex = 0;

  bool _hasRootAccess = false;
  String _accessMethod = 'Standard';
  final List<ThreatDetection> _threats = [];
  double _detectionCapability = 0.0;

  // Real proof-of-work for the home feed: surveillance domains the Android
  // DNS firewall actually blocked today (0 when off / not Android / native
  // absent — the feed shows its honest empty state at 0, never a fake number).
  final FirewallRealtime _firewallRt = FirewallRealtime();
  int _blockedToday = 0;

  // Live guard states for the control-panel home. Each probe reads a REAL
  // source (auto-scan setting, firewall state, granted permissions); breach
  // and hidden-VPN start as "check to verify" until a real check populates
  // them. Refreshed after first frame and on every resume.
  late final GuardStatusController _guards = GuardStatusController(probes: [
    GuardProbes.spywareWatch(
        autoScanOn: () async =>
            context.read<SettingsProvider>().scan.autoScanEnabled),
    GuardProbes.firewall(
        supported: PlatformInfo.isAndroid,
        enabled: () async => context.read<NetworkFirewallProvider>().isEnabled),
    GuardProbes.smsFilter(
        supported: PlatformInfo.isAndroid,
        granted: () async => await Permission.sms.isGranted),
    GuardProbes.malwareScan(supported: PlatformInfo.isAndroid),
    GuardProbes.alerts(granted: () async => await Permission.notification.isGranted),
    GuardProbes.breachMonitor(breachedAccounts: () async => null),
    GuardProbes.hiddenVpn(unknownVpnActive: () async => null),
    GuardProbes.secureCall(
        supported: PlatformInfo.isAndroid || PlatformInfo.isIOS),
  ]);

  // Signs the user in when they tap the orbguard://login?code=… magic link.
  late final MagicLinkDeepLinkHandler _magicLink =
      MagicLinkDeepLinkHandler(_signInWithMagicCode);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guards.refresh();
      _refreshActivity();
      _maybeRunFirstCheck();
      unawaited(_magicLink.start());
    });
    _initializeApp();
  }

  // Exchange a magic-link code (from the deep link) for a session. The backend
  // token is self-contained, so no email is needed (the field is unused there).
  Future<void> _signInWithMagicCode(String code) async {
    if (!mounted) return;
    final account = context.read<AccountProvider>();
    if (account.isLoggedIn) return; // already signed in — ignore stale links
    // Capture across the async gap so we don't touch context after await.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await account.verifyMagicCode('', code);
    if (!mounted) return;
    if (ok) {
      // The deep link fires under HomeScreen; the login screen is pushed on top.
      // Pop back to home so the user lands signed-in instead of being stranded
      // on the sign-in screen.
      navigator.popUntil((route) => route.isFirst);
    }
    messenger.showSnackBar(SnackBar(
      content:
          Text(ok ? 'Signed in' : 'That sign-in link is invalid or expired'),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _guards.dispose();
    _magicLink.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh permissions when app returns to foreground
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
    }
  }

  Future<void> _refreshPermissions() async {
    await specialPermissions.checkPermissions();
    await _calculateDetectionCapability();
    unawaited(_guards.refresh());
    unawaited(_refreshActivity());
    setState(() {});
  }

  /// Run the automatic first checkup once, right after first-run priming, so
  /// the user gets the "your first check found N things" moment instead of a
  /// static home. Guarded by a one-shot pref; Guard mode only.
  void _maybeRunFirstCheck() {
    if (!mounted) return;
    final s = context.read<SettingsProvider>();
    if (s.isProMode || !s.permissionsPrimed || s.firstCheckDone) return;
    s.markFirstCheckDone();
    // The onboarding "your first check found N things" moment is free — not
    // user-initiated, and never an ad prompt on first run.
    _startScan(userInitiated: false);
  }

  /// Pull the real "blocked today" count for the home's proof-of-work feed.
  Future<void> _refreshActivity() async {
    if (!PlatformInfo.isAndroid) return;
    final n = await _firewallRt.blockedToday();
    if (mounted) setState(() => _blockedToday = n);
  }

  /// Route a tapped guard tile straight to where it's actually set up or run —
  /// not the generic Protect hub. Scan-based guards run a check; alerts asks
  /// for the permission; each feature guard opens its own screen (as a sheet).
  void _onGuardTap(String id) {
    switch (id) {
      case 'alerts':
        _requestAlerts();
      case 'spyware_watch':
      case 'malware_scan':
        _startScan();
      case 'firewall':
        showAppSheet(context,
            heightFactor: 0.94, child: const NetworkFirewallScreen());
      case 'sms_filter':
        showAppSheet(context,
            heightFactor: 0.94, child: const SmsProtectionScreen());
      case 'breach':
        showAppSheet(context,
            heightFactor: 0.94, child: const DarkWebScreen());
      case 'hidden_vpn':
        showAppSheet(context,
            heightFactor: 0.94, child: const HiddenVpnProxyScreen());
      case 'secure_call':
        showAppSheet(context,
            heightFactor: 0.94, child: const SecureCallScreen());
      default:
        setState(() => _currentNavIndex = 4); // Protect hub
    }
  }

  /// Route a "thing to fix" from the privacy-score card to its remedy.
  void _onFactorTap(String id) {
    switch (id) {
      case 'run_check':
      case 'resolve_threats':
      case 'review_apps':
        _startScan();
      case 'enable_alerts':
        _requestAlerts();
      default:
        setState(() => _currentNavIndex = 4); // Protect hub
    }
  }

  Future<void> _requestAlerts() async {
    await Permission.notification.request();
    await _guards.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _initializeApp() async {
    await _checkSystemAccess();
    await _checkAllPermissions();
    await _calculateDetectionCapability();
    // Foreground catch-up for the automatic scan: runs only if enabled and
    // due (self-throttled). Covers iOS/desktop where OS background scheduling
    // is unavailable; on Android the WorkManager cycle also drives it.
    unawaited(AutoScanScheduler.instance.runIfDue());
  }

  Future<void> _checkSystemAccess() async {
    try {
      final result = await platform.invokeMethod('checkRootAccess');
      setState(() {
        _hasRootAccess = result['hasRoot'] ?? false;
        _accessMethod = result['method'] ?? 'Standard';
      });

      if (_accessMethod != 'Standard') {
        debugPrint('[OrbGuard] Access method detected: $_accessMethod');
      }
    } catch (e) {
      setState(() {
        _accessMethod = 'Standard';
      });
    }
  }

  Future<void> _checkAllPermissions() async {
    await specialPermissions.checkPermissions();
  }

  Future<void> _calculateDetectionCapability() async {
    // Browser sandbox: no device permissions, MethodChannels or scanning —
    // report the honest base capability instead of probing unavailable
    // plugins.
    if (PlatformInfo.isWeb) {
      setState(() => _detectionCapability = 25.0);
      return;
    }

    // Base capability from standard APIs
    double capability = 25.0;

    // Add capability based on granted permissions (45% total)
    if (await Permission.phone.isGranted) capability += 5;
    if (await Permission.sms.isGranted) capability += 10;
    if (await Permission.location.isGranted) capability += 5;

    // Storage - check via native method for Android 11+
    try {
      final storageResult =
          await platform.invokeMethod('checkStoragePermission');
      if (storageResult['hasPermission'] == true) capability += 10;
    } catch (e) {
      if (await Permission.storage.isGranted) capability += 10;
    }

    // Special permissions (25% total)
    if (specialPermissions.hasUsageStats) capability += 15;
    if (specialPermissions.hasAccessibility) capability += 10;

    // Enhanced/Root access (15% total)
    if (_hasRootAccess) {
      capability += 15;
    } else if (_accessMethod == 'Shell' || _accessMethod == 'AppProcess') {
      capability += 10;
    }

    setState(() {
      _detectionCapability = capability.clamp(0, 100);
    });
  }

  Future<void> _startScan({bool? deepScan, bool userInitiated = true}) async {
    // Check if we have enough permissions
    if (_detectionCapability < 50) {
      _showPermissionWarning();
      return;
    }

    // Scan-credit gate: subscribers scan freely; free users spend one credit
    // (earning more via a rewarded ad). Only user-initiated scans are metered —
    // the one-shot first-run check and background auto-scans are exempt.
    if (userInitiated && !await ensureScanCredit(context)) return;
    if (!mounted) return;

    // Honor the Deep Scan setting unless a caller explicitly overrides it.
    final effectiveDeepScan =
        deepScan ?? context.read<SettingsProvider>().scan.deepScanEnabled;

    // Navigate to scanning screen
    final scanResult = await Navigator.push<ScanResult>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            PrivacyCheckScreen(
          onScanWithProgress: (onProgress) =>
              DeviceScanService.instance.performScan(
            deepScan: effectiveDeepScan,
            hasRoot: _hasRootAccess,
            onProgress: onProgress,
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );

    // A completed checkup — clean or not — extends the "days protected" streak
    // AND records the honest verdict the home reads (score from real findings
    // + real coverage), so scanning genuinely moves the home status.
    if (scanResult != null && mounted) {
      context.read<ProtectionStreakController>().recordCheckup(DateTime.now());
      context.read<LastScanVerdictController>().recordScan(
            threats: scanResult.threats,
            coveragePercent: _detectionCapability.round(),
            now: DateTime.now(),
          );
    }

    // The honest findings screen handles BOTH outcomes: a list of threats to
    // fix, or a calm all-clear that states how many checks genuinely ran.
    if (scanResult != null) {
      setState(() {
        _threats
          ..clear()
          ..addAll(scanResult.threats.map(ThreatDetection.fromJson));
      });
      debugPrint('[OrbGuard] Scan complete: ${_threats.length} threats');
      if (mounted) {
        // Results present as an iOS sheet (slides up over the home), not a
        // full-screen push.
        final threats = scanResult.threats;
        showAppSheet(
          context,
          heightFactor: 0.94,
          child: FindingsScreen(
            threats: threats,
            checksRun: scanResult.itemsScanned,
            onOpenThreat: _remediate,
            onFixAll: threats.isNotEmpty
                ? () => _remediate(_mostSevere(threats))
                : null,
          ),
        );
      }
    }
  }


  final Remediation _remediation = Remediation();

  static const _severityRank = {
    'CRITICAL': 0,
    'HIGH': 1,
    'MEDIUM': 2,
    'LOW': 3,
    'INFO': 4,
  };

  /// The most-severe threat, so "Fix these" starts with what matters most.
  Map<String, dynamic> _mostSevere(List<Map<String, dynamic>> threats) {
    final sorted = [...threats]..sort((a, b) {
        final ra = _severityRank['${a['severity']}'.toUpperCase()] ?? 5;
        final rb = _severityRank['${b['severity']}'.toUpperCase()] ?? 5;
        return ra - rb;
      });
    return sorted.first;
  }

  /// Take the user to the real, one-tap fix for a finding: the app's App Info
  /// (uninstall/disable) or the system VPN settings (disconnect). When there's
  /// no device-native fix, point them at the right place.
  Future<void> _remediate(Map<String, dynamic> threat) async {
    final opened = await _remediation.fix(threat);
    if (opened || !mounted) return;
    final guidance = Remediation.kindFor(threat) == RemediationKind.guidanceOnly
        ? 'Open the Protect tab to review and resolve this.'
        : "Couldn't open the system screen — resolve it manually in Settings.";
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(guidance)));
  }

  void _showPermissionWarning() {
    showAppSheet(
      context,
      child: SheetPanel(
        title: 'Enable deeper scanning',
        body: Text(
          'OrbGuard can check your device more thoroughly with a few extra '
          'permissions. Current coverage: ${_detectionCapability.round()}%.\n\n'
          'Set them up now?',
          style: TextStyle(
            fontSize: 14.5,
            height: 1.45,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        secondaryLabel: 'Not now',
        primaryLabel: 'Set up permissions',
        onPrimary: _navigateToPermissionSetup,
      ),
    );
  }

  void _navigateToPermissionSetup() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PermissionSetupScreen(),
      ),
    );

    if (result == true) {
      await _checkAllPermissions();
      await _calculateDetectionCapability();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final backgroundColor =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final textColor = cs.onSurface;
    final iconColor = cs.onSurfaceVariant;

    // Guard mode (default) hides the expert "Intel" tab; Pro shows it.
    // Destinations keep STABLE ids (0=Home,1=Scan,2=Intel,3=Settings) so the
    // body switch is independent of a tab's visible position, and switching
    // modes can never strand the user on a hidden tab.
    final isPro = context.watch<SettingsProvider>().isProMode;
    // Guard: Home · Protect(shields) · Scan · Settings. Pro swaps in the expert
    // Intel tab and drops the consumer Protect hub.
    final navDests = isPro ? const [0, 1, 2, 3] : const [0, 4, 1, 3];
    final effIndex = navDests.contains(_currentNavIndex) ? _currentNavIndex : 0;

    // The Intel tab owns the whole screen: its Browse/Check/History selector is
    // the single bottom bar, with a Home button top-left (no shell header/nav) —
    // avoids stacking two navigation bars.
    if (effIndex == 2) {
      return Scaffold(
        backgroundColor: backgroundColor,
        drawer: _buildNavigationDrawer(isPro),
        body: IntelligenceCoreScreen(
          asMainTab: true,
          onHome: () => setState(() => _currentNavIndex = 0),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: _buildNavigationDrawer(isPro),
      body: Stack(
        children: [
          // Main content (constrained on wide screens, centered)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: GlassTheme.contentMaxWidth),
                child: Column(
                  children: [
                    // OrbX-style header
                    _buildOrbXHeader(isDark, textColor, iconColor),
                    // Body content — viewport ends above the floating nav
                    Expanded(
                      child: _buildCurrentScreen(effIndex),
                    ),
                    const SizedBox(height: GlassTheme.bottomNavClearance),
                  ],
                ),
              ),
            ),
          ),
          // Bottom navigation bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: GlassTheme.contentMaxWidth),
                child: GlassBottomNavBar(
                  currentIndex: navDests.indexOf(effIndex),
                  onTap: (pos) {
                    setState(() {
                      _currentNavIndex = navDests[pos];
                    });
                  },
                  items: navDests.map(_navItemFor).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// OrbX-style header: round menu button LEFT, pill title RIGHT
  Widget _buildOrbXHeader(bool isDark, Color textColor, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Menu button (round glass, 50x50)
          Builder(
            builder: (context) => GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: Container(
                width: 50,
                height: 50,
                decoration: GlassTheme.circularGlassDecoration(isDark: isDark),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: GlassTheme.blurFilter,
                    child: Center(
                      child: DuotoneIcon(
                        AppIcons.menu,
                        size: 22,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title area — floats over the page with NO background bar.
          Expanded(
            child: SizedBox(
              height: 50,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                      children: [
                        // Title text
                        Expanded(
                          child: Text(
                            'OrbGuard',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        // Permission status icon
                        GestureDetector(
                          onTap: _navigateToPermissionSetup,
                          child: DuotoneIcon(
                            AppIcons.shieldCheck,
                            size: 22,
                            // Use the theme-aware INK getters, not the raw fills
                            // (lime/pink fills are invisible on the light bed).
                            color: _detectionCapability >= 80
                                ? AppColors.accentInk
                                : _detectionCapability >= 50
                                    ? AppColors.amberInk
                                    : AppColors.errorInk,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Info icon
                        GestureDetector(
                          onTap: _showAboutDialog,
                          child: DuotoneIcon(
                            AppIcons.infoCircle,
                            size: 22,
                            color: iconColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// Build current screen based on navigation index
  Widget _buildCurrentScreen(int index) {
    switch (index) {
      case 0:
        return _buildHomeContent();
      case 1:
        return _buildScanContent();
      case 2:
        return _buildIntelContent();
      case 3:
        return _buildSettingsContent();
      case 4:
        return const ShieldsScreen();
      default:
        return _buildHomeContent();
    }
  }

  /// Bottom-nav item for a stable destination id (0=Home,1=Scan,2=Intel,3=Settings).
  NavItem _navItemFor(int dest) {
    switch (dest) {
      case 1:
        return NavItem(label: 'Scan', iconPath: AppIcons.search);
      case 2:
        return NavItem(label: 'Intel', iconPath: AppIcons.structure);
      case 3:
        return NavItem(label: 'Settings', iconPath: AppIcons.settings);
      case 4:
        return NavItem(label: 'Protect', iconPath: AppIcons.shieldCheck);
      case 0:
      default:
        return NavItem(label: 'Home', iconPath: AppIcons.home);
    }
  }

  /// Home tab content - Security Center
  Widget _buildHomeContent() {
    // Guard (default) gets the calm single-verdict home; Pro keeps the fuller
    // Security Center dashboard.
    if (context.watch<SettingsProvider>().isProMode) {
      return const SecurityCenterScreen();
    }
    return ControlPanelHomeScreen(
      onRunCheck: () => _startScan(),
      verdict: context.watch<LastScanVerdictController>(),
      guardsController: _guards,
      streak: context.watch<ProtectionStreakController>(),
      onGuardTap: _onGuardTap,
      onFactorTap: _onFactorTap,
      blockedTodayCount: () => _blockedToday,
    );
  }

  /// Scan tab content
  Widget _buildScanContent() {
    // On desktop platforms, show the DesktopSecurityScreen directly (embedded mode)
    if (PlatformInfo.isMacOS ||
        PlatformInfo.isWindows ||
        PlatformInfo.isLinux) {
      return const DesktopSecurityScreen(embedded: true);
    }

    // On mobile, show the scan button UI
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlassCircleButton(
            size: 120,
            tintColor: AppColors.accent,
            onTap: () => _startScan(),
            child: DuotoneIcon(
              AppIcons.search,
              size: 56,
              color: AppColors.accentInk,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tap to Start Scan',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Detection capability: ${_detectionCapability.round()}%',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Intel tab content - show Intelligence Core
  Widget _buildIntelContent() {
    // A tab should show its content, not a launcher button — embed the
    // Intelligence Core on every platform.
    return const IntelligenceCoreScreen(embedded: true);
  }

  /// Settings tab content - show Settings
  Widget _buildSettingsContent() {
    // A tab should show its content, not a launcher button — embed the
    // Settings screen on every platform.
    return const SettingsScreen(embedded: true);
  }

  Widget _buildNavigationDrawer(bool isPro) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final textColor = cs.onSurface;
    final secondaryColor = cs.onSurfaceVariant;

    return Drawer(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: Container(
            decoration: BoxDecoration(
              // Heavy glass panel over the brand bed — obsidian/white tint.
              color: isDark
                  ? AppColors.backgroundDark.withAlpha(200)
                  : AppColors.surfaceLight.withAlpha(240),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // Header Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withAlpha(isDark ? 40 : 25),
                          AppColors.accent.withAlpha(isDark ? 20 : 12),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: AppColors.accent.withAlpha(isDark ? 60 : 40),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: AppColors.accent.withAlpha(30),
                            border: Border.all(
                                color: AppColors.accent.withAlpha(60),
                                width: 1),
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                                'assets/branding/orbguard_icon.svg',
                                width: 36,
                                height: 36),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('OrbGuard',
                                  style: TextStyle(
                                      color: textColor,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5)),
                              const SizedBox(height: 4),
                              Text('Mobile Security Suite',
                                  style: TextStyle(
                                      color: secondaryColor, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildDrawerItem(
                    svgIcon: 'widget_5',
                    title: 'Dashboard',
                    subtitle: 'Real-time threat overview',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DashboardScreen(),
                          ));
                    },
                  ),
                  const GlassDivider(isDark: true),
                  _buildDrawerSection('Protection'),
                  _buildDrawerItem(
                    svgIcon: 'chat_dots',
                    title: 'SMS Protection',
                    subtitle: 'Phishing & scam text detection',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SmsProtectionScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'link_round',
                    title: 'URL Protection',
                    subtitle: 'Malicious link scanner',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const UrlProtectionScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'qr_code',
                    title: 'QR Scanner',
                    subtitle: 'Safe QR code scanning',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const QrScannerScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'danger_triangle',
                    title: 'Scam Detection',
                    subtitle: 'AI text, URL & call scam analysis',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ScamDetectionScreen(),
                          ));
                    },
                  ),
                  const GlassDivider(isDark: true),
                  _buildDrawerSection('Security'),
                  _buildDrawerItem(
                    svgIcon: 'smartphone',
                    title: 'App Security',
                    subtitle: 'Installed app analysis',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AppSecurityScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'wi_fi_router',
                    title: 'Network Security',
                    subtitle: 'Wi-Fi & network protection',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NetworkSecurityScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'incognito',
                    title: 'Dark Web Monitor',
                    subtitle: 'Credential breach detection',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DarkWebScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'wi_fi_router_round',
                    title: 'Rogue AP Detection',
                    subtitle: 'Evil twin & fake hotspots',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RogueAPScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'shield_network',
                    title: 'Network Firewall',
                    subtitle: 'Per-app network rules',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NetworkFirewallScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'smartphone',
                    title: 'Device Security',
                    subtitle: 'Anti-theft, SIM & OS protection',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DeviceSecurityScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'magnifer',
                    title: 'Forensics',
                    subtitle: 'Spyware & Pegasus analysis',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ForensicsScreen(),
                          ));
                    },
                  ),
                  // Expert console — threat-intelligence tools (Pro mode only).
                  if (isPro) ...[
                    const GlassDivider(isDark: true),
                    _buildDrawerSection('Intelligence'),
                    _buildDrawerItem(
                      svgIcon: 'structure',
                      title: 'Intelligence Core',
                      subtitle: 'Threat intel browsing & IOC check',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const IntelligenceCoreScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'widget_4',
                      title: 'MITRE ATT&CK',
                      subtitle: 'Threat framework mapping',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MitreScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'magnifer_bug',
                      title: 'Threat Hunting',
                      subtitle: 'Proactive threat detection',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ThreatHuntingScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'box',
                      title: 'Supply Chain',
                      subtitle: 'Dependency vulnerabilities',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SupplyChainScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'graph_new',
                      title: 'Threat Graph',
                      subtitle: 'Entity relationship explorer',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ThreatGraphScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'routing',
                      title: 'Correlation',
                      subtitle: 'Cross-indicator correlation engine',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CorrelationScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'cpu',
                      title: 'ML Analysis',
                      subtitle: 'Anomaly detection & insights',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MLAnalysisScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'flag',
                      title: 'Campaigns',
                      subtitle: 'Tracked threat campaigns',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CampaignsScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'users_group_rounded',
                      title: 'Threat Actors',
                      subtitle: 'APT & actor profiles',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ThreatActorsScreen(),
                            ));
                      },
                    ),
                  ],
                  const GlassDivider(isDark: true),
                  _buildDrawerSection('Identity & Privacy'),
                  _buildDrawerItem(
                    svgIcon: 'user_id',
                    title: 'Identity Protection',
                    subtitle: 'Credit & identity monitoring',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const IdentityProtectionScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'share',
                    title: 'Social Media',
                    subtitle: 'Account security monitoring',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SocialMediaScreen(),
                          ));
                    },
                  ),
                  _buildDrawerItem(
                    svgIcon: 'shield_keyhole',
                    title: 'Privacy Protection',
                    subtitle: 'Permission & tracker audit',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const PrivacyProtectionScreen(),
                          ));
                    },
                  ),
                  // Expert console — enterprise tools (Pro mode only).
                  if (isPro) ...[
                    const GlassDivider(isDark: true),
                    _buildDrawerSection('Enterprise'),
                    _buildDrawerItem(
                      svgIcon: 'crown',
                      title: 'Executive Protection',
                      subtitle: 'VIP & BEC fraud detection',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ExecutiveProtectionScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'clipboard_text',
                      title: 'Enterprise Policy',
                      subtitle: 'MDM & compliance policies',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const EnterprisePolicyScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'widget_5',
                      title: 'Enterprise Overview',
                      subtitle: 'Organization security status',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const EnterpriseOverviewScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'server_square',
                      title: 'SIEM Integration',
                      subtitle: 'Splunk, ELK, ArcSight',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const SiemIntegrationScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'document_add',
                      title: 'Compliance Reports',
                      subtitle: 'SOC2, GDPR, HIPAA, PCI-DSS',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ComplianceReportingScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'transfer_horizontal',
                      title: 'STIX/TAXII',
                      subtitle: 'Threat intelligence sharing',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const StixTaxiiScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'play_circle',
                      title: 'Playbooks',
                      subtitle: 'Automated response playbooks',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const PlaybooksScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'socket',
                      title: 'Webhooks',
                      subtitle: 'Event notifications & delivery',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const WebhooksScreen(),
                            ));
                      },
                    ),
                    _buildDrawerItem(
                      svgIcon: 'plug_circle',
                      title: 'Integrations',
                      subtitle: 'Third-party service connections',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const IntegrationsScreen(),
                            ));
                      },
                    ),
                  ],
                  const GlassDivider(isDark: true),
                  _buildDrawerItem(
                    svgIcon: 'settings',
                    title: 'Settings',
                    subtitle: 'App configuration',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ));
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.7),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required String svgIcon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final textColor = cs.onSurface;
    final secondaryColor = cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              // Neutral row tint from the scheme (theme-aware).
              color: cs.onSurface.withValues(alpha: 0.04),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.accent.withAlpha(isDark ? 25 : 15),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      svgIcon,
                      size: 18,
                      color: AppColors.accentInk,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: secondaryColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                DuotoneIcon(
                  AppIcons.chevronRight,
                  size: 14,
                  color: secondaryColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showAppSheet(
      context,
      heightFactor: 0.7,
      child: SheetPanel(
        title: 'About OrbGuard',
        titleIcon: SvgPicture.asset('assets/branding/orbguard_icon.svg',
            width: 26, height: 26),
        body: Text(
          'OrbGuard - Advanced Spyware Defense\n\n'
          'Finds and removes advanced spyware, including Pegasus, using '
          'whatever level of device access is available:\n\n'
          '• Full access if your device is rooted\n'
          '• Deeper system access where your device supports it\n'
          '• System-level scanning\n'
          '• Standard device checks\n\n'
          '✓ No extra apps required\n'
          '✓ All scanning happens on your device\n'
          '✓ No data sent to servers\n'
          '✓ Automatically uses the deepest access your device allows\n'
          '✓ Up-to-date threat information from the cloud\n'
          '✓ Uses extra permissions for stronger detection\n\n'
          'Your privacy and security are our priority.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        primaryLabel: 'Close',
      ),
    );
  }
}

// Data Models
class ThreatDetection {
  final String id;
  String name;
  String description;
  String severity;
  final String type;
  final String path;
  final bool requiresRoot;
  final Map<String, dynamic> metadata;

  ThreatDetection({
    required this.id,
    required this.name,
    required this.description,
    required this.severity,
    required this.type,
    required this.path,
    required this.requiresRoot,
    required this.metadata,
  });

  factory ThreatDetection.fromJson(Map<String, dynamic> json) {
    return ThreatDetection(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      severity: json['severity'] ?? 'MEDIUM',
      type: json['type'] ?? '',
      path: json['path'] ?? '',
      requiresRoot: json['requiresRoot'] ?? false,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'severity': severity,
      'type': type,
      'path': path,
      'requiresRoot': requiresRoot,
      'metadata': metadata,
    };
  }
}
