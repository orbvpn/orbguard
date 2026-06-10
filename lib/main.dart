// lib/main.dart - OrbGuard with iOS 26 Liquid Glass Design
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'screens/scan_results_screen.dart';
import 'screens/permission_setup_screen.dart';
import 'screens/scanning_screen.dart';
import 'screens/dashboard_screen.dart';
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
import 'permissions/special_permissions_manager.dart';
import 'detection/advanced_detection_modules.dart';
import 'intelligence/cloud_threat_intelligence.dart';

// Glass Theme & Colors
import 'presentation/theme/glass_theme.dart';
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
import 'providers/settings_provider.dart';
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

// API Client
import 'services/api/orbguard_api_client.dart';
import 'services/api/api_config.dart';

// On-device scan engine
import 'services/security/device_scan_service.dart';

// Global instances
late ThreatIntelligenceManager threatIntel;
late AdvancedDetectionManager advancedDetection;
late SpecialPermissionsManager specialPermissions;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  await threatIntel.initialize();

  // Start auto-updates
  final autoUpdater = ThreatIntelligenceAutoUpdater(threatIntel);
  autoUpdater.startAutoUpdate();

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
        ChangeNotifierProvider(create: (_) => AppSecurityProvider()),
        ChangeNotifierProvider(create: (_) => NetworkProvider()),
        ChangeNotifierProvider(create: (_) => DarkWebProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..init()),
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
      ],
      child: MaterialApp(
        title: 'OrbGuard',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          primaryColor: AppColors.primary,
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            secondary: AppColors.secondary,
            error: AppColors.error,
            surface: AppColors.surfaceDark,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
          cardTheme: CardThemeData(
            color: GlassTheme.glassColorDark,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GlassTheme.radiusLarge),
            ),
          ),
        ),
        builder: (context, child) {
          return GlassGradientBackground(
            isDark: true,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const HomeScreen(),
      ),
    );
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    setState(() {});
  }

  Future<void> _initializeApp() async {
    await _checkSystemAccess();
    await _checkAllPermissions();
    await _calculateDetectionCapability();
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
    // Base capability from standard APIs
    double capability = 25.0;

    // Add capability based on granted permissions (45% total)
    if (await Permission.phone.isGranted) capability += 5;
    if (await Permission.sms.isGranted) capability += 10;
    if (await Permission.location.isGranted) capability += 5;

    // Storage - check via native method for Android 11+
    try {
      final storageResult = await platform.invokeMethod('checkStoragePermission');
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

  // Track scan metadata for results display
  int _lastScanItemsScanned = 0;
  Duration _lastScanDuration = Duration.zero;

  Future<void> _startScan({bool deepScan = false}) async {
    // Check if we have enough permissions
    if (_detectionCapability < 50) {
      _showPermissionWarning();
      return;
    }

    // Navigate to scanning screen
    final scanResult = await Navigator.push<ScanResult>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ScanningScreen(
          onScanWithProgress: (onProgress) =>
              DeviceScanService.instance.performScan(
            deepScan: deepScan,
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

    if (scanResult != null && scanResult.threats.isNotEmpty) {
      debugPrint('[OrbGuard] Received ${scanResult.threats.length} threats from scan');
      setState(() {
        _threats.clear();
        for (var t in scanResult.threats) {
          final converted = ThreatDetection.fromJson(t);
          debugPrint('[OrbGuard] Converted: ${converted.name} (${converted.severity})');
          _threats.add(converted);
        }
        _lastScanItemsScanned = scanResult.itemsScanned;
        _lastScanDuration = scanResult.scanDuration;
      });
      debugPrint('[OrbGuard] Showing results with ${_threats.length} threats');
      _showScanResults();
    } else if (scanResult != null) {
      // Scan completed with no threats
      debugPrint('[OrbGuard] Scan completed with no threats');
      setState(() {
        _lastScanItemsScanned = scanResult.itemsScanned;
        _lastScanDuration = scanResult.scanDuration;
      });
      _showNoThreatsDialog();
    }
  }


  void _showNoThreatsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1E33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withAlpha(51),
              ),
              child: const Center(
                child: DuotoneIcon(
                  AppIcons.shieldCheck,
                  size: 48,
                  color: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'All Clear!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No threats were detected on your device. Your device appears to be secure.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Great!'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showScanResults() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanResultsScreen(
          threats: _threats,
          itemsScanned: _lastScanItemsScanned,
          scanDuration: _lastScanDuration,
        ),
      ),
    );
  }

  void _showPermissionWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Limited Detection'),
        content: Text(
          'Current detection capability: ${_detectionCapability.round()}%\n\n'
          'For comprehensive scanning, please grant additional permissions.\n\n'
          'Would you like to set up permissions now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToPermissionSetup();
            },
            child: const Text('Setup Permissions'),
          ),
        ],
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
    final backgroundColor = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;
    final iconColor = isDark ? Colors.white.withAlpha(150) : Colors.black.withAlpha(100);

    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: _buildNavigationDrawer(),
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: Column(
              children: [
                // OrbX-style header
                _buildOrbXHeader(isDark, textColor, iconColor),
                // Body content
                Expanded(
                  child: _buildCurrentScreen(),
                ),
              ],
            ),
          ),
          // Bottom navigation bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: GlassBottomNavBar(
              currentIndex: _currentNavIndex,
              onTap: (index) {
                setState(() {
                  _currentNavIndex = index;
                });
              },
              items: const [
                NavItem(label: 'Home', iconPath: AppIcons.home),
                NavItem(label: 'Scan', iconPath: AppIcons.search),
                NavItem(label: 'Intel', iconPath: AppIcons.structure),
                NavItem(label: 'Settings', iconPath: AppIcons.settings),
              ],
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
          // Title container (pill-shaped)
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: GlassTheme.glassColor(isDark),
                border: Border.all(
                  color: GlassTheme.glassBorderColor(isDark),
                  width: GlassTheme.borderWidth,
                ),
                boxShadow: [GlassTheme.shadow(isDark)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: GlassTheme.blurFilter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
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
                            color: _detectionCapability >= 80
                                ? GlassTheme.successColor
                                : _detectionCapability >= 50
                                    ? GlassTheme.warningColor
                                    : GlassTheme.errorColor,
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
            ),
          ),
        ],
      ),
    );
  }

  /// Build current screen based on navigation index
  Widget _buildCurrentScreen() {
    switch (_currentNavIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return _buildScanContent();
      case 2:
        return _buildIntelContent();
      case 3:
        return _buildSettingsContent();
      default:
        return _buildHomeContent();
    }
  }

  /// Home tab content - Security Center
  Widget _buildHomeContent() {
    return const SecurityCenterScreen();
  }

  /// Scan tab content
  Widget _buildScanContent() {
    // On desktop platforms, show the DesktopSecurityScreen directly (embedded mode)
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
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
            child: const DuotoneIcon(
              AppIcons.search,
              size: 56,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tap to Start Scan',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withAlpha(200),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Detection capability: ${_detectionCapability.round()}%',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }

  /// Intel tab content - show Intelligence Core
  Widget _buildIntelContent() {
    // On desktop platforms, show the IntelligenceCoreScreen directly (embedded mode)
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return const IntelligenceCoreScreen(embedded: true);
    }

    // On mobile, show the button UI
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlassCircleButton(
            size: 100,
            tintColor: AppColors.accent,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => const IntelligenceCoreScreen(),
              ));
            },
            child: const DuotoneIcon(
              AppIcons.structure,
              size: 48,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Threat Intelligence',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withAlpha(200),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to browse IOCs & threat data',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }

  /// Settings tab content - show Settings
  Widget _buildSettingsContent() {
    // On desktop platforms, show the SettingsScreen directly (embedded mode)
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return const SettingsScreen(embedded: true);
    }

    // On mobile, show the button UI
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlassCircleButton(
            size: 100,
            tintColor: AppColors.accent,
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (context) => const SettingsScreen(),
              ));
            },
            child: const DuotoneIcon(
              AppIcons.settings,
              size: 48,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white.withAlpha(200),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure app preferences',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationDrawer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;
    final secondaryColor = isDark ? Colors.white.withAlpha(150) : AppColors.textSecondary;

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
              color: isDark ? Colors.black.withAlpha(200) : Colors.white.withAlpha(240),
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            border: Border.all(color: AppColors.accent.withAlpha(60), width: 1),
                          ),
                          child: const Center(
                            child: DuotoneIcon(AppIcons.shield, size: 28, color: AppColors.accent),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('OrbGuard', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                              const SizedBox(height: 4),
                              Text('Mobile Security Suite', style: TextStyle(color: secondaryColor, fontSize: 13)),
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
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const DashboardScreen(),
                    ));
                  },
                ),
                const GlassDivider(isDark: true),
                _buildDrawerSection('Protection'),
                _buildDrawerItem(
                  svgIcon: 'chat_dots',
                  title: 'SMS Protection',
                  subtitle: 'Phishing & smishing detection',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const SmsProtectionScreen(),
                    ));
                  },
                ),
                _buildDrawerItem(
                  svgIcon: 'link',
                  title: 'URL Protection',
                  subtitle: 'Malicious link scanner',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
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
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const QrScannerScreen(),
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
                    Navigator.push(context, MaterialPageRoute(
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
                    Navigator.push(context, MaterialPageRoute(
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
                    Navigator.push(context, MaterialPageRoute(
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
                    Navigator.push(context, MaterialPageRoute(
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
                    Navigator.push(context, MaterialPageRoute(
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
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const DeviceSecurityScreen(),
                    ));
                  },
                ),
                const GlassDivider(isDark: true),
                _buildDrawerSection('Intelligence'),
                _buildDrawerItem(
                  svgIcon: 'structure',
                  title: 'Intelligence Core',
                  subtitle: 'Threat intel browsing & IOC check',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const IntelligenceCoreScreen(),
                    ));
                  },
                ),
                _buildDrawerItem(
                  svgIcon: 'widget_4',
                  title: 'MITRE ATT&CK',
                  subtitle: 'Threat framework mapping',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
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
                    Navigator.push(context, MaterialPageRoute(
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
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const SupplyChainScreen(),
                    ));
                  },
                ),
                const GlassDivider(isDark: true),
                _buildDrawerSection('Identity & Privacy'),
                _buildDrawerItem(
                  svgIcon: 'user_id',
                  title: 'Identity Protection',
                  subtitle: 'Credit & identity monitoring',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const IdentityProtectionScreen(),
                    ));
                  },
                ),
                _buildDrawerItem(
                  svgIcon: 'share',
                  title: 'Social Media',
                  subtitle: 'Account security monitoring',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const SocialMediaScreen(),
                    ));
                  },
                ),
                const GlassDivider(isDark: true),
                _buildDrawerSection('Enterprise'),
                _buildDrawerItem(
                  svgIcon: 'crown',
                  title: 'Executive Protection',
                  subtitle: 'VIP & BEC fraud detection',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const ExecutiveProtectionScreen(),
                    ));
                  },
                ),
                _buildDrawerItem(
                  svgIcon: 'clipboard_text',
                  title: 'Enterprise Policy',
                  subtitle: 'MDM & compliance policies',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const EnterprisePolicyScreen(),
                    ));
                  },
                ),
                _buildDrawerItem(
                  svgIcon: 'widget_5',
                  title: 'Enterprise Overview',
                  subtitle: 'Organization security status',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const EnterpriseOverviewScreen(),
                    ));
                  },
                ),
                _buildDrawerItem(
                  svgIcon: 'server_square',
                  title: 'SIEM Integration',
                  subtitle: 'Splunk, ELK, ArcSight',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const SiemIntegrationScreen(),
                    ));
                  },
                ),
                _buildDrawerItem(
                  svgIcon: 'document_add',
                  title: 'Compliance Reports',
                  subtitle: 'SOC2, GDPR, HIPAA, PCI-DSS',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const ComplianceReportingScreen(),
                    ));
                  },
                ),
                _buildDrawerItem(
                  svgIcon: 'transfer_horizontal',
                  title: 'STIX/TAXII',
                  subtitle: 'Threat intelligence sharing',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) => const StixTaxiiScreen(),
                    ));
                  },
                ),
                const GlassDivider(isDark: true),
                _buildDrawerItem(
                  svgIcon: 'settings',
                  title: 'Settings',
                  subtitle: 'App configuration',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: isDark ? Colors.white.withAlpha(100) : Colors.black.withAlpha(80),
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
    final textColor = isDark ? Colors.white : AppColors.textPrimary;
    final secondaryColor = isDark ? Colors.white.withAlpha(130) : AppColors.textSecondary;

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
              color: isDark
                  ? Colors.white.withAlpha(8)
                  : Colors.black.withAlpha(5),
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
                      color: AppColors.accent,
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About OrbGuard'),
        content: const Text(
          'OrbGuard - Advanced Spyware Defense\n\n'
          'Detects and removes sophisticated threats including Pegasus using multiple access methods:\n\n'
          '• Root Access (if available)\n'
          '• Shell Access (Shizuku method integrated)\n'
          '• System Services (app_process)\n'
          '• Standard APIs\n\n'
          '✓ No external apps required\n'
          '✓ All scanning happens locally\n'
          '✓ No data sent to servers\n'
          '✓ Automatic privilege escalation\n'
          '✓ Cloud threat intelligence\n'
          '✓ Special permissions for enhanced detection\n\n'
          'Your privacy and security are our priority.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
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

