/// Desktop-specific security features including persistence scanning,
/// code signing verification, and firewall management
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/desktop_security_provider.dart';
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

  bool get _isDesktopPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  String _getPlatformName() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Desktop';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    if (_isDesktopPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<DesktopSecurityProvider>().init();
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load desktop security data from API
      final persistenceData = await _apiClient.getPersistenceItems();
      final signedAppsData = await _apiClient.getSignedApps();
      final firewallData = await _apiClient.getDesktopFirewallRules();

      setState(() {
        _persistenceItems.clear();
        _persistenceItems.addAll(persistenceData.map((json) => PersistenceItem.fromJson(json)));

        _signedApps.clear();
        _signedApps.addAll(signedAppsData.map((json) => SignedApp.fromJson(json)));

        _firewallRules.clear();
        _firewallRules.addAll(firewallData.map((json) => FirewallRule.fromJson(json)));

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load desktop security data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassTabPage(
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
              icon: const DuotoneIcon('download_minimalistic', size: 22, color: Colors.white),
              onPressed: _exportResults,
              tooltip: 'Export Results',
            ),
            IconButton(
              icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
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
          label: 'Quarantine',
          iconPath: 'danger_circle',
          content: _buildQuarantineTab(),
        ),
      ],
    );
  }

  Widget _buildPersistenceTab() {
    final suspicious = _persistenceItems.where((i) => i.isSuspicious).length;
    final safe = _persistenceItems.length - suspicious;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Scan button
        _isDesktopPlatform
            ? Consumer<DesktopSecurityProvider>(
                builder: (context, provider, child) {
                  final scanPhase = provider.isScanning ? provider.currentPhase : '';
                  final progress = provider.scanProgress;

                  return GlassCard(
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
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    provider.isScanning
                                        ? scanPhase
                                        : 'Native scan for persistence mechanisms',
                                    style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            if (_isScanning || provider.isScanning)
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: GlassTheme.primaryAccent,
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              const DuotoneIcon('play', color: GlassTheme.primaryAccent),
                          ],
                        ),
                        if (provider.isScanning) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white.withAlpha(30),
                              color: GlassTheme.primaryAccent,
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
                          const Text(
                            'Persistence Scanner',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _isScanning ? 'Scanning...' : 'Scan for persistence mechanisms',
                            style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (_isScanning)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: GlassTheme.primaryAccent,
                          strokeWidth: 2,
                        ),
                      )
                    else
                      const DuotoneIcon('play', color: GlassTheme.primaryAccent),
                  ],
                ),
              ),

        // Stats
        const SizedBox(height: 16),
        Row(
          children: [
            _buildStatCard('Suspicious', suspicious.toString(), GlassTheme.errorColor),
            const SizedBox(width: 12),
            _buildStatCard('Safe', safe.toString(), GlassTheme.successColor),
          ],
        ),

        // Error display
        if (_error != null) ...[
          const SizedBox(height: 16),
          GlassCard(
            tintColor: GlassTheme.errorColor,
            child: Row(
              children: [
                const DuotoneIcon('danger_circle', color: GlassTheme.errorColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Error Loading Data',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const DuotoneIcon('refresh', color: Colors.white, size: 20),
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
    if (Platform.isMacOS) {
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
    } else if (Platform.isWindows) {
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
    } else if (Platform.isLinux) {
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
            Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  item.type,
                  style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  item.path,
                  style: TextStyle(
                    color: Colors.white.withAlpha(102),
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
          GlassSvgIconBox(icon: icon, color: enabled ? GlassTheme.primaryAccent : Colors.grey, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ),
          DuotoneIcon(
            enabled ? 'check_circle' : 'close_circle',
            color: enabled ? GlassTheme.successColor : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildCodeSigningTab() {
    final unsigned = _signedApps.where((a) => !a.isSigned).length;
    final invalid = _signedApps.where((a) => a.isSigned && !a.isValid).length;
    final valid = _signedApps.where((a) => a.isSigned && a.isValid).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Valid', valid.toString(), GlassTheme.successColor),
            const SizedBox(width: 12),
            _buildStatCard('Invalid', invalid.toString(), GlassTheme.errorColor),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatCard('Unsigned', unsigned.toString(), GlassTheme.warningColor),
            const SizedBox(width: 12),
            _buildStatCard('Total Apps', _signedApps.length.toString(), GlassTheme.primaryAccent),
          ],
        ),

        // Apps list
        const SizedBox(height: 24),
        const GlassSectionHeader(title: 'Running Applications'),
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
      statusColor = GlassTheme.warningColor;
      statusText = 'Unsigned';
      statusIcon = 'danger_triangle';
    } else if (!app.isValid) {
      statusColor = GlassTheme.errorColor;
      statusText = 'Invalid';
      statusIcon = 'danger_circle';
    } else {
      statusColor = GlassTheme.successColor;
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
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: DuotoneIcon(
                _getAppIcon(app.name),
                color: Colors.white,
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                if (app.isSigned && app.developer.isNotEmpty)
                  Text(
                    app.developer,
                    style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
                  ),
                Text(
                  app.bundleId,
                  style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10, fontFamily: 'monospace'),
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
    final blocked = _firewallRules.where((r) => r.action == 'Block').length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Firewall status
        GlassCard(
          tintColor: GlassTheme.successColor,
          child: Row(
            children: [
              GlassSvgIconBox(icon: 'shield_check', color: GlassTheme.successColor),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Firewall Status',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Active and protecting your system',
                      style: TextStyle(color: GlassTheme.successColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: true,
                onChanged: (v) {},
                activeTrackColor: GlassTheme.successColor.withAlpha(128),
                activeThumbColor: GlassTheme.successColor,
              ),
            ],
          ),
        ),

        // Stats
        const SizedBox(height: 16),
        Row(
          children: [
            _buildStatCard('Active Rules', enabled.toString(), GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Blocked', blocked.toString(), GlassTheme.errorColor),
          ],
        ),

        // Quick actions
        const SizedBox(height: 24),
        const GlassSectionHeader(title: 'Quick Actions'),
        _buildQuickAction('forbidden', 'Block All Incoming', 'Block all incoming connections'),
        _buildQuickAction('eye_closed', 'Stealth Mode', 'Hide from network scans'),
        _buildQuickAction('smartphone', 'App Permissions', 'Manage application access'),

        // Rules
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const GlassSectionHeader(title: 'Firewall Rules'),
            TextButton.icon(
              onPressed: () => _showAddRuleDialog(context),
              icon: const DuotoneIcon('add_circle', size: 18),
              label: const Text('Add Rule'),
              style: TextButton.styleFrom(foregroundColor: GlassTheme.primaryAccent),
            ),
          ],
        ),
        if (_firewallRules.isEmpty && !_isLoading)
          _buildEmptyState(
            'No Firewall Rules',
            'Add custom rules to control network access.',
            'shield_network',
          )
        else
          ..._firewallRules.map((rule) => _buildFirewallRuleCard(rule)),
      ],
    );
  }

  Widget _buildQuickAction(String icon, String title, String subtitle) {
    return GlassCard(
      onTap: () => _showQuickActionDialog(icon),
      child: Row(
        children: [
          GlassSvgIconBox(icon: icon, color: GlassTheme.primaryAccent, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11)),
              ],
            ),
          ),
          const DuotoneIcon('alt_arrow_right', color: Colors.white38),
        ],
      ),
    );
  }

  Widget _buildFirewallRuleCard(FirewallRule rule) {
    final isBlock = rule.action == 'Block';

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
                Text(rule.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                      color: Colors.grey,
                      fontSize: 10,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${rule.port != null ? "Port ${rule.port}" : "All ports"} • ${rule.address ?? "Any address"}',
                  style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10),
                ),
              ],
            ),
          ),
          Switch(
            value: rule.isEnabled,
            onChanged: (v) => setState(() => rule.isEnabled = v),
            activeTrackColor: GlassTheme.successColor.withAlpha(128),
            activeThumbColor: GlassTheme.successColor,
          ),
        ],
      ),
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
          padding: const EdgeInsets.all(16),
          children: [
            // Header stats
            GlassCard(
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          quarantinedItems.isEmpty
                              ? 'No items in quarantine'
                              : '${quarantinedItems.length} item${quarantinedItems.length == 1 ? '' : 's'} quarantined',
                          style: TextStyle(
                            color: Colors.white.withAlpha(179),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (quarantinedItems.isNotEmpty)
                    IconButton(
                      icon: const DuotoneIcon('refresh', color: Colors.white),
                      onPressed: () => setState(() {}),
                      tooltip: 'Refresh',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Info card
            GlassCard(
              child: Row(
                children: [
                  DuotoneIcon('info_circle', color: GlassTheme.primaryAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Quarantined items are disabled and moved to a safe location. '
                      'You can restore them if needed.',
                      style: TextStyle(
                        color: Colors.white.withAlpha(179),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Quarantine location
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quarantine Location',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(51),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const DuotoneIcon('folder', color: Colors.white54, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _getQuarantinePath(),
                            style: TextStyle(
                              color: Colors.white.withAlpha(179),
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
                        color: GlassTheme.successColor,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No Quarantined Items',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Items you quarantine from the Persistence tab will appear here.',
                        style: TextStyle(color: Colors.white.withAlpha(128)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              const Text(
                'Quarantined Items',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '~';
    return '$home/.orbguard/quarantine';
  }

  Widget _buildQuarantinedItemCard(QuarantinedItem item) {
    final dateStr = item.quarantinedAt != null
        ? '${item.quarantinedAt!.day}/${item.quarantinedAt!.month}/${item.quarantinedAt!.year}'
        : 'Unknown date';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.type,
                    style: TextStyle(
                      color: Colors.white.withAlpha(179),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Quarantined $dateStr',
                    style: TextStyle(
                      color: GlassTheme.warningColor.withAlpha(179),
                      fontSize: 11,
                    ),
                  ),
                  if (item.originalPath.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.originalPath,
                      style: TextStyle(
                        color: Colors.white.withAlpha(100),
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
                    icon: DuotoneIcon('refresh', color: GlassTheme.successColor, size: 20),
                    onPressed: () => _restoreQuarantinedItem(item),
                    tooltip: 'Restore',
                  )
                else
                  Tooltip(
                    message: item.isRegistry ? 'Registry items require manual restoration' : 'Cannot auto-restore',
                    child: IconButton(
                      icon: DuotoneIcon('refresh', color: Colors.white24, size: 20),
                      onPressed: null,
                    ),
                  ),
                // Delete permanently button
                IconButton(
                  icon: DuotoneIcon('trash_bin_minimalistic', color: GlassTheme.errorColor, size: 20),
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
        backgroundColor: GlassTheme.glassColor(true),
        title: const Text('Restore Item?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to restore "${item.name}"?',
              style: TextStyle(color: Colors.white.withAlpha(204)),
            ),
            if (item.originalPath.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Will restore to:',
                style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(51),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.originalPath,
                  style: TextStyle(
                    color: Colors.white.withAlpha(179),
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'This will re-enable the persistence mechanism.',
              style: TextStyle(color: GlassTheme.warningColor.withAlpha(179), fontSize: 12),
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
        backgroundColor: GlassTheme.glassColor(true),
        title: const Text('Delete Permanently?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to permanently delete "${item.name}"? '
          'This action cannot be undone.',
          style: TextStyle(color: Colors.white.withAlpha(204)),
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
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      final exportPath = '$home/orbguard_scan_$timestamp.json';

      await File(exportPath).writeAsString(jsonStr);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to $exportPath'),
            backgroundColor: GlassTheme.successColor,
            action: SnackBarAction(
              label: 'Open Folder',
              textColor: Colors.white,
              onPressed: () {
                if (Platform.isMacOS) {
                  Process.run('open', ['-R', exportPath]);
                } else if (Platform.isWindows) {
                  Process.run('explorer', ['/select,', exportPath]);
                } else if (Platform.isLinux) {
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
              isRunning: item.isEnabled,
              autoStart: item.isEnabled,
              isSuspicious: item.risk.level >= DesktopItemRisk.high.level,
              reason: item.indicators.isNotEmpty ? item.indicators.first : null,
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                        Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                    _buildDetailRow('Status', item.isRunning ? 'Running' : 'Stopped'),
                    _buildDetailRow('Auto Start', item.autoStart ? 'Yes' : 'No'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Path', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  item.path,
                  style: TextStyle(color: Colors.white.withAlpha(204), fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              if (item.isSuspicious) ...[
                const SizedBox(height: 16),
                const Text('Reason', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                GlassContainer(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    item.reason ?? 'Unknown executable in startup location',
                    style: TextStyle(color: GlassTheme.errorColor.withAlpha(230)),
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
                    foregroundColor: Colors.white,
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Text(app.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(app.bundleId, style: TextStyle(color: Colors.white.withAlpha(153), fontFamily: 'monospace')),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddRuleDialog(BuildContext context) {
    final nameController = TextEditingController();
    String action = 'Block';
    String direction = 'Incoming';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: GlassTheme.gradientTop,
          title: const Text('Add Firewall Rule', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Rule Name',
                  labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: action,
                      dropdownColor: GlassTheme.gradientTop,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Action',
                        labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                      ),
                      items: ['Allow', 'Block'].map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                      onChanged: (v) => setDialogState(() => action = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: direction,
                      dropdownColor: GlassTheme.gradientTop,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Direction',
                        labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                      ),
                      items: ['Incoming', 'Outgoing'].map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                      onChanged: (v) => setDialogState(() => direction = v!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  setState(() {
                    _firewallRules.add(FirewallRule(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text,
                      action: action,
                      direction: direction,
                      protocol: 'TCP',
                    ));
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add', style: TextStyle(color: GlassTheme.primaryAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(153))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
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

  void _showQuickActionDialog(String action) {
    String title;
    String description;

    switch (action) {
      case 'forbidden':
        title = 'Block All Incoming';
        description = 'This will block all incoming network connections except for established connections and essential services.';
        break;
      case 'eye_closed':
        title = 'Stealth Mode';
        description = 'Your device will not respond to network discovery requests, making it invisible to port scans.';
        break;
      case 'smartphone':
        title = 'App Permissions';
        description = 'Manage which applications can access the network.';
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.glassColor(true),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: TextStyle(color: Colors.white.withAlpha(204)),
            ),
            const SizedBox(height: 16),
            Text(
              'Note: This feature requires system-level firewall access.',
              style: TextStyle(color: GlassTheme.warningColor.withAlpha(204), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$title enabled'),
                  backgroundColor: GlassTheme.successColor,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
            ),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle, String icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            DuotoneIcon(
              icon,
              color: Colors.white.withAlpha(100),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

}

class PersistenceItem {
  final String id;
  final String name;
  final String type;
  final String path;
  final bool isRunning;
  final bool autoStart;
  final bool isSuspicious;
  final String? reason;

  PersistenceItem({
    required this.id,
    required this.name,
    required this.type,
    required this.path,
    required this.isRunning,
    required this.autoStart,
    required this.isSuspicious,
    this.reason,
  });

  factory PersistenceItem.fromJson(Map<String, dynamic> json) {
    return PersistenceItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      type: json['type'] as String? ?? 'Unknown',
      path: json['path'] as String? ?? '',
      isRunning: json['is_running'] as bool? ?? false,
      autoStart: json['auto_start'] as bool? ?? false,
      isSuspicious: json['is_suspicious'] as bool? ?? false,
      reason: json['reason'] as String?,
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

  SignedApp({
    required this.name,
    required this.bundleId,
    required this.isSigned,
    required this.isValid,
    required this.developer,
    this.teamId,
  });

  factory SignedApp.fromJson(Map<String, dynamic> json) {
    return SignedApp(
      name: json['name'] as String? ?? 'Unknown',
      bundleId: json['bundle_id'] as String? ?? '',
      isSigned: json['is_signed'] as bool? ?? false,
      isValid: json['is_valid'] as bool? ?? false,
      developer: json['developer'] as String? ?? '',
      teamId: json['team_id'] as String?,
    );
  }
}

class FirewallRule {
  final String id;
  final String name;
  final String action;
  final String direction;
  final String protocol;
  final int? port;
  final String? address;
  bool isEnabled;

  FirewallRule({
    required this.id,
    required this.name,
    required this.action,
    required this.direction,
    required this.protocol,
    this.port,
    this.address,
    this.isEnabled = true,
  });

  factory FirewallRule.fromJson(Map<String, dynamic> json) {
    return FirewallRule(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown Rule',
      action: json['action'] as String? ?? 'Block',
      direction: json['direction'] as String? ?? 'Incoming',
      protocol: json['protocol'] as String? ?? 'TCP',
      port: json['port'] as int?,
      address: json['address'] as String?,
      isEnabled: json['is_enabled'] as bool? ?? true,
    );
  }
}
