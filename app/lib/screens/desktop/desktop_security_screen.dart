/// Desktop-specific security features including persistence scanning,
/// code signing verification, and firewall management
library;

import 'dart:convert';
import 'dart:io';
import '../../utils/platform_info.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/desktop_security_provider.dart';
import '../../services/security/desktop_firewall_enforcer.dart';
import '../../services/security/desktop_scan_config.dart';
import '../../services/api/orbguard_api_client.dart';

class DesktopSecurityScreen extends StatefulWidget {
  /// When true, skips the outer page wrapper (for embedding in other screens)
  final bool embedded;

  const DesktopSecurityScreen({super.key, this.embedded = false});

  @override
  State<DesktopSecurityScreen> createState() => _DesktopSecurityScreenState();
}

class _DesktopSecurityScreenState extends State<DesktopSecurityScreen> {
  final OrbGuardApiClient _apiClient = OrbGuardApiClient.instance;
  bool _isLoading = false;
  bool _isScanning = false;
  String? _error;
  final List<PersistenceItem> _persistenceItems = [];
  final List<SignedApp> _signedApps = [];
  final List<FirewallRule> _firewallRules = [];
  List<Map<String, dynamic>> _networkConnections = [];
  Map<String, dynamic>? _browserScanResult;

  bool get _isDesktopPlatform =>
      PlatformInfo.isMacOS || PlatformInfo.isWindows || PlatformInfo.isLinux;

  String _getPlatformName() {
    if (PlatformInfo.isMacOS) return 'macOS';
    if (PlatformInfo.isWindows) return 'Windows';
    if (PlatformInfo.isLinux) return 'Linux';
    return 'Desktop';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        context.read<DesktopSecurityProvider>().init();
        // Auto-scan on startup when enabled (Desktop Scanner settings).
        final cfg = await DesktopScanConfig.load();
        if (cfg.autoScanOnStartup && mounted && !_isScanning) {
          _runScan();
        }
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Each section loads independently so one failing endpoint does not hide
    // data from the others; failures are surfaced instead of silently
    // replaced with empty placeholders.
    final errors = <String>[];

    // On desktop platforms, network connections, browser extensions, the
    // firewall state and code signing are collected/verified LOCALLY on this
    // device (the backend's desktop scanners run on the server host, not
    // here). The backend is only used for value-based lookups (VirusTotal)
    // and the server-side rule list.
    if (_isDesktopPlatform) {
      final provider = context.read<DesktopSecurityProvider>();
      // Each call manages its own state and surfaces its own errors.
      await Future.wait([
        provider.refreshHostFirewallStatus(),
        provider.refreshFirewallEnforcementStatus(),
        provider.loadHostNetworkConnections(),
        provider.loadHostBrowserExtensions(),
      ]);
    }

    List<PersistenceItem> persistenceItems = [];
    try {
      final persistenceData = await _apiClient.getPersistenceItems();
      persistenceItems =
          persistenceData.map((json) => PersistenceItem.fromJson(json)).toList();
    } catch (e) {
      errors.add('persistence: $e');
    }

    // Backend code-signing cache reflects the SERVER host, so it is only
    // meaningful off-desktop; desktop uses local verification instead.
    List<SignedApp> signedApps = [];
    if (!_isDesktopPlatform) {
      try {
        final signedAppsData = await _apiClient.getSignedApps();
        signedApps =
            signedAppsData.map((json) => SignedApp.fromJson(json)).toList();
      } catch (e) {
        errors.add('signed apps: $e');
      }
    }

    List<FirewallRule> firewallRules = [];
    try {
      final firewallData = await _apiClient.getDesktopFirewallRules();
      firewallRules = firewallData.map((json) => FirewallRule.fromJson(json)).toList();
    } catch (e) {
      errors.add('firewall: $e');
    }

    List<Map<String, dynamic>> networkData = [];
    Map<String, dynamic> browserData = {};
    if (!_isDesktopPlatform) {
      try {
        networkData = await _apiClient.getNetworkConnections();
      } catch (e) {
        errors.add('network: $e');
      }
      try {
        browserData = await _apiClient.scanBrowserExtensions();
      } catch (e) {
        errors.add('browser: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _persistenceItems
        ..clear()
        ..addAll(persistenceItems);
      _signedApps
        ..clear()
        ..addAll(signedApps);
      _firewallRules
        ..clear()
        ..addAll(firewallRules);
      _networkConnections = networkData;
      _browserScanResult = browserData.isNotEmpty ? browserData : null;
      _error = errors.isEmpty
          ? null
          : 'Failed to load desktop security data — ${errors.join('; ')}';
      _isLoading = false;
    });
  }

  /// Content padding for the tab list views. In the embedded tab path the
  /// shell's floating bottom nav overlays the body, so the primary scrollable
  /// needs extra bottom clearance for content to be fully visible at rest.
  EdgeInsets get _tabContentPadding => EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 +
            (widget.embedded
                ? GlassTheme.bottomNavClearance +
                    MediaQuery.of(context).padding.bottom
                : 0),
      );

