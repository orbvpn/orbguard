/// OrbNet VPN Screen
/// VPN DNS filtering and server management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../services/api/orbguard_api_client.dart';

class OrbNetVpnScreen extends StatefulWidget {
  const OrbNetVpnScreen({super.key});

  @override
  State<OrbNetVpnScreen> createState() => _OrbNetVpnScreenState();
}

class _OrbNetVpnScreenState extends State<OrbNetVpnScreen> {
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isLoading = true;
  String? _error;
  String _selectedServer = 'Auto';
  final List<VpnServer> _servers = [];
  final List<BlockedDomain> _blockedDomains = [];
  final GlobalKey<GlassTabPageState> _tabPageKey = GlobalKey<GlassTabPageState>();

  // VPN stats
  int _blockedCount = 0;
  int _protectedCount = 0;
  String _uptime = '0m';
  String _dataUsage = '0 MB';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = OrbGuardApiClient.instance;
      final results = await Future.wait([
        api.getVpnServers(),
        api.getVpnBlockedDomains(),
        api.getVpnStats(),
      ]);

      final serversData = results[0] as List<Map<String, dynamic>>;
      final blockedDomainsData = results[1] as List<Map<String, dynamic>>;
      final statsData = results[2] as Map<String, dynamic>;

      setState(() {
        _servers.clear();
        _servers.addAll(serversData.map((data) => VpnServer.fromJson(data)));

        _blockedDomains.clear();
        _blockedDomains.addAll(blockedDomainsData.map((data) => BlockedDomain.fromJson(data)));

        // Parse VPN stats
        _blockedCount = statsData['blocked_count'] as int? ?? _blockedDomains.length;
        _protectedCount = statsData['protected_count'] as int? ?? 0;
        _uptime = statsData['uptime'] as String? ?? '0m';
        _dataUsage = statsData['data_usage'] as String? ?? '0 MB';

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    return GlassTabPage(
      key: _tabPageKey,
      title: 'OrbNet VPN',
      tabs: [
        GlassTab(
          label: 'Connect',
          iconPath: 'lock',
          content: _buildConnectTab(),
        ),
        GlassTab(
          label: 'Servers',
          iconPath: 'server',
          content: _buildServersTab(),
        ),
        GlassTab(
          label: 'DNS Filter',
          iconPath: 'shield',
          content: _buildDnsFilterTab(),
        ),
      ],
      actions: [
        IconButton(
          icon: DuotoneIcon(AppIcons.settings, size: 22, color: Colors.white),
          onPressed: () => _showSettingsDialog(context),
          tooltip: 'Settings',
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('OrbNet VPN', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('OrbNet VPN', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DuotoneIcon(AppIcons.dangerCircle, size: 64, color: GlassTheme.errorColor),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load VPN data',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? 'Unknown error',
                  style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GlassTheme.primaryAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Connection status
          GlassCard(
            tintColor: _isConnected ? GlassTheme.successColor : null,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _isConnecting ? null : _toggleConnection,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isConnected ? GlassTheme.successColor : GlassTheme.primaryAccent,
                        width: 4,
                      ),
                      color: (_isConnected ? GlassTheme.successColor : GlassTheme.primaryAccent).withAlpha(40),
                    ),
                    child: Center(
                      child: _isConnecting
                          ? const CircularProgressIndicator(color: GlassTheme.primaryAccent)
                          : DuotoneIcon(
                              AppIcons.power,
                              size: 64,
                              color: _isConnected ? GlassTheme.successColor : GlassTheme.primaryAccent,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    color: _isConnected ? GlassTheme.successColor : Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isConnected ? 'Your traffic is protected' : 'Tap to connect',
                  style: TextStyle(color: Colors.white.withAlpha(153)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Server selection
          GlassCard(
            child: Row(
              children: [
                GlassSvgIconBox(icon: AppIcons.server, color: GlassTheme.primaryAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Server', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      Text(_selectedServer, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _tabPageKey.currentState?.animateToTab(1),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),

          // Stats when connected
          if (_isConnected) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                _buildStatCard('Blocked', _formatCount(_blockedCount), GlassTheme.errorColor),
                const SizedBox(width: 12),
                _buildStatCard('Protected', _formatCount(_protectedCount), GlassTheme.successColor),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatCard('Uptime', _uptime, GlassTheme.primaryAccent),
                const SizedBox(width: 12),
                _buildStatCard('Data', _dataUsage, const Color(0xFF9C27B0)),
              ],
            ),
          ],

          // Features
          const SizedBox(height: 24),
          const GlassSectionHeader(title: 'Protection Features'),
          _buildFeatureRow(AppIcons.forbidden, 'Malware Blocking', true),
          _buildFeatureRow(AppIcons.closeCircle, 'Ad Blocking', true),
          _buildFeatureRow(AppIcons.target, 'Tracker Blocking', true),
          _buildFeatureRow(AppIcons.shieldWarning, 'Phishing Protection', true),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(String icon, String title, bool enabled) {
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(icon: icon, color: enabled ? GlassTheme.successColor : Colors.grey, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ),
          DuotoneIcon(
            enabled ? AppIcons.checkCircle : AppIcons.closeCircle,
            size: 24,
            color: enabled ? GlassTheme.successColor : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildServersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Auto selection
        GlassCard(
          onTap: () => _selectServer('Auto'),
          tintColor: _selectedServer == 'Auto' ? GlassTheme.primaryAccent : null,
          child: Row(
            children: [
              GlassSvgIconBox(
                icon: AppIcons.magic,
                color: _selectedServer == 'Auto' ? GlassTheme.primaryAccent : Colors.white54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Auto Select', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('Best server based on location', style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                  ],
                ),
              ),
              if (_selectedServer == 'Auto')
                DuotoneIcon(AppIcons.checkCircle, size: 24, color: GlassTheme.primaryAccent),
            ],
          ),
        ),

        const GlassSectionHeader(title: 'Available Servers'),
        ..._servers.map((server) => _buildServerCard(server)),
      ],
    );
  }

  Widget _buildServerCard(VpnServer server) {
    final isSelected = _selectedServer == server.name;

    return GlassCard(
      onTap: () => _selectServer(server.name),
      tintColor: isSelected ? GlassTheme.primaryAccent : null,
      child: Row(
        children: [
          Text(server.flag, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(server.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(server.location, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DuotoneIcon(
                    AppIcons.wifi,
                    size: 16,
                    color: server.latency < 50
                        ? GlassTheme.successColor
                        : server.latency < 100
                            ? GlassTheme.warningColor
                            : GlassTheme.errorColor,
                  ),
                  const SizedBox(width: 4),
                  Text('${server.latency}ms', style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 11)),
                ],
              ),
              Text('${server.load}% load', style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
            ],
          ),
          if (isSelected)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: DuotoneIcon(AppIcons.checkCircle, size: 24, color: GlassTheme.primaryAccent),
            ),
        ],
      ),
    );
  }

  Widget _buildDnsFilterTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            _buildStatCard('Blocked Today', '${_blockedDomains.length}', GlassTheme.errorColor),
            const SizedBox(width: 12),
            _buildStatCard('Categories', '${_blockedDomains.map((d) => d.category).toSet().length}', GlassTheme.primaryAccent),
          ],
        ),
        const SizedBox(height: 24),

        // Filter categories
        const GlassSectionHeader(title: 'Block Categories'),
        _buildFilterCategory('Malware', true, GlassTheme.errorColor),
        _buildFilterCategory('Phishing', true, const Color(0xFFFF5722)),
        _buildFilterCategory('Ads & Trackers', true, GlassTheme.warningColor),
        _buildFilterCategory('Adult Content', false, const Color(0xFF9C27B0)),
        _buildFilterCategory('Social Media', false, const Color(0xFF2196F3)),

        const GlassSectionHeader(title: 'Recently Blocked'),
        ..._blockedDomains.take(10).map((domain) => _buildBlockedDomainCard(domain)),
      ],
    );
  }

  Widget _buildFilterCategory(String name, bool enabled, Color color) {
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(icon: AppIcons.forbidden, color: enabled ? color : Colors.grey, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ),
          Switch(
            value: enabled,
            onChanged: (v) {},
            activeColor: color,
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedDomainCard(BlockedDomain domain) {
    return GlassCard(
      child: Row(
        children: [
          GlassSvgIconBox(icon: AppIcons.forbidden, color: GlassTheme.errorColor, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(domain.domain, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13)),
                Text(domain.category, style: TextStyle(color: GlassTheme.errorColor, fontSize: 11)),
              ],
            ),
          ),
          Text(_formatTime(domain.blockedAt), style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 11)),
        ],
      ),
    );
  }

  void _toggleConnection() {
    setState(() => _isConnecting = true);

    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _isConnecting = false;
        _isConnected = !_isConnected;
      });
    });
  }

  void _selectServer(String server) {
    setState(() => _selectedServer = server);
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('VPN Settings', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Auto-connect on startup', style: TextStyle(color: Colors.white)),
              value: true,
              onChanged: (v) {},
              activeColor: GlassTheme.primaryAccent,
            ),
            SwitchListTile(
              title: const Text('Kill switch', style: TextStyle(color: Colors.white)),
              value: true,
              onChanged: (v) {},
              activeColor: GlassTheme.primaryAccent,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

}

class VpnServer {
  final String name;
  final String location;
  final String flag;
  final int latency;
  final int load;

  VpnServer({
    required this.name,
    required this.location,
    required this.flag,
    required this.latency,
    required this.load,
  });

  factory VpnServer.fromJson(Map<String, dynamic> json) {
    return VpnServer(
      name: json['name'] as String? ?? '',
      location: json['location'] as String? ?? '',
      flag: json['flag'] as String? ?? '',
      latency: json['latency'] as int? ?? 0,
      load: json['load'] as int? ?? 0,
    );
  }
}

class BlockedDomain {
  final String domain;
  final String category;
  final DateTime blockedAt;

  BlockedDomain({
    required this.domain,
    required this.category,
    required this.blockedAt,
  });

  factory BlockedDomain.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime;
    final blockedAtValue = json['blocked_at'];
    if (blockedAtValue is String) {
      parsedTime = DateTime.tryParse(blockedAtValue) ?? DateTime.now();
    } else if (blockedAtValue is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(blockedAtValue);
    } else {
      parsedTime = DateTime.now();
    }

    return BlockedDomain(
      domain: json['domain'] as String? ?? '',
      category: json['category'] as String? ?? 'Unknown',
      blockedAt: parsedTime,
    );
  }
}
