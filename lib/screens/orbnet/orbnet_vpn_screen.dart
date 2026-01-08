/// OrbNet VPN Screen
/// VPN DNS filtering and server management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

class OrbNetVpnScreen extends StatefulWidget {
  const OrbNetVpnScreen({super.key});

  @override
  State<OrbNetVpnScreen> createState() => _OrbNetVpnScreenState();
}

class _OrbNetVpnScreenState extends State<OrbNetVpnScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _selectedServer = 'Auto';
  final List<VpnServer> _servers = [];
  final List<BlockedDomain> _blockedDomains = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.delayed(const Duration(milliseconds: 300));
    setState(() {
      _servers.addAll(_getSampleServers());
      _blockedDomains.addAll(_getSampleBlockedDomains());
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'OrbNet VPN',
      body: Column(
        children: [
          // Actions row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: DuotoneIcon(AppIcons.settings, size: 22, color: Colors.white),
                  onPressed: () => _showSettingsDialog(context),
                  tooltip: 'Settings',
                ),
              ],
            ),
          ),
          // Tab bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
              child: Container(
                decoration: GlassTheme.glassDecoration(),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: GlassTheme.primaryAccent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  tabs: const [
                    Tab(text: 'Connect'),
                    Tab(text: 'Servers'),
                    Tab(text: 'DNS Filter'),
                  ],
                ),
              ),
            ),
          ),
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildConnectTab(),
                _buildServersTab(),
                _buildDnsFilterTab(),
              ],
            ),
          ),
        ],
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
                  onPressed: () => _tabController.animateTo(1),
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
                _buildStatCard('Blocked', '127', GlassTheme.errorColor),
                const SizedBox(width: 12),
                _buildStatCard('Protected', '2.4K', GlassTheme.successColor),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatCard('Uptime', '2h 34m', GlassTheme.primaryAccent),
                const SizedBox(width: 12),
                _buildStatCard('Data', '145 MB', const Color(0xFF9C27B0)),
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
            _buildStatCard('Categories', '5', GlassTheme.primaryAccent),
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

  List<VpnServer> _getSampleServers() {
    return [
      VpnServer(name: 'US - New York', location: 'New York, USA', flag: '\u{1F1FA}\u{1F1F8}', latency: 32, load: 45),
      VpnServer(name: 'US - Los Angeles', location: 'Los Angeles, USA', flag: '\u{1F1FA}\u{1F1F8}', latency: 45, load: 62),
      VpnServer(name: 'UK - London', location: 'London, UK', flag: '\u{1F1EC}\u{1F1E7}', latency: 78, load: 38),
      VpnServer(name: 'Germany - Frankfurt', location: 'Frankfurt, DE', flag: '\u{1F1E9}\u{1F1EA}', latency: 85, load: 51),
      VpnServer(name: 'Japan - Tokyo', location: 'Tokyo, JP', flag: '\u{1F1EF}\u{1F1F5}', latency: 142, load: 28),
      VpnServer(name: 'Singapore', location: 'Singapore', flag: '\u{1F1F8}\u{1F1EC}', latency: 156, load: 35),
    ];
  }

  List<BlockedDomain> _getSampleBlockedDomains() {
    return [
      BlockedDomain(domain: 'malware-c2.evil.com', category: 'Malware', blockedAt: DateTime.now().subtract(const Duration(minutes: 5))),
      BlockedDomain(domain: 'tracking.ads.net', category: 'Tracker', blockedAt: DateTime.now().subtract(const Duration(minutes: 12))),
      BlockedDomain(domain: 'phishing-bank.com', category: 'Phishing', blockedAt: DateTime.now().subtract(const Duration(hours: 1))),
      BlockedDomain(domain: 'ad-serve.network', category: 'Ads', blockedAt: DateTime.now().subtract(const Duration(hours: 2))),
    ];
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
}