  @override
  Widget build(BuildContext context) {
    final page = GlassTabPage(
      title: 'Desktop Security',
      hasSearch: true,
      searchHint: 'Search devices...',
      embedded: widget.embedded,
      headerContent: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: DuotoneIcon('download_minimalistic', size: 22, color: context.colors.onSurface),
              onPressed: _exportResults,
              tooltip: 'Export Results',
            ),
            IconButton(
              icon: DuotoneIcon('refresh', size: 22, color: context.colors.onSurface),
              onPressed: _isScanning ? null : _runScan,
              tooltip: 'Refresh',
            ),
          ],
        ),
      ),
      tabs: [
        GlassTab(
          label: 'Persistence',
          iconPath: 'laptop',
          content: _buildPersistenceTab(),
        ),
        GlassTab(
          label: 'Code Signing',
          iconPath: 'shield',
          content: _buildCodeSigningTab(),
        ),
        GlassTab(
          label: 'Firewall',
          iconPath: 'link_round',
          content: _buildFirewallTab(),
        ),
        GlassTab(
          label: 'Network',
          iconPath: 'wi_fi_router',
          content: _buildNetworkTab(),
        ),
        GlassTab(
          label: 'Browser',
          iconPath: 'globe',
          content: _buildBrowserTab(),
        ),
        GlassTab(
          label: 'Quarantine',
          iconPath: 'danger_circle',
          content: _buildQuarantineTab(),
        ),
      ],
    );
    if (!widget.embedded) return page;
    // Embedded tab path: the shell's transparent floating header overlays the
    // top of the body, so push the fixed internal tab selector below it. The
    // bottom clearance is applied inside each tab's scrollable padding.
    return Padding(
      padding: const EdgeInsets.only(top: GlassTheme.headerClearance),
      child: page,
    );
  }

  Widget _buildPersistenceTab() {
    final suspicious = _persistenceItems.where((i) => i.isSuspicious).length;
    final safe = _persistenceItems.length - suspicious;

    return ListView(
      padding: _tabContentPadding,
      children: [
        // Scan button
        _isDesktopPlatform
            ? Consumer<DesktopSecurityProvider>(
                builder: (context, provider, child) {
                  final scanPhase = provider.isScanning ? provider.currentPhase : '';
                  final progress = provider.scanProgress;

                  return GlassCard(
                    margin: EdgeInsets.zero,
                    onTap: (_isScanning || provider.isScanning) ? null : _runScan,
                    tintColor: (_isScanning || provider.isScanning) ? GlassTheme.primaryAccent : null,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GlassSvgIconBox(
                              icon: 'radar',
                              color: GlassTheme.primaryAccent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_getPlatformName()} Persistence Scanner',
                                    style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    provider.isScanning
                                        ? scanPhase
                                        : 'Native scan for persistence mechanisms',
                                    style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            if (_isScanning || provider.isScanning)
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: AppColors.accentInk,
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              DuotoneIcon('play', color: AppColors.accentInk),
                          ],
                        ),
                        if (provider.isScanning) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: context.colors.onSurface.withValues(alpha: 0.06),
                              color: AppColors.accentInk,
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              )
            : GlassCard(
                margin: EdgeInsets.zero,
                onTap: _isScanning ? null : _runScan,
                tintColor: _isScanning ? GlassTheme.primaryAccent : null,
                child: Row(
                  children: [
                    GlassSvgIconBox(
                      icon: 'radar',
                      color: GlassTheme.primaryAccent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Persistence Scanner',
                            style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _isScanning ? 'Scanning...' : 'Scan for persistence mechanisms',
                            style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (_isScanning)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: AppColors.accentInk,
                          strokeWidth: 2,
                        ),
                      )
                    else
                      DuotoneIcon('play', color: AppColors.accentInk),
                  ],
                ),
              ),

        // Stats
        const SizedBox(height: 24),
        Row(
          children: [
            _buildStatCard('Suspicious', suspicious.toString(), AppColors.errorInk),
            const SizedBox(width: 12),
            _buildStatCard('Safe', safe.toString(), AppColors.accentInk),
          ],
        ),

        // Error display
        if (_error != null) ...[
          const SizedBox(height: 24),
          GlassCard(
            margin: EdgeInsets.zero,
            tintColor: GlassTheme.errorColor,
            child: Row(
              children: [
                DuotoneIcon('danger_circle', color: AppColors.errorInk, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Error Loading Data',
                        style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _error!,
                        style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: DuotoneIcon('refresh', color: context.colors.onSurface, size: 20),
                  onPressed: _loadData,
                  tooltip: 'Retry',
                ),
              ],
            ),
          ),
        ],

        // Persistence items
        const SizedBox(height: 24),
        const GlassSectionHeader(title: 'Startup Items & Services'),
        if (_persistenceItems.isEmpty && !_isLoading && !_isScanning)
          _buildEmptyState(
            'No Persistence Items',
            'Run a scan to detect startup items and services.',
            'radar',
          )
        else
          ..._persistenceItems.map((item) => _buildPersistenceCard(item)),

        // Categories info
        const SizedBox(height: 24),
        const GlassSectionHeader(title: 'Scan Coverage'),
        ..._buildPlatformCoverage(),
      ],
    );
  }

  List<Widget> _buildPlatformCoverage() {
    if (PlatformInfo.isMacOS) {
      return [
        _buildCoverageRow('play_circle', 'Launch Agents & Daemons', true),
        _buildCoverageRow('user', 'Login Items', true),
        _buildCoverageRow('clock_circle', 'Cron Jobs & Periodic Tasks', true),
        _buildCoverageRow('widget', 'Browser Extensions', true),
        _buildCoverageRow('cpu', 'Kernel Extensions', true),
        _buildCoverageRow('server', 'Auth & Directory Plugins', true),
        _buildCoverageRow('code', 'Scripting Additions', true),
        _buildCoverageRow('danger_circle', 'Event Monitor Rules', true),
        _buildCoverageRow('folder', 'Startup Items', true),
        _buildCoverageRow('settings', 'Spotlight Importers', true),
      ];
    } else if (PlatformInfo.isWindows) {
      return [
        _buildCoverageRow('key', 'Registry Run Keys', true),
        _buildCoverageRow('clock_circle', 'Scheduled Tasks', true),
        _buildCoverageRow('settings', 'Windows Services', true),
        _buildCoverageRow('folder', 'Startup Folders', true),
        _buildCoverageRow('server', 'WMI Subscriptions', true),
        _buildCoverageRow('widget', 'Browser Extensions', true),
        _buildCoverageRow('code', 'COM Objects & DLL Hijacks', true),
        _buildCoverageRow('danger_circle', 'IFEO & Winlogon', true),
        _buildCoverageRow('cpu', 'AppInit DLLs & LSA Packages', true),
        _buildCoverageRow('link_round', 'Netsh Helpers & Print Monitors', true),
      ];
    } else if (PlatformInfo.isLinux) {
      return [
        _buildCoverageRow('settings', 'Systemd Services & Timers', true),
        _buildCoverageRow('play_circle', 'Init Scripts & RC Local', true),
        _buildCoverageRow('clock_circle', 'Cron Jobs (System & User)', true),
        _buildCoverageRow('code', 'Shell RC Files & Profile.d', true),
        _buildCoverageRow('cpu', 'Kernel Modules', true),
        _buildCoverageRow('danger_circle', 'LD_PRELOAD Hijacking', true),
        _buildCoverageRow('key', 'SSH Keys & Sudoers.d', true),
        _buildCoverageRow('folder', 'XDG Autostart & Desktop Entries', true),
        _buildCoverageRow('server', 'D-Bus Services & Polkit Rules', true),
        _buildCoverageRow('user', 'MOTD Scripts & Udev Rules', true),
      ];
    }
    return [
      _buildCoverageRow('play_circle', 'Launch Agents', true),
      _buildCoverageRow('settings', 'Launch Daemons', true),
      _buildCoverageRow('user', 'Login Items', true),
      _buildCoverageRow('clock_circle', 'Scheduled Tasks', true),
      _buildCoverageRow('widget', 'Browser Extensions', true),
      _buildCoverageRow('cpu', 'Kernel Extensions', true),
    ];
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: BrandText.heading(size: 28, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildPersistenceCard(PersistenceItem item) {
    return GlassCard(
      onTap: () => _showPersistenceDetails(context, item),
      tintColor: item.isSuspicious ? GlassTheme.errorColor : null,
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: _getPersistenceIcon(item.type),
            color: item.isSuspicious ? GlassTheme.errorColor : GlassTheme.successColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold),
                ),
                Text(
                  item.type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  item.path,
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GlassBadge(
            text: item.isSuspicious ? 'Suspicious' : 'Safe',
            color: item.isSuspicious ? GlassTheme.errorColor : GlassTheme.successColor,
            fontSize: 10,
          ),
        ],
      ),
    );
  }

  Widget _buildCoverageRow(String icon, String title, bool enabled) {
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(icon: icon, color: enabled ? GlassTheme.primaryAccent : context.colors.onSurfaceVariant, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500)),
          ),
          DuotoneIcon(
            enabled ? 'check_circle' : 'close_circle',
            color: enabled ? AppColors.accentInk : context.colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildCodeSigningTab() {
    if (_isDesktopPlatform) {
      // Local verification: the backend's codesign verifier runs on the
      // SERVER host and cannot inspect files on this device, so signatures
      // are verified here with codesign / Get-AuthenticodeSignature. The
      // backend is used only for VirusTotal hash lookups.
      return Consumer<DesktopSecurityProvider>(
        builder: (context, provider, _) {
          final apps = provider.localSignedApps
              .map((json) => SignedApp.fromJson(json))
              .toList();
          final unsigned = apps.where((a) => !a.isSigned).length;
          final invalid = apps.where((a) => a.isSigned && !a.isValid).length;
          final valid = apps.where((a) => a.isSigned && a.isValid).length;
          final unavailable = provider.codeSigningUnavailableReason;

          return ListView(
            padding: _tabContentPadding,
            children: [
              GlassCard(
                margin: EdgeInsets.zero,
                onTap: provider.isVerifyingCodeSigning
                    ? null
                    : () => provider.verifyLocalCodeSigning(),
                child: Row(
                  children: [
                    GlassSvgIconBox(
                        icon: 'verified_check', color: GlassTheme.primaryAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verify Code Signatures Locally',
                            style: TextStyle(
                                color: context.colors.onSurface,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            provider.isVerifyingCodeSigning
                                ? 'Verifying signatures on this device…'
                                : PlatformInfo.isMacOS
                                    ? 'codesign verification of installed apps and persistence executables'
                                    : PlatformInfo.isWindows
                                        ? 'Authenticode verification of persistence executables'
                                        : 'Verification of persistence executables',
                            style: TextStyle(
                                color: context.colors.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (provider.isVerifyingCodeSigning)
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: AppColors.accentInk, strokeWidth: 2),
                      )
                    else
                      DuotoneIcon('play', color: AppColors.accentInk),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (unavailable != null)
                GlassCard(
                  tintColor: GlassTheme.warningColor,
                  child: Row(
                    children: [
                      DuotoneIcon('danger_circle',
                          color: AppColors.secondaryInk, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          unavailable,
                          style: TextStyle(
                              color: context.colors.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Row(
                  children: [
                    _buildStatCard('Valid', valid.toString(), AppColors.accentInk),
                    const SizedBox(width: 12),
                    _buildStatCard('Invalid', invalid.toString(), AppColors.errorInk),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatCard('Unsigned', unsigned.toString(), AppColors.amberInk),
                    const SizedBox(width: 12),
                    _buildStatCard('Verified', apps.length.toString(), AppColors.secondaryInk),
                  ],
                ),
                const SizedBox(height: 24),
                const GlassSectionHeader(title: 'Verified on This Device'),
                if (apps.isEmpty && !provider.isVerifyingCodeSigning)
                  _buildEmptyState(
                    'Nothing Verified Yet',
                    'Run the local verification above. Tip: run a persistence '
                        'scan first so its executables are included.',
                    'verified_check',
                  )
                else
                  ...apps.map((app) => _buildSignedAppCard(app)),
              ],
            ],
          );
        },
      );
    }

    final unsigned = _signedApps.where((a) => !a.isSigned).length;
    final invalid = _signedApps.where((a) => a.isSigned && !a.isValid).length;
    final valid = _signedApps.where((a) => a.isSigned && a.isValid).length;

    return ListView(
      padding: _tabContentPadding,
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Valid', valid.toString(), AppColors.accentInk),
            const SizedBox(width: 12),
            _buildStatCard('Invalid', invalid.toString(), AppColors.errorInk),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatCard('Unsigned', unsigned.toString(), AppColors.amberInk),
            const SizedBox(width: 12),
            _buildStatCard('Total Apps', _signedApps.length.toString(), AppColors.secondaryInk),
          ],
        ),

        // Apps list
        const SizedBox(height: 24),
        const GlassSectionHeader(title: 'Applications (verified on server host)'),
        if (_signedApps.isEmpty && !_isLoading)
          _buildEmptyState(
            'No Apps Detected',
            'Code signing verification will appear here after scanning.',
            'verified_check',
          )
        else
          ..._signedApps.map((app) => _buildSignedAppCard(app)),
      ],
    );
  }

  Widget _buildSignedAppCard(SignedApp app) {
    Color statusColor;
    String statusText;
    String statusIcon;

    if (!app.isSigned) {
      statusColor = AppColors.amberInk;
      statusText = 'Unsigned';
      statusIcon = 'danger_triangle';
    } else if (!app.isValid) {
      statusColor = AppColors.errorInk;
      statusText = 'Invalid';
      statusIcon = 'danger_circle';
    } else {
      statusColor = AppColors.accentInk;
      statusText = 'Valid';
      statusIcon = 'verified_check';
    }

    return GlassCard(
      onTap: () => _showSigningDetails(context, app),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.colors.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
            ),
            child: Center(
              child: DuotoneIcon(
                _getAppIcon(app.name),
                color: context.colors.onSurface,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold),
                ),
                if (app.isSigned && app.developer.isNotEmpty)
                  Text(
                    app.developer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11),
                  ),
                Text(
                  app.bundleId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 10, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DuotoneIcon(statusIcon, color: statusColor, size: 20),
              const SizedBox(height: 4),
              Text(statusText, style: TextStyle(color: statusColor, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFirewallTab() {
    final enabled = _firewallRules.where((r) => r.isEnabled).length;
    final blocked =
        _firewallRules.where((r) => r.action.toLowerCase() == 'block').length;

    return ListView(
      padding: _tabContentPadding,
      children: [
        // REAL host firewall status, read from OS tooling
        // (socketfilterfw / netsh advfirewall / ufw+firewalld).
        if (_isDesktopPlatform)
          Consumer<DesktopSecurityProvider>(
            builder: (context, provider, _) =>
                _buildHostFirewallCard(provider),
          )
        else
          GlassCard(
            margin: EdgeInsets.zero,
            tintColor: GlassTheme.warningColor,
            child: Row(
              children: [
                GlassSvgIconBox(icon: 'shield', color: GlassTheme.warningColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Host Firewall',
                        style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'OS firewall control is only available on desktop platforms',
                        style: TextStyle(color: AppColors.secondaryInk, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Stats
        const SizedBox(height: 24),
        Row(
          children: [
            _buildStatCard('Server Rules', enabled.toString(), AppColors.secondaryInk),
            const SizedBox(width: 12),
            _buildStatCard('Blocking', blocked.toString(), AppColors.errorInk),
          ],
        ),

        // Quick actions — each runs a real OS command and reports the real
        // outcome (including admin-prompt cancellation).
        if (_isDesktopPlatform) ...[
          const SizedBox(height: 24),
          const GlassSectionHeader(title: 'Quick Actions (local OS firewall)'),
          _buildQuickAction(
            'forbidden',
            'Block All Incoming',
            PlatformInfo.isLinux
                ? 'Not supported by ufw/firewalld (incoming is denied by default)'
                : 'Block all incoming connections at the OS firewall',
            () => _runQuickFirewallAction('block_all'),
          ),
          _buildQuickAction(
            'eye_closed',
            'Stealth Mode',
            PlatformInfo.isMacOS
                ? 'Do not respond to probes (socketfilterfw stealth mode)'
                : 'No separate stealth toggle on this OS — enabled firewalls already drop probes',
            () => _runQuickFirewallAction('stealth'),
          ),
          _buildQuickAction(
            'settings',
            'Open System Firewall Settings',
            'Open the OS firewall configuration UI',
            () => _runQuickFirewallAction('open_settings'),
          ),
        ],

        // Rules — these live on the OrbGuard Lab backend host, not on this
        // device, and are labeled accordingly.
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: GlassSectionHeader(title: 'Server-Side Rules (OrbGuard Lab)'),
            ),
            TextButton.icon(
              onPressed: () => _showAddRuleDialog(context),
              icon: const DuotoneIcon('add_circle', size: 18),
              label: const Text('Add Rule'),
              style: TextButton.styleFrom(foregroundColor: AppColors.accentInk),
            ),
          ],
        ),
        if (_firewallRules.isEmpty && !_isLoading)
          _buildEmptyState(
            'No Server-Side Rules',
            'Rules added here are enforced on the OrbGuard Lab host, not on this device.',
            'shield_network',
          )
        else
          ..._firewallRules.map((rule) => _buildFirewallRuleCard(rule)),
      ],
    );
  }

  Widget _buildHostFirewallCard(DesktopSecurityProvider provider) {
    final status = provider.hostFirewallStatus;

    Color color;
    Color ink;
    String stateText;
    String icon;
    bool? switchValue;
    if (status == null) {
      color = context.colors.onSurfaceVariant;
      ink = context.colors.onSurfaceVariant;
      stateText = 'Reading firewall state…';
      icon = 'shield';
      switchValue = null;
    } else {
      switch (status.state) {
        case HostFirewallState.enabled:
          color = GlassTheme.successColor;
          ink = AppColors.accentInk;
          stateText = status.detail;
          icon = 'shield_check';
          switchValue = true;
          break;
        case HostFirewallState.disabled:
          color = GlassTheme.errorColor;
          ink = AppColors.errorInk;
          stateText = status.detail;
          icon = 'shield';
          switchValue = false;
          break;
        case HostFirewallState.unknown:
          color = GlassTheme.warningColor;
          ink = AppColors.secondaryInk;
          stateText = status.detail;
          icon = 'danger_triangle';
          switchValue = null;
          break;
        case HostFirewallState.unavailable:
          color = context.colors.onSurfaceVariant;
          ink = context.colors.onSurfaceVariant;
          stateText = status.detail;
          icon = 'danger_circle';
          switchValue = null;
          break;
      }
    }

    return GlassCard(
      margin: EdgeInsets.zero,
      tintColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(icon: icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_getPlatformName()} Firewall',
                      style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      stateText,
                      style: TextStyle(color: ink, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (switchValue != null)
                Switch(
                  value: switchValue,
                  onChanged: (v) => _toggleHostFirewall(v),
                )
              else
                IconButton(
                  icon: DuotoneIcon('refresh', size: 20, color: context.colors.onSurface),
                  onPressed: () => provider.refreshHostFirewallStatus(),
                  tooltip: 'Re-read firewall state',
                ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(
              'Source: ${status.source}',
              style: TextStyle(
                color: context.colors.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
          // Threat-intel malicious-IP enforcement — a distinct control that
          // installs real pf/iptables/netsh DROP rules for the block list.
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: context.colors.onSurfaceVariant.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 14),
          _buildFirewallEnforcementSection(provider),
        ],
      ),
    );
  }

  /// Enforcement sub-control inside the host firewall card: honestly reflects
  /// whether OrbGuard is ACTUALLY blocking the threat-intel malicious IPs at
  /// the OS packet-filter level, including an "Administrator privileges
  /// required" state when elevation is needed or was denied.
  Widget _buildFirewallEnforcementSection(DesktopSecurityProvider provider) {
    final status = provider.firewallEnforcementStatus;
    final mutating = provider.isMutatingFirewallEnforcement;

    Color color;
    Color ink;
    String stateText;
    String icon;
    bool switchValue = false;
    bool showSwitch = true;

    if (status == null) {
      color = context.colors.onSurfaceVariant;
      ink = context.colors.onSurfaceVariant;
      stateText = 'Checking malicious-IP enforcement…';
      icon = 'shield';
    } else {
      switch (status.state) {
        case FirewallEnforcementState.enforcing:
          color = GlassTheme.successColor;
          ink = AppColors.accentInk;
          stateText = status.reason;
          icon = 'shield_check';
          switchValue = true;
          break;
        case FirewallEnforcementState.notEnforcing:
          color = status.errored
              ? GlassTheme.errorColor
              : context.colors.onSurfaceVariant;
          ink = status.errored ? AppColors.errorInk : context.colors.onSurfaceVariant;
          stateText = status.reason;
          icon = status.errored ? 'danger_triangle' : 'shield';
          break;
        case FirewallEnforcementState.needsElevation:
          color = GlassTheme.warningColor;
          ink = AppColors.secondaryInk;
          stateText = 'Administrator privileges required. ${status.reason}';
          icon = 'danger_triangle';
          break;
        case FirewallEnforcementState.unavailable:
          color = context.colors.onSurfaceVariant;
          ink = context.colors.onSurfaceVariant;
          stateText = status.reason;
          icon = 'danger_circle';
          showSwitch = false;
          break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GlassSvgIconBox(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Block Malicious IPs (threat intel)',
                    style: TextStyle(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    stateText,
                    style: TextStyle(color: ink, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (mutating)
              SizedBox(
                width: 40,
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accentInk),
                ),
              )
            else if (showSwitch)
              Switch(
                value: switchValue,
                onChanged: (v) => _toggleFirewallEnforcement(v),
              ),
          ],
        ),
        Text(
          'OS packet-filter DROP rules for the critical malicious IPs in your '
          'threat feed. Blocks IP addresses, not domains.',
          style: TextStyle(
            color: context.colors.onSurfaceVariant.withValues(alpha: 0.7),
            fontSize: 10,
          ),
        ),
        if (status != null && status.blockedIpCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Source: ${status.source}',
            style: TextStyle(
              color: context.colors.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }

  /// Enable/disable REAL OS firewall enforcement of the malicious-IP block
  /// list. Shows an honest confirmation (admin will be requested) and reports
  /// the true outcome, including elevation cancellation.
  Future<void> _toggleFirewallEnforcement(bool enable) async {
    final provider = context.read<DesktopSecurityProvider>();
    final scaffold = ScaffoldMessenger.of(context);

    if (enable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: GlassTheme.glassColor(context.isDark),
          title: Text('Block Malicious IPs',
              style: TextStyle(color: context.colors.onSurface)),
          content: Text(
            'OrbGuard will install OS firewall rules that drop all traffic to '
            'and from the critical malicious IP addresses in your threat '
            'intelligence feed. This modifies the system firewall and requires '
            'administrator privileges — you will be asked to authorize it.',
            style: TextStyle(color: context.colors.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
              ),
              child: const Text('Enable Blocking'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final status = enable
        ? await provider.enableFirewallEnforcement()
        : await provider.disableFirewallEnforcement();
    if (!mounted) return;

    final isSuccess = status.state == FirewallEnforcementState.enforcing ||
        (!enable &&
            status.state == FirewallEnforcementState.notEnforcing &&
            !status.errored);
    final isWarning =
        status.state == FirewallEnforcementState.needsElevation ||
            status.state == FirewallEnforcementState.unavailable;
    scaffold.showSnackBar(SnackBar(
      content: Text(status.reason),
      backgroundColor: isSuccess
          ? GlassTheme.successColor
          : isWarning
              ? GlassTheme.warningColor
              : GlassTheme.errorColor,
      duration: const Duration(seconds: 6),
    ));
  }

  Future<void> _toggleHostFirewall(bool enable) async {
    final provider = context.read<DesktopSecurityProvider>();
    final scaffold = ScaffoldMessenger.of(context);
    final result = await provider.setHostFirewallEnabled(enable);
    if (!mounted) return;
    scaffold.showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Firewall ${enable ? 'enabled' : 'disabled'}'
              : result.message,
        ),
        backgroundColor: result.success
            ? GlassTheme.successColor
            : result.cancelled
                ? GlassTheme.warningColor
                : GlassTheme.errorColor,
      ),
    );
  }

  Widget _buildQuickAction(
      String icon, String title, String subtitle, VoidCallback onTap) {
    return GlassCard(
      onTap: onTap,
      child: Row(
        children: [
          GlassSvgIconBox(icon: icon, color: GlassTheme.primaryAccent, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500)),
                Text(subtitle, style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
          DuotoneIcon('alt_arrow_right',
              color: context.colors.onSurfaceVariant.withValues(alpha: 0.7)),
        ],
      ),
    );
  }

  /// Runs a quick action against the REAL OS firewall and reports the real
  /// command outcome (success, admin-prompt cancellation, permission denial
  /// or honest "not supported on this OS").
  Future<void> _runQuickFirewallAction(String kind) async {
    final provider = context.read<DesktopSecurityProvider>();
    final scaffold = ScaffoldMessenger.of(context);

    if (kind == 'open_settings') {
      final result = await provider.openSystemFirewallSettings();
      if (!mounted) return;
      scaffold.showSnackBar(SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? GlassTheme.successColor : GlassTheme.errorColor,
      ));
      return;
    }

    final isBlockAll = kind == 'block_all';
    final title = isBlockAll ? 'Block All Incoming' : 'Stealth Mode';
    final description = isBlockAll
        ? 'This changes the OS firewall policy to block all incoming '
            'connections. You may be asked for administrator credentials.'
        : 'This makes the device ignore unsolicited network probes. '
            'You may be asked for administrator credentials.';

    final enable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.glassColor(context.isDark),
        title: Text(title, style: TextStyle(color: context.colors.onSurface)),
        content: Text(
          description,
          style: TextStyle(color: context.colors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Disable'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
            ),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (enable == null || !mounted) return;

    final result = isBlockAll
        ? await provider.setBlockAllIncoming(enable)
        : await provider.setStealthMode(enable);
    if (!mounted) return;
    scaffold.showSnackBar(SnackBar(
      content: Text(
        result.success
            ? '$title ${enable ? 'enabled' : 'disabled'}'
            : result.message,
      ),
      backgroundColor: result.success
          ? GlassTheme.successColor
          : (result.cancelled || result.unsupported)
              ? GlassTheme.warningColor
              : GlassTheme.errorColor,
      duration: const Duration(seconds: 5),
    ));
  }

  Widget _buildFirewallRuleCard(FirewallRule rule) {
    final isBlock = rule.action.toLowerCase() == 'block';

    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(
            icon: isBlock ? 'forbidden' : 'check_circle',
            color: isBlock ? GlassTheme.errorColor : GlassTheme.successColor,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rule.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    GlassBadge(
                      text: rule.action,
                      color: isBlock ? GlassTheme.errorColor : GlassTheme.successColor,
                      fontSize: 10,
                    ),
                    const SizedBox(width: 8),
                    GlassBadge(
                      text: rule.direction,
                      color: GlassTheme.primaryAccent,
                      fontSize: 10,
                    ),
                    const SizedBox(width: 8),
                    GlassBadge(
                      text: rule.protocol,
                      color: context.colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                    if (!rule.isEnabled) ...[
                      const SizedBox(width: 8),
                      GlassBadge(
                        text: 'Disabled',
                        color: context.colors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${rule.destPort != null ? "Port ${rule.destPort}" : "All ports"} • ${rule.destAddress ?? "Any address"} • enforced on server host',
                  style: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            icon: DuotoneIcon('trash_bin_minimalistic',
                color: AppColors.errorInk, size: 20),
            onPressed: () => _deleteServerFirewallRule(rule),
            tooltip: 'Delete rule',
          ),
        ],
      ),
    );
  }

  Future<void> _deleteServerFirewallRule(FirewallRule rule) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _apiClient.deleteFirewallRule(rule.id);
      if (!mounted) return;
      setState(() => _firewallRules.remove(rule));
      scaffold.showSnackBar(SnackBar(
        content: Text('Rule "${rule.name}" deleted from the server'),
        backgroundColor: GlassTheme.successColor,
      ));
    } catch (e) {
      if (!mounted) return;
      scaffold.showSnackBar(SnackBar(
        content: Text('Failed to delete rule: $e'),
        backgroundColor: GlassTheme.errorColor,
      ));
    }
  }

  Widget _buildNetworkTab() {
    if (_isDesktopPlatform) {
      // Client-side collection: the backend's network monitor observes the
      // SERVER host, so this device's connections are gathered locally
      // (lsof / ss / netstat) and only enriched via backend VT lookups.
      return Consumer<DesktopSecurityProvider>(
        builder: (context, provider, _) => _buildHostNetworkList(provider),
      );
    }

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accentInk));
    }

    return ListView(
      padding: _tabContentPadding,
      children: [
        // Summary card
        GlassCard(
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              const GlassDuotoneIconBox(icon: 'wi_fi_router', color: GlassTheme.primaryAccent, size: 48, iconSize: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_networkConnections.length} Active Connections',
                      style: BrandText.title(size: 18),
                    ),
                    Text(
                      'Observed on the OrbGuard Lab server host (not this device)',
                      style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: DuotoneIcon('refresh', size: 20, color: context.colors.onSurface),
                onPressed: () async {
                  final data = await _apiClient.getNetworkConnections().catchError((_) => <Map<String, dynamic>>[]);
                  setState(() => _networkConnections = data);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Connection list
        if (_networkConnections.isEmpty)
          GlassCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No active connections detected', style: TextStyle(color: context.colors.onSurfaceVariant)),
              ),
            ),
          )
        else
          ..._networkConnections.map((conn) {
            // Live NetworkConnection JSON (orbguard-lab
            // models/desktop_security.go): process_name, remote_address,
            // remote_port, protocol, state, is_known_bad, is_cnc,
            // threat_tags, ...
            final process = conn['process_name'] as String? ?? 'Unknown';
            final remoteIp = conn['remote_address'] as String? ?? '';
            final remotePortNum = (conn['remote_port'] as num?)?.toInt() ?? 0;
            final remotePort = remotePortNum > 0 ? remotePortNum.toString() : '';
            final protocol = conn['protocol'] as String? ?? 'tcp';
            final state = conn['state'] as String? ?? '';
            final isSuspicious = (conn['is_known_bad'] as bool? ?? false) ||
                (conn['is_cnc'] as bool? ?? false);

            return GlassCard(
              tintColor: isSuspicious ? GlassTheme.errorColor : null,
              child: Row(
                children: [
                  GlassDuotoneIconBox(
                    icon: isSuspicious ? 'danger_triangle' : 'link_round',
                    color: isSuspicious ? GlassTheme.errorColor : GlassTheme.successColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(process, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500)),
                        Text(
                          '$remoteIp${remotePort.isNotEmpty ? ':$remotePort' : ''} ($protocol)',
                          style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (state.isNotEmpty)
                    GlassBadge(
                      text: state,
                      color: state == 'ESTABLISHED' ? GlassTheme.successColor : context.colors.onSurfaceVariant,
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  /// Network list collected on THIS device by the platform scanner service.
  Widget _buildHostNetworkList(DesktopSecurityProvider provider) {
    final connections = provider.hostNetworkConnections;
    final errors = provider.hostNetworkErrors;
    final collecting = provider.isCollectingNetwork;

    return ListView(
      padding: _tabContentPadding,
      children: [
        GlassCard(
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              const GlassDuotoneIconBox(
                  icon: 'wi_fi_router',
                  color: GlassTheme.primaryAccent,
                  size: 48,
                  iconSize: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collecting
                          ? 'Collecting…'
                          : '${connections.length} Connections on This Device',
                      style: BrandText.title(size: 18),
                    ),
                    Text(
                      provider.hostNetworkSource.isEmpty
                          ? 'Tap refresh to collect network connections'
                          : 'Source: ${provider.hostNetworkSource}',
                      style: TextStyle(
                          color: context.colors.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (collecting)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: AppColors.accentInk, strokeWidth: 2),
                )
              else
                IconButton(
                  icon: DuotoneIcon('refresh', size: 20, color: context.colors.onSurface),
                  onPressed: () => provider.loadHostNetworkConnections(),
                ),
            ],
          ),
        ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          GlassCard(
            margin: EdgeInsets.zero,
            tintColor: GlassTheme.warningColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collection Notes',
                    style: TextStyle(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...errors.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• $e',
                          style: TextStyle(
                              color: context.colors.onSurfaceVariant,
                              fontSize: 11)),
                    )),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (connections.isEmpty && !collecting)
          GlassCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  errors.isEmpty
                      ? 'No connections collected yet — tap refresh'
                      : 'Collection failed — see notes above',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          ...connections.map(_buildConnectionCard),
      ],
    );
  }

  Widget _buildConnectionCard(Map<String, dynamic> conn) {
    final process = conn['process_name'] as String? ?? 'Unknown process';
    final remoteIp = conn['remote_address'] as String? ?? '';
    final remotePortNum = (conn['remote_port'] as num?)?.toInt() ?? 0;
    final remotePort = remotePortNum > 0 ? remotePortNum.toString() : '';
    final protocol = conn['protocol'] as String? ?? 'tcp';
    final state = conn['state'] as String? ?? '';
    final isSuspicious = (conn['is_known_bad'] as bool? ?? false) ||
        (conn['is_cnc'] as bool? ?? false);
    final tags = (conn['threat_tags'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final localPort = (conn['local_port'] as num?)?.toInt() ?? 0;

    return GlassCard(
      tintColor: isSuspicious ? GlassTheme.errorColor : null,
      child: Row(
        children: [
          GlassDuotoneIconBox(
            icon: isSuspicious ? 'danger_triangle' : 'link_round',
            color: isSuspicious ? GlassTheme.errorColor : GlassTheme.successColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(process,
                    style: TextStyle(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w500)),
                Text(
                  remoteIp.isEmpty
                      ? 'local port $localPort ($protocol)'
                      : '$remoteIp${remotePort.isNotEmpty ? ':$remotePort' : ''} ($protocol)',
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
                ),
                if (tags.isNotEmpty)
                  Text(
                    tags.join(', '),
                    style: TextStyle(
                        color: AppColors.errorInk, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (state.isNotEmpty)
            GlassBadge(
              text: state,
              color: state == 'ESTABLISHED' || state == 'ESTAB'
                  ? GlassTheme.successColor
                  : context.colors.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  Widget _buildBrowserTab() {
    final bool desktop = _isDesktopPlatform;
    if (desktop) {
      return Consumer<DesktopSecurityProvider>(
        builder: (context, provider, _) {
          final scan = provider.hostBrowserScan;
          return _buildBrowserContent(
            scanResult: scan,
            collecting: provider.isCollectingBrowser,
            onRefresh: () => provider.loadHostBrowserExtensions(),
            sourceLabel: scan?['source'] as String? ??
                'Filesystem scan of browser profiles on this device',
            errors: (scan?['errors'] as List?)?.whereType<String>().toList() ??
                const [],
          );
        },
      );
    }

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accentInk));
    }
    return _buildBrowserContent(
      scanResult: _browserScanResult,
      collecting: false,
      onRefresh: () async {
        final data = await _apiClient.scanBrowserExtensions().catchError((_) => <String, dynamic>{});
        setState(() => _browserScanResult = data.isNotEmpty ? data : null);
      },
      sourceLabel: 'Scanned on the OrbGuard Lab server host (not this device)',
      errors: const [],
    );
  }

  Widget _buildBrowserContent({
    required Map<String, dynamic>? scanResult,
    required bool collecting,
    required VoidCallback onRefresh,
    required String sourceLabel,
    required List<String> errors,
  }) {
    final extensions = (scanResult?['extensions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final totalExt = scanResult?['total'] as int? ?? extensions.length;
    final highRisk = scanResult?['high_risk'] as int? ?? 0;
    final byBrowser = (scanResult?['by_browser'] as Map?)?.cast<String, dynamic>() ?? {};

    return ListView(
      padding: _tabContentPadding,
      children: [
        // Summary card
        GlassCard(
          margin: EdgeInsets.zero,
          tintColor: highRisk > 0 ? GlassTheme.warningColor : null,
          child: Row(
            children: [
              GlassDuotoneIconBox(
                icon: 'globe',
                color: highRisk > 0 ? GlassTheme.warningColor : GlassTheme.successColor,
                size: 48,
                iconSize: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collecting ? 'Scanning…' : '$totalExt Extensions Found',
                      style: BrandText.title(size: 18),
                    ),
                    Text(
                      highRisk > 0 ? '$highRisk high-risk extension${highRisk > 1 ? 's' : ''} detected' : 'No high-risk extensions',
                      style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sourceLabel,
                      style: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (collecting)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: AppColors.accentInk, strokeWidth: 2),
                )
              else
                IconButton(
                  icon: DuotoneIcon('refresh', size: 20, color: context.colors.onSurface),
                  onPressed: onRefresh,
                ),
            ],
          ),
        ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          GlassCard(
            margin: EdgeInsets.zero,
            tintColor: GlassTheme.warningColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scan Notes',
                    style: TextStyle(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...errors.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• $e',
                          style: TextStyle(
                              color: context.colors.onSurfaceVariant, fontSize: 11)),
                    )),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Browser breakdown
        if (byBrowser.isNotEmpty) ...[
          Text('By Browser', style: BrandText.title()),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: byBrowser.entries.map((e) {
              return GlassBadge(text: '${e.key}: ${e.value}', color: GlassTheme.primaryAccent);
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Extension list
        if (extensions.isEmpty)
          GlassCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    DuotoneIcon('globe', size: 48, color: context.colors.outline),
                    const SizedBox(height: 12),
                    Text('No extensions data', style: TextStyle(color: context.colors.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('Tap refresh to scan browser extensions', style: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 12)),
                  ],
                ),
              ),
            ),
          )
        else
          ...extensions.map((ext) {
            final name = ext['name'] as String? ?? 'Unknown';
            final browser = ext['browser'] as String? ?? '';
            final risk = ext['risk_level'] as String? ?? 'low';
            final version = ext['version'] as String? ?? '';
            final isHighRisk = risk == 'high' || risk == 'critical';

            return GlassCard(
              tintColor: isHighRisk ? GlassTheme.errorColor : null,
              child: Row(
                children: [
                  GlassDuotoneIconBox(
                    icon: isHighRisk ? 'danger_triangle' : 'verified_check',
                    color: isHighRisk ? GlassTheme.errorColor : GlassTheme.successColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500)),
                        Text(
                          '$browser${version.isNotEmpty ? ' v$version' : ''}',
                          style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GlassBadge(
                    text: risk,
                    color: isHighRisk ? GlassTheme.errorColor : risk == 'medium' ? GlassTheme.warningColor : GlassTheme.successColor,
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildQuarantineTab() {
    return FutureBuilder<List<QuarantinedItem>>(
      future: _isDesktopPlatform
          ? context.read<DesktopSecurityProvider>().getQuarantinedItems()
          : Future.value([]),
      builder: (context, snapshot) {
        final quarantinedItems = snapshot.data ?? [];

        return ListView(
          padding: _tabContentPadding,
          children: [
            // Header stats
            GlassCard(
              margin: EdgeInsets.zero,
              child: Row(
                children: [
                  GlassSvgIconBox(
                    icon: 'danger_circle',
                    color: quarantinedItems.isEmpty
                        ? GlassTheme.successColor
                        : GlassTheme.warningColor,
                    size: 48,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quarantine',
                          style: BrandText.title(size: 18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          quarantinedItems.isEmpty
                              ? 'No items in quarantine'
                              : '${quarantinedItems.length} item${quarantinedItems.length == 1 ? '' : 's'} quarantined',
                          style: TextStyle(
                            color: context.colors.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (quarantinedItems.isNotEmpty)
                    IconButton(
                      icon: DuotoneIcon('refresh', color: context.colors.onSurface),
                      onPressed: () => setState(() {}),
                      tooltip: 'Refresh',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Info card
            GlassCard(
              margin: EdgeInsets.zero,
              child: Row(
                children: [
                  DuotoneIcon('info_circle', color: AppColors.accentInk, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Quarantined items are disabled and moved to a safe location. '
                      'You can restore them if needed.',
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quarantine location
            GlassCard(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quarantine Location',
                    style: TextStyle(
                      color: context.colors.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                    ),
                    child: Row(
                      children: [
                        DuotoneIcon('folder', color: context.colors.onSurfaceVariant, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _getQuarantinePath(),
                            style: TextStyle(
                              color: context.colors.onSurfaceVariant,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quarantined items list
            if (quarantinedItems.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      DuotoneIcon(
                        'check_circle',
                        color: AppColors.accentInk,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Quarantined Items',
                        style: BrandText.title(size: 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Items you quarantine from the Persistence tab will appear here.',
                        style: TextStyle(color: context.colors.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Text(
                'Quarantined Items',
                style: BrandText.title(),
              ),
              const SizedBox(height: 12),
              ...quarantinedItems.map((item) => _buildQuarantinedItemCard(item)),
            ],
          ],
        );
      },
    );
  }

  String _getQuarantinePath() {
    final home = PlatformInfo.environment['HOME'] ?? PlatformInfo.environment['USERPROFILE'] ?? '~';
    return '$home/.orbguard/quarantine';
  }

  Widget _buildQuarantinedItemCard(QuarantinedItem item) {
    final dateStr = item.quarantinedAt != null
        ? '${item.quarantinedAt!.day}/${item.quarantinedAt!.month}/${item.quarantinedAt!.year}'
        : 'Unknown date';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        margin: EdgeInsets.zero,
        child: Row(
          children: [
            GlassSvgIconBox(
              icon: item.isService ? 'settings' : (item.isRegistry ? 'code' : 'danger_circle'),
              color: GlassTheme.warningColor,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Quarantined $dateStr',
                    style: TextStyle(
                      color: AppColors.secondaryInk,
                      fontSize: 11,
                    ),
                  ),
                  if (item.originalPath.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.originalPath,
                      style: TextStyle(
                        color: context.colors.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Restore button
                if (item.canAutoRestore)
                  IconButton(
                    icon: DuotoneIcon('refresh', color: AppColors.accentInk, size: 20),
                    onPressed: () => _restoreQuarantinedItem(item),
                    tooltip: 'Restore',
                  )
                else
                  Tooltip(
                    message: item.isRegistry
                        ? 'No registry backup exists for this item — it must be restored manually'
                        : 'Cannot auto-restore',
                    child: IconButton(
                      icon: DuotoneIcon('refresh', color: context.colors.outline, size: 20),
                      onPressed: null,
                    ),
                  ),
                // Delete permanently button
                IconButton(
                  icon: DuotoneIcon('trash_bin_minimalistic', color: AppColors.errorInk, size: 20),
                  onPressed: () => _deleteQuarantinedItem(item),
                  tooltip: 'Delete Permanently',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreQuarantinedItem(QuarantinedItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.glassColor(context.isDark),
        title: Text('Restore Item?',
            style: TextStyle(color: context.colors.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to restore "${item.name}"?',
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            if (item.originalPath.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Will restore to:',
                style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.colors.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
                child: Text(
                  item.originalPath,
                  style: TextStyle(
                    color: context.colors.onSurfaceVariant,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'This will re-enable the persistence mechanism.',
              style: TextStyle(color: AppColors.secondaryInk, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.warningColor,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final scaffold = ScaffoldMessenger.of(context);
      final provider = context.read<DesktopSecurityProvider>();

      // Use metadata for automatic restore
      final success = await provider.restoreItem(item.fileName);
      if (mounted) {
        if (success) {
          scaffold.showSnackBar(
            SnackBar(
              content: Text('${item.name} has been restored'),
              backgroundColor: GlassTheme.successColor,
            ),
          );
          setState(() {}); // Refresh the list
        } else {
          scaffold.showSnackBar(
            SnackBar(
              content: Text('Failed to restore ${item.name}: ${provider.error ?? "Unknown error"}'),
              backgroundColor: GlassTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteQuarantinedItem(QuarantinedItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.glassColor(context.isDark),
        title: Text('Delete Permanently?',
            style: TextStyle(color: context.colors.onSurface)),
        content: Text(
          'Are you sure you want to permanently delete "${item.name}"? '
          'This action cannot be undone.',
          style: TextStyle(color: context.colors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.errorColor,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final scaffold = ScaffoldMessenger.of(context);
      final provider = context.read<DesktopSecurityProvider>();

      final success = await provider.deleteQuarantinedItem(item.fileName);
      if (mounted) {
        if (success) {
          scaffold.showSnackBar(
            SnackBar(
              content: Text('${item.name} has been permanently deleted'),
              backgroundColor: GlassTheme.successColor,
            ),
          );
          setState(() {}); // Refresh the list
        } else {
          scaffold.showSnackBar(
            SnackBar(
              content: Text('Failed to delete ${item.name}'),
              backgroundColor: GlassTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  Future<void> _exportResults() async {
    final provider = context.read<DesktopSecurityProvider>();
    final results = provider.exportResults();

    if (results.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No scan results to export. Run a scan first.'),
            backgroundColor: GlassTheme.warningColor,
          ),
        );
      }
      return;
    }

    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(results);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final home = PlatformInfo.environment['HOME'] ?? PlatformInfo.environment['USERPROFILE'] ?? '';
      final exportPath = '$home/orbguard_scan_$timestamp.json';

      await File(exportPath).writeAsString(jsonStr);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to $exportPath'),
            backgroundColor: GlassTheme.successColor,
            action: SnackBarAction(
              label: 'Open Folder',
              textColor: Brand.onLime,
              onPressed: () {
                if (PlatformInfo.isMacOS) {
                  Process.run('open', ['-R', exportPath]);
                } else if (PlatformInfo.isWindows) {
                  Process.run('explorer', ['/select,', exportPath]);
                } else if (PlatformInfo.isLinux) {
                  Process.run('xdg-open', [home]);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: GlassTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _runScan() async {
    setState(() => _isScanning = true);

    try {
      if (_isDesktopPlatform) {
        // Use native scanning on desktop platforms
        final provider = context.read<DesktopSecurityProvider>();
        final result = await provider.runFullScan();

        if (!mounted) return;

        setState(() {
          _isScanning = false;
          // Update persistence items with native scan results
          _persistenceItems.clear();
          _persistenceItems.addAll(
            result.items.map((item) => PersistenceItem(
              id: item.id,
              name: item.name,
              type: item.typeDisplayName,
              path: item.path,
              enabled: item.isEnabled,
              runAtLoad: item.isEnabled,
              riskLevel: item.risk == DesktopItemRisk.safe ? 'clean' : item.risk.name,
              riskReasons: item.indicators,
              isKnownBad: item.risk == DesktopItemRisk.critical,
            )),
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Native scan complete: ${result.totalItems} items found'),
            backgroundColor: GlassTheme.successColor,
          ),
        );
      } else {
        // Run persistence scan via API for non-desktop
        final results = await _apiClient.scanPersistence();

        if (!mounted) return;

        setState(() {
          _isScanning = false;
          // Update persistence items with new scan results
          if (results['items'] != null) {
            _persistenceItems.clear();
            _persistenceItems.addAll(
              (results['items'] as List).map((json) => PersistenceItem.fromJson(json as Map<String, dynamic>)),
            );
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Persistence scan complete'),
            backgroundColor: GlassTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan failed: $e'),
          backgroundColor: GlassTheme.errorColor,
        ),
      );
    }
  }

  void _showPersistenceDetails(BuildContext context, PersistenceItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: context.isDark
                  ? const [GlassTheme.gradientTop, GlassTheme.gradientBottom]
                  : const [
                      GlassTheme.gradientTopLight,
                      GlassTheme.gradientBottomLight
                    ],
            ),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  GlassSvgIconBox(
                    icon: _getPersistenceIcon(item.type),
                    color: item.isSuspicious ? GlassTheme.errorColor : GlassTheme.successColor,
                    size: 56,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: BrandText.heading(size: 20)),
                        const SizedBox(height: 4),
                        GlassBadge(
                          text: item.isSuspicious ? 'Suspicious' : 'Safe',
                          color: item.isSuspicious ? GlassTheme.errorColor : GlassTheme.successColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Type', item.type),
                    _buildDetailRow('Status', item.enabled ? 'Enabled' : 'Disabled'),
                    _buildDetailRow('Run at Load', item.runAtLoad ? 'Yes' : 'No'),
                    _buildDetailRow('Risk Level', item.riskLevel.toUpperCase()),
                    if (item.codeSigning != null)
                      _buildDetailRow('Code Signing', item.codeSigning!),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Path', style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  item.path,
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              if (item.riskReasons.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Risk Reasons',
                style: TextStyle(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                GlassContainer(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: item.riskReasons
                        .map((r) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '• $r',
                                style: TextStyle(color: AppColors.errorInk),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (item.isSuspicious)
                ElevatedButton.icon(
                  onPressed: () async {
                    // Capture context before async gap
                    final navigator = Navigator.of(context);
                    final scaffold = ScaffoldMessenger.of(context);
                    final provider = context.read<DesktopSecurityProvider>();

                    navigator.pop();

                    // Find the corresponding DesktopPersistenceItem from provider
                    final providerItem = provider.items.firstWhere(
                      (i) => i.id == item.id,
                      orElse: () => DesktopPersistenceItem(
                        id: item.id,
                        name: item.name,
                        path: item.path,
                        type: item.type,
                        typeDisplayName: item.type,
                        risk: DesktopItemRisk.high,
                      ),
                    );

                    // Attempt to disable/quarantine the item
                    final success = await provider.disableItem(providerItem);

                    if (mounted) {
                      if (success) {
                        setState(() => _persistenceItems.remove(item));
                        scaffold.showSnackBar(
                          SnackBar(
                            content: Text('${item.name} has been quarantined'),
                            backgroundColor: GlassTheme.successColor,
                          ),
                        );
                      } else {
                        scaffold.showSnackBar(
                          SnackBar(
                            content: Text('Failed to quarantine ${item.name}. ${provider.error ?? ""}'),
                            backgroundColor: GlassTheme.errorColor,
                          ),
                        );
                      }
                    }
                  },
                  icon: const DuotoneIcon('trash_bin_minimalistic', size: 20),
                  label: const Text('Quarantine'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GlassTheme.errorColor,
                    foregroundColor: Brand.onDanger,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSigningDetails(BuildContext context, SignedApp app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: context.isDark
                  ? const [GlassTheme.gradientTop, GlassTheme.gradientBottom]
                  : const [
                      GlassTheme.gradientTopLight,
                      GlassTheme.gradientBottomLight
                    ],
            ),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Text(app.name, style: BrandText.heading(size: 20)),
              const SizedBox(height: 8),
              Text(app.bundleId, style: TextStyle(color: context.colors.onSurfaceVariant, fontFamily: 'monospace')),
              const SizedBox(height: 16),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Signed', app.isSigned ? 'Yes' : 'No'),
                    if (app.isSigned) ...[
                      _buildDetailRow('Valid', app.isValid ? 'Yes' : 'No'),
                      _buildDetailRow('Developer', app.developer),
                      _buildDetailRow('Team ID', app.teamId ?? 'N/A'),
                    ],
                    _buildDetailRow(
                      'Verified',
                      app.source == 'local'
                          ? 'Locally on this device'
                          : 'On the OrbGuard server host',
                    ),
                  ],
                ),
              ),
              if (app.path != null && app.path!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Path', style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                GlassContainer(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    app.path!,
                    style: TextStyle(
                        color: context.colors.onSurfaceVariant,
                        fontFamily: 'monospace',
                        fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _lookupAppOnVirusTotal(app);
                  },
                  icon: const DuotoneIcon('shield', size: 20),
                  label: const Text('Check Hash on VirusTotal'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GlassTheme.primaryAccent,
                    foregroundColor: Brand.onLime,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Computes the file's SHA-256 locally and queries VirusTotal through the
  /// backend (a genuinely client-value-based lookup). Shows the real report
  /// or the real failure.
  Future<void> _lookupAppOnVirusTotal(SignedApp app) async {
    final provider = context.read<DesktopSecurityProvider>();
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(
      content: Text('Hashing file and querying VirusTotal…'),
      duration: Duration(seconds: 2),
    ));
    try {
      final report = await provider.lookupFileOnVirusTotal(app.path!);
      if (!mounted) return;

      final found = report['found'] as bool? ?? false;
      final detections = (report['detections'] as num?)?.toInt() ?? 0;
      final total = (report['total_engines'] as num?)?.toInt() ?? 0;
      final malicious = report['malicious'] as bool? ?? false;
      final hash = report['sha256'] as String? ?? report['hash'] as String? ?? '';

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: GlassTheme.glassColor(context.isDark),
          title: Text('VirusTotal: ${app.name}',
              style: TextStyle(color: context.colors.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!found)
                Text(
                  'This file hash is not known to VirusTotal.',
                  style: TextStyle(color: context.colors.onSurfaceVariant),
                )
              else
                Text(
                  '$detections of $total engines flagged this file.',
                  style: TextStyle(
                    color: malicious || detections > 0
                        ? AppColors.errorInk
                        : AppColors.accentInk,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (hash.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  'SHA-256: $hash',
                  style: TextStyle(
                      color: context.colors.onSurfaceVariant,
                      fontFamily: 'monospace',
                      fontSize: 11),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      scaffold.showSnackBar(SnackBar(
        content: Text('VirusTotal lookup failed: $e'),
        backgroundColor: GlassTheme.errorColor,
      ));
    }
  }

  /// Add Rule dialog. The user picks where the rule lives, and the labels
  /// are explicit about it:
  ///  - "OrbGuard server": persisted via POST /desktop/network/rules and
  ///    enforced on the OrbGuard Lab backend host.
  ///  - "This device": created in the local OS firewall (netsh / ufw /
  ///    socketfilterfw app rules) with real elevation prompts.
  void _showAddRuleDialog(BuildContext context) {
    final nameController = TextEditingController();
    final portController = TextEditingController();
    final addressController = TextEditingController();
    final appPathController = TextEditingController();
    String action = 'Block';
    String direction = 'Inbound';
    String protocol = 'TCP';
    String target = _isDesktopPlatform ? 'local' : 'server';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isMacLocal = target == 'local' && PlatformInfo.isMacOS;
          final dialogBg = dialogContext.isDark
              ? GlassTheme.gradientTop
              : GlassTheme.gradientTopLight;
          return AlertDialog(
            backgroundColor: dialogBg,
            title: Text('Add Firewall Rule',
                style: TextStyle(color: context.colors.onSurface)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: target,
                    dropdownColor: dialogBg,
                    style: TextStyle(color: context.colors.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Apply to',
                      labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                    ),
                    items: [
                      if (_isDesktopPlatform)
                        const DropdownMenuItem(
                          value: 'local',
                          child: Text('This device (local OS firewall)'),
                        ),
                      const DropdownMenuItem(
                        value: 'server',
                        child: Text('OrbGuard server (backend host)'),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => target = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: context.colors.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Rule Name',
                      labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: action,
                          dropdownColor: dialogBg,
                          style: TextStyle(color: context.colors.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Action',
                            labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                          ),
                          items: ['Allow', 'Block'].map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                          onChanged: (v) => setDialogState(() => action = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: direction,
                          dropdownColor: dialogBg,
                          style: TextStyle(color: context.colors.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Direction',
                            labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                          ),
                          items: ['Inbound', 'Outbound'].map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                          onChanged: (v) => setDialogState(() => direction = v!),
                        ),
                      ),
                    ],
                  ),
                  if (!isMacLocal) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: protocol,
                            dropdownColor: dialogBg,
                            style: TextStyle(color: context.colors.onSurface),
                            decoration: InputDecoration(
                              labelText: 'Protocol',
                              labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                            ),
                            items: ['TCP', 'UDP', 'Any'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                            onChanged: (v) => setDialogState(() => protocol = v!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: portController,
                            style: TextStyle(color: context.colors.onSurface),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Port (optional)',
                              labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: addressController,
                      style: TextStyle(color: context.colors.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Remote address / CIDR (optional)',
                        labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: appPathController,
                      style: TextStyle(color: context.colors.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Application path (required)',
                        helperText: 'macOS Application Firewall only supports per-app rules',
                        helperStyle: TextStyle(color: context.colors.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 11),
                        labelStyle: TextStyle(color: context.colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              TextButton(
                onPressed: () {
                  if (nameController.text.isEmpty) return;
                  Navigator.pop(dialogContext);
                  _submitFirewallRule(
                    target: target,
                    name: nameController.text,
                    action: action,
                    direction: direction,
                    protocol: protocol,
                    port: portController.text.trim(),
                    address: addressController.text.trim(),
                    appPath: appPathController.text.trim(),
                  );
                },
                child: Text('Add', style: TextStyle(color: AppColors.accentInk)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitFirewallRule({
    required String target,
    required String name,
    required String action,
    required String direction,
    required String protocol,
    required String port,
    required String address,
    required String appPath,
  }) async {
    final scaffold = ScaffoldMessenger.of(context);

    if (target == 'server') {
      // Server-side rule: enforced on the OrbGuard Lab backend host.
      try {
        await _apiClient.addFirewallRule({
          'name': name,
          'action': action.toLowerCase(),
          'direction': direction.toLowerCase(),
          'protocol': protocol == 'Any' ? 'any' : protocol.toLowerCase(),
          if (port.isNotEmpty) 'dest_port': port,
          if (address.isNotEmpty) 'dest_address': address,
          'enabled': true,
        });
        // Re-read the authoritative server rule list instead of fabricating
        // a local entry.
        final firewallData = await _apiClient.getDesktopFirewallRules();
        if (!mounted) return;
        setState(() {
          _firewallRules
            ..clear()
            ..addAll(firewallData.map((json) => FirewallRule.fromJson(json)));
        });
        scaffold.showSnackBar(SnackBar(
          content: Text('Rule "$name" added on the OrbGuard server'),
          backgroundColor: GlassTheme.successColor,
        ));
      } catch (e) {
        if (!mounted) return;
        scaffold.showSnackBar(SnackBar(
          content: Text('Failed to add server rule: $e'),
          backgroundColor: GlassTheme.errorColor,
        ));
      }
      return;
    }

    // Local OS firewall rule.
    final provider = context.read<DesktopSecurityProvider>();
    final result = await provider.addLocalFirewallRule(
      name: name,
      action: action.toLowerCase(),
      direction: direction.toLowerCase(),
      protocol: protocol == 'Any' ? 'any' : protocol.toLowerCase(),
      port: port.isEmpty ? null : port,
      remoteAddress: address.isEmpty ? null : address,
      appPath: appPath.isEmpty ? null : appPath,
    );
    if (!mounted) return;
    scaffold.showSnackBar(SnackBar(
      content: Text(
        result.success
            ? 'Local firewall rule "$name" created on this device'
            : result.message,
      ),
      backgroundColor: result.success
          ? GlassTheme.successColor
          : (result.cancelled || result.unsupported)
              ? GlassTheme.warningColor
              : GlassTheme.errorColor,
      duration: const Duration(seconds: 5),
    ));
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.colors.onSurfaceVariant)),
          Text(value, style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _getPersistenceIcon(String type) {
    final lowerType = type.toLowerCase();
    // macOS types
    if (lowerType.contains('launch agent')) return 'play_circle';
    if (lowerType.contains('launch daemon')) return 'settings';
    if (lowerType.contains('login item')) return 'user';
    if (lowerType.contains('kernel extension')) return 'cpu';
    if (lowerType.contains('browser extension')) return 'widget';
    if (lowerType.contains('cron')) return 'clock_circle';
    if (lowerType.contains('auth plugin')) return 'shield';
    if (lowerType.contains('spotlight')) return 'eye';
    if (lowerType.contains('scripting')) return 'code';
    if (lowerType.contains('startup')) return 'play_circle';
    if (lowerType.contains('periodic')) return 'clock_circle';
    if (lowerType.contains('emond')) return 'danger_circle';
    if (lowerType.contains('quick look')) return 'eye';
    if (lowerType.contains('screen saver')) return 'smartphone';
    if (lowerType.contains('folder action')) return 'folder';
    if (lowerType.contains('input method')) return 'code_square';
    if (lowerType.contains('colorsync')) return 'settings';
    // Windows types
    if (lowerType.contains('registry')) return 'key';
    if (lowerType.contains('scheduled task')) return 'clock_circle';
    if (lowerType.contains('service')) return 'settings';
    if (lowerType.contains('wmi')) return 'server';
    if (lowerType.contains('com object')) return 'code';
    if (lowerType.contains('ifeo')) return 'danger_circle';
    if (lowerType.contains('winlogon')) return 'user';
    if (lowerType.contains('appinit')) return 'danger_circle';
    if (lowerType.contains('lsa')) return 'shield';
    if (lowerType.contains('print')) return 'document';
    if (lowerType.contains('boot')) return 'cpu';
    if (lowerType.contains('netsh')) return 'link_round';
    if (lowerType.contains('office')) return 'document';
    if (lowerType.contains('powershell')) return 'code_square';
    if (lowerType.contains('active setup')) return 'settings';
    // Linux types
    if (lowerType.contains('systemd')) return 'settings';
    if (lowerType.contains('init')) return 'play_circle';
    if (lowerType.contains('shell rc')) return 'code';
    if (lowerType.contains('xdg') || lowerType.contains('autostart')) return 'folder';
    if (lowerType.contains('kernel module')) return 'cpu';
    if (lowerType.contains('ld_preload')) return 'danger_circle';
    if (lowerType.contains('ssh')) return 'key';
    if (lowerType.contains('at job')) return 'clock_circle';
    if (lowerType.contains('udev')) return 'server';
    if (lowerType.contains('rc local')) return 'code';
    if (lowerType.contains('profile')) return 'user';
    if (lowerType.contains('motd')) return 'letter';
    if (lowerType.contains('pam')) return 'shield';
    if (lowerType.contains('polkit')) return 'shield';
    if (lowerType.contains('sudoers')) return 'key';
    if (lowerType.contains('dbus') || lowerType.contains('d-bus')) return 'link_round';
    if (lowerType.contains('desktop')) return 'smartphone';
    if (lowerType.contains('environment')) return 'settings';
    if (lowerType.contains('selinux')) return 'shield';
    if (lowerType.contains('tcp wrapper') || lowerType.contains('hosts')) return 'link_round';
    return 'code';
  }

  String _getAppIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('safari') || lower.contains('chrome') || lower.contains('firefox')) {
      return 'globus';
    } else if (lower.contains('mail') || lower.contains('outlook')) {
      return 'letter';
    } else if (lower.contains('terminal') || lower.contains('iterm')) {
      return 'code_square';
    } else if (lower.contains('code') || lower.contains('xcode')) {
      return 'code';
    } else if (lower.contains('finder')) {
      return 'folder';
    }
    return 'smartphone';
  }

  Widget _buildEmptyState(String title, String subtitle, String icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            DuotoneIcon(
              icon,
              color: context.colors.onSurfaceVariant.withValues(alpha: 0.7),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: BrandText.title(),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

}

/// Mirrors the live PersistenceItem JSON emitted by the backend
/// (orbguard-lab internal/domain/models/desktop_security.go): id, type, name,
/// path, enabled, run_at_load, risk_level (critical/high/medium/low/info/
/// clean), risk_reasons, is_known_bad, code_signing, ...
class PersistenceItem {
  final String id;
  final String name;
  final String type;
  final String path;
  final bool enabled;
  final bool runAtLoad;
  final String riskLevel;
  final List<String> riskReasons;
  final bool isKnownBad;
  final String? codeSigning;

  PersistenceItem({
    required this.id,
    required this.name,
    required this.type,
    required this.path,
    required this.enabled,
    required this.runAtLoad,
    required this.riskLevel,
    required this.riskReasons,
    required this.isKnownBad,
    this.codeSigning,
  });

  bool get isSuspicious =>
      isKnownBad || riskLevel == 'critical' || riskLevel == 'high';

  String? get reason => riskReasons.isNotEmpty ? riskReasons.join('; ') : null;

  factory PersistenceItem.fromJson(Map<String, dynamic> json) {
    return PersistenceItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      type: json['type'] as String? ?? 'Unknown',
      path: json['path'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      runAtLoad: json['run_at_load'] as bool? ?? false,
      riskLevel: json['risk_level'] as String? ?? 'info',
      riskReasons:
          (json['risk_reasons'] as List?)?.whereType<String>().toList() ?? const [],
      isKnownBad: json['is_known_bad'] as bool? ?? false,
      codeSigning: json['code_signing'] as String?,
    );
  }
}

class SignedApp {
  final String name;
  final String bundleId;
  final bool isSigned;
  final bool isValid;
  final String developer;
  final String? teamId;

  /// Filesystem path of the verified binary/bundle (present for local
  /// verification results; enables the VirusTotal hash lookup).
  final String? path;

  /// 'local' = verified on this device with codesign/Authenticode;
  /// 'server' = cached verification from the OrbGuard Lab backend host.
  final String source;

  SignedApp({
    required this.name,
    required this.bundleId,
    required this.isSigned,
    required this.isValid,
    required this.developer,
    this.teamId,
    this.path,
    this.source = 'server',
  });

  factory SignedApp.fromJson(Map<String, dynamic> json) {
    return SignedApp(
      name: json['name'] as String? ?? 'Unknown',
      bundleId: json['bundle_id'] as String? ?? '',
      isSigned: json['is_signed'] as bool? ?? false,
      isValid: json['is_valid'] as bool? ?? false,
      developer: json['developer'] as String? ?? '',
      teamId: json['team_id'] as String?,
      path: json['path'] as String?,
      source: json['source'] as String? ?? 'server',
    );
  }
}

/// Mirrors the live FirewallRule JSON emitted by the backend
/// (orbguard-lab internal/domain/models/desktop_security.go): id, name,
/// action, direction, protocol, dest_address, dest_port (string: port, range
/// or any), enabled, ...
class FirewallRule {
  final String id;
  final String name;
  final String action;
  final String direction;
  final String protocol;
  final String? destPort;
  final String? destAddress;
  bool isEnabled;

  FirewallRule({
    required this.id,
    required this.name,
    required this.action,
    required this.direction,
    required this.protocol,
    this.destPort,
    this.destAddress,
    this.isEnabled = true,
  });

  factory FirewallRule.fromJson(Map<String, dynamic> json) {
    final destPort = json['dest_port'] as String?;
    final destAddress = json['dest_address'] as String?;
    return FirewallRule(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Rule',
      action: json['action'] as String? ?? 'block',
      direction: json['direction'] as String? ?? 'inbound',
      protocol: json['protocol'] as String? ?? 'any',
      destPort: (destPort != null && destPort.isNotEmpty) ? destPort : null,
      destAddress: (destAddress != null && destAddress.isNotEmpty) ? destAddress : null,
      isEnabled: json['enabled'] as bool? ?? true,
    );
  }
}
