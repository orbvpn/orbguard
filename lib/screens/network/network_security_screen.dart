/// Network Security Screen
/// Main screen for network security and WiFi protection

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/network_provider.dart';
import '../../widgets/network/network_widgets.dart';

class NetworkSecurityScreen extends StatefulWidget {
  const NetworkSecurityScreen({super.key});

  @override
  State<NetworkSecurityScreen> createState() => _NetworkSecurityScreenState();
}

class _NetworkSecurityScreenState extends State<NetworkSecurityScreen> {
  String _searchQuery = '';

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkProvider>(
      builder: (context, provider, child) {
        return GlassTabPage(
          title: 'Network Security',
          hasSearch: true,
          searchHint: 'Search networks...',
          onSearchChanged: _onSearchChanged,
          headerContent: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
                  onPressed: () {
                    provider.refreshNetworkInfo();
                    provider.scanNetworks();
                  },
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          tabs: [
            GlassTab(
              label: 'WiFi',
              iconPath: 'wi_fi_router',
              content: _buildWifiTab(provider),
            ),
            GlassTab(
              label: 'VPN',
              iconPath: 'lock',
              content: _buildVpnTab(provider),
            ),
            GlassTab(
              label: 'DNS',
              iconPath: 'server',
              content: _buildDnsTab(provider),
            ),
            GlassTab(
              label: 'Stats',
              iconPath: 'chart',
              content: _buildStatsTab(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWifiTab(NetworkProvider provider) {
    // Filter networks based on search query
    final filteredNetworks = _searchQuery.isEmpty
        ? provider.nearbyNetworks
        : provider.nearbyNetworks
            .where((n) => n.ssid.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current network
          CurrentNetworkCard(
            network: provider.currentNetwork,
            onScan: () => provider.scanNetworks(),
          ),
          // Threats
          if (provider.activeThreats.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const DuotoneIcon('danger_triangle', size: 20, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Active Threats (${provider.activeThreats.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...provider.activeThreats.map((threat) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NetworkThreatCard(
                    threat: threat,
                    onDismiss: () => provider.dismissThreat(threat.id),
                  ),
                )),
          ],
          // Scan button
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: provider.isScanning ? null : () => provider.scanNetworks(),
              icon: provider.isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const DuotoneIcon('wi_fi_router', size: 24),
              label: Text(provider.isScanning ? 'Scanning...' : 'Scan Networks'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D9FF),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          // Nearby networks
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _searchQuery.isEmpty ? 'Nearby Networks' : 'Search Results',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${filteredNetworks.where((n) => !n.isConnected).length} found',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredNetworks.where((n) => !n.isConnected).isEmpty)
            GlassCard(
              child: Center(
                child: Column(
                  children: [
                    DuotoneIcon(
                      'wi_fi_router',
                      size: 48,
                      color: Colors.grey.withAlpha(77),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _searchQuery.isEmpty ? 'No networks found' : 'No matching networks',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _searchQuery.isEmpty
                          ? 'Tap scan to search for nearby networks'
                          : 'Try a different search term',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filteredNetworks
                .where((n) => !n.isConnected)
                .map((network) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: WifiNetworkCard(
                        network: network,
                        onTap: () => _showNetworkDetails(context, network),
                      ),
                    )),
        ],
      ),
    );
  }

  Widget _buildVpnTab(NetworkProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // VPN status card
          VpnStatusCard(
            status: provider.vpnStatus,
            onConnect: () => _showVpnServerSelector(context, provider),
            onDisconnect: () => provider.disconnectVpn(),
          ),
          const SizedBox(height: 24),
          // Benefits section
          const Text(
            'VPN Protection Benefits',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildBenefitItem(
            'lock',
            'Encrypted Connection',
            'All your internet traffic is encrypted end-to-end',
          ),
          _buildBenefitItem(
            'eye_closed',
            'Hide IP Address',
            'Your real IP address is hidden from websites',
          ),
          _buildBenefitItem(
            'wi_fi_router',
            'Secure on Public WiFi',
            'Stay protected on unsecured networks',
          ),
          _buildBenefitItem(
            'globe',
            'Access Global Content',
            'Access content from anywhere in the world',
          ),
          if (!provider.vpnStatus.isConnected &&
              !provider.isCurrentNetworkSecure) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withAlpha(75)),
              ),
              child: Row(
                children: [
                  const DuotoneIcon('danger_triangle', size: 24, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'VPN Recommended',
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'You\'re on an unsecured network. Enable VPN for protection.',
                          style: TextStyle(
                            color: Colors.orange[300],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBenefitItem(String iconName, String title, String description) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF00D9FF).withAlpha(40),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: DuotoneIcon(iconName, size: 20, color: const Color(0xFF00D9FF)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDnsTab(NetworkProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // DNS protection card
          DnsProtectionCard(
            status: provider.dnsStatus,
            onToggle: () {
              if (provider.dnsStatus.isEnabled) {
                provider.disableDnsProtection();
              } else {
                _showDnsSettings(context, provider);
              }
            },
          ),
          const SizedBox(height: 24),
          // What DNS protection does
          const Text(
            'How DNS Protection Works',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              children: [
                _buildDnsInfoRow(
                  '1',
                  'Intercepts DNS Queries',
                  'When you visit a website, DNS Protection checks the request',
                ),
                _buildDnsInfoRow(
                  '2',
                  'Blocks Malicious Sites',
                  'Known malware and phishing domains are blocked automatically',
                ),
                _buildDnsInfoRow(
                  '3',
                  'Filters Trackers',
                  'Stops trackers from following you across the web',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // DNS servers info
          if (provider.dnsStatus.isEnabled) ...[
            const Text(
              'Current DNS Servers',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildDnsServerCard('Primary', provider.dnsStatus.primaryDns),
            if (provider.dnsStatus.secondaryDns != null)
              _buildDnsServerCard('Secondary', provider.dnsStatus.secondaryDns!),
          ],
        ],
      ),
    );
  }

  Widget _buildDnsInfoRow(String number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF00D9FF).withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Color(0xFF00D9FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDnsServerCard(String label, String server) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const DuotoneIcon('server', size: 20, color: Color(0xFF00D9FF)),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
              ),
              Text(
                server,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsTab(NetworkProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          NetworkStatsCard(stats: provider.stats),
          const SizedBox(height: 24),
          // Connection history / scan history could go here
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Security Recommendations',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildRecommendation(
                  provider.vpnStatus.isConnected,
                  'Use VPN on public networks',
                  'lock',
                ),
                _buildRecommendation(
                  provider.dnsStatus.isEnabled,
                  'Enable DNS protection',
                  'server',
                ),
                _buildRecommendation(
                  provider.currentNetwork?.security.isRecommended ?? false,
                  'Use WPA2 or WPA3 encryption',
                  'lock',
                ),
                _buildRecommendation(
                  provider.activeThreats.isEmpty,
                  'No active network threats',
                  'shield_check',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendation(bool isComplete, String text, String iconName) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isComplete
                  ? Colors.green.withAlpha(40)
                  : Colors.grey.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: isComplete
                  ? const DuotoneIcon('check_circle', size: 18, color: Colors.green)
                  : DuotoneIcon(iconName, size: 18, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              color: isComplete ? Colors.green : Colors.grey[400],
              fontSize: 13,
              decoration: isComplete ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  void _showNetworkDetails(BuildContext context, WifiNetwork network) {
    showModalBottomSheet(
      context: context,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Network name
            Text(
              network.ssid.isEmpty ? '(Hidden Network)' : network.ssid,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Details
            _buildDetailRow('Security', network.security.displayName),
            _buildDetailRow('Signal Strength', '${network.signalStrength} dBm'),
            _buildDetailRow('Frequency', network.is5GHz ? '5 GHz' : '2.4 GHz'),
            _buildDetailRow('BSSID', network.bssid),
            if (!network.security.isSecure) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const DuotoneIcon('danger_triangle', size: 18, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This network is not secure. Avoid transmitting sensitive data.',
                        style: TextStyle(
                          color: Colors.red[300],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showVpnServerSelector(BuildContext context, NetworkProvider provider) {
    final servers = [
      ('United States', 'us'),
      ('United Kingdom', 'uk'),
      ('Germany', 'de'),
      ('Japan', 'jp'),
      ('Australia', 'au'),
      ('Canada', 'ca'),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Select VPN Server',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...servers.map((server) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2B40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      server.$2.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  server.$1,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  provider.connectVpn(server.$1);
                },
              )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showDnsSettings(BuildContext context, NetworkProvider provider) {
    bool malware = true;
    bool ads = false;
    bool tracking = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'DNS Protection Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text('Block Malware'),
                subtitle: const Text('Block known malicious domains'),
                value: malware,
                onChanged: (v) => setState(() => malware = v),
                activeColor: const Color(0xFF00D9FF),
              ),
              SwitchListTile(
                title: const Text('Block Ads'),
                subtitle: const Text('Block advertising domains'),
                value: ads,
                onChanged: (v) => setState(() => ads = v),
                activeColor: const Color(0xFF00D9FF),
              ),
              SwitchListTile(
                title: const Text('Block Trackers'),
                subtitle: const Text('Block tracking and analytics'),
                value: tracking,
                onChanged: (v) => setState(() => tracking = v),
                activeColor: const Color(0xFF00D9FF),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    provider.enableDnsProtection(
                      malwareBlocking: malware,
                      adBlocking: ads,
                      trackingBlocking: tracking,
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D9FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Enable DNS Protection',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
