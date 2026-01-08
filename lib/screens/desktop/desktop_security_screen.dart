/// Desktop-specific security features including persistence scanning,
/// code signing verification, and firewall management
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';

class DesktopSecurityScreen extends StatefulWidget {
  const DesktopSecurityScreen({super.key});

  @override
  State<DesktopSecurityScreen> createState() => _DesktopSecurityScreenState();
}

class _DesktopSecurityScreenState extends State<DesktopSecurityScreen> {
  bool _isScanning = false;
  final List<PersistenceItem> _persistenceItems = [];
  final List<SignedApp> _signedApps = [];
  final List<FirewallRule> _firewallRules = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() {
      _persistenceItems.addAll(_getSamplePersistenceItems());
      _signedApps.addAll(_getSampleSignedApps());
      _firewallRules.addAll(_getSampleFirewallRules());
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassTabPage(
      title: 'Desktop Security',
      headerContent: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
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
        GlassCard(
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

        // Persistence items
        const SizedBox(height: 24),
        const GlassSectionHeader(title: 'Startup Items & Services'),
        ..._persistenceItems.map((item) => _buildPersistenceCard(item)),

        // Categories info
        const SizedBox(height: 24),
        const GlassSectionHeader(title: 'Scan Coverage'),
        _buildCoverageRow('play_circle', 'Launch Agents', true),
        _buildCoverageRow('settings', 'Launch Daemons', true),
        _buildCoverageRow('user', 'Login Items', true),
        _buildCoverageRow('clock_circle', 'Scheduled Tasks', true),
        _buildCoverageRow('widget', 'Browser Extensions', true),
        _buildCoverageRow('cpu', 'Kernel Extensions', true),
      ],
    );
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
        ..._firewallRules.map((rule) => _buildFirewallRuleCard(rule)),
      ],
    );
  }

  Widget _buildQuickAction(String icon, String title, String subtitle) {
    return GlassCard(
      onTap: () {},
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

  void _runScan() {
    setState(() => _isScanning = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Persistence scan complete'),
          backgroundColor: GlassTheme.successColor,
        ),
      );
    });
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
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _persistenceItems.remove(item));
                  },
                  icon: const DuotoneIcon('trash_bin_minimalistic', size: 20),
                  label: const Text('Remove'),
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
    switch (type.toLowerCase()) {
      case 'launch agent':
        return 'play_circle';
      case 'launch daemon':
        return 'settings';
      case 'login item':
        return 'user';
      case 'scheduled task':
        return 'clock_circle';
      case 'browser extension':
        return 'widget';
      case 'kernel extension':
        return 'cpu';
      default:
        return 'code';
    }
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

  List<PersistenceItem> _getSamplePersistenceItems() {
    return [
      PersistenceItem(
        id: '1',
        name: 'com.apple.spotlight',
        type: 'Launch Agent',
        path: '/System/Library/LaunchAgents/com.apple.spotlight.plist',
        isRunning: true,
        autoStart: true,
        isSuspicious: false,
      ),
      PersistenceItem(
        id: '2',
        name: 'Google Chrome Helper',
        type: 'Login Item',
        path: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper',
        isRunning: true,
        autoStart: true,
        isSuspicious: false,
      ),
      PersistenceItem(
        id: '3',
        name: 'com.unknown.helper',
        type: 'Launch Agent',
        path: '/Users/user/Library/LaunchAgents/com.unknown.helper.plist',
        isRunning: true,
        autoStart: true,
        isSuspicious: true,
        reason: 'Unknown developer, hidden executable, network connections detected',
      ),
      PersistenceItem(
        id: '4',
        name: 'Docker Desktop',
        type: 'Login Item',
        path: '/Applications/Docker.app/Contents/MacOS/Docker Desktop',
        isRunning: false,
        autoStart: true,
        isSuspicious: false,
      ),
      PersistenceItem(
        id: '5',
        name: 'com.apple.ScreenTimeAgent',
        type: 'Launch Daemon',
        path: '/System/Library/LaunchDaemons/com.apple.ScreenTimeAgent.plist',
        isRunning: true,
        autoStart: true,
        isSuspicious: false,
      ),
    ];
  }

  List<SignedApp> _getSampleSignedApps() {
    return [
      SignedApp(
        name: 'Safari',
        bundleId: 'com.apple.Safari',
        isSigned: true,
        isValid: true,
        developer: 'Apple Inc.',
        teamId: 'APPLECOMPUTER',
      ),
      SignedApp(
        name: 'Google Chrome',
        bundleId: 'com.google.Chrome',
        isSigned: true,
        isValid: true,
        developer: 'Google LLC',
        teamId: 'EQHXZ8M8AV',
      ),
      SignedApp(
        name: 'Visual Studio Code',
        bundleId: 'com.microsoft.VSCode',
        isSigned: true,
        isValid: true,
        developer: 'Microsoft Corporation',
        teamId: 'UBF8T346G9',
      ),
      SignedApp(
        name: 'Unknown App',
        bundleId: 'com.unknown.app',
        isSigned: false,
        isValid: false,
        developer: '',
      ),
      SignedApp(
        name: 'Modified App',
        bundleId: 'com.modified.app',
        isSigned: true,
        isValid: false,
        developer: 'Unknown Developer',
      ),
      SignedApp(
        name: 'Terminal',
        bundleId: 'com.apple.Terminal',
        isSigned: true,
        isValid: true,
        developer: 'Apple Inc.',
        teamId: 'APPLECOMPUTER',
      ),
    ];
  }

  List<FirewallRule> _getSampleFirewallRules() {
    return [
      FirewallRule(
        id: '1',
        name: 'Block SSH',
        action: 'Block',
        direction: 'Incoming',
        protocol: 'TCP',
        port: 22,
      ),
      FirewallRule(
        id: '2',
        name: 'Allow HTTPS',
        action: 'Allow',
        direction: 'Outgoing',
        protocol: 'TCP',
        port: 443,
      ),
      FirewallRule(
        id: '3',
        name: 'Block Telnet',
        action: 'Block',
        direction: 'Incoming',
        protocol: 'TCP',
        port: 23,
      ),
      FirewallRule(
        id: '4',
        name: 'Allow DNS',
        action: 'Allow',
        direction: 'Outgoing',
        protocol: 'UDP',
        port: 53,
      ),
      FirewallRule(
        id: '5',
        name: 'Block Unknown IPs',
        action: 'Block',
        direction: 'Incoming',
        protocol: 'Any',
        address: '0.0.0.0/0',
        isEnabled: false,
      ),
    ];
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
}
