/// Network Security Screen
/// Main screen for network security and WiFi protection

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/network_provider.dart';
import '../../services/api/orbguard_api_client.dart';
import '../../widgets/network/network_widgets.dart';

/// Well-known public resolvers with built-in malware/phishing blocking that
/// users can configure as OS-level Private DNS. These are third-party
/// services, not operated by OrbGuard.
const List<({String name, String host, String description})>
    _privateDnsProviders = [
  (
    name: 'Quad9',
    host: 'dns.quad9.net',
    description: 'Blocks known malware and phishing domains',
  ),
  (
    name: 'Cloudflare Security',
    host: 'security.cloudflare-dns.com',
    description: 'Cloudflare 1.1.1.2 resolver with malware blocking',
  ),
];

class NetworkSecurityScreen extends StatefulWidget {
  const NetworkSecurityScreen({super.key});

  @override
  State<NetworkSecurityScreen> createState() => _NetworkSecurityScreenState();
}

class _NetworkSecurityScreenState extends State<NetworkSecurityScreen> {
  String _searchQuery = '';

  // Informational OrbVPN server list (GET /api/v1/vpn/servers).
  List<Map<String, dynamic>>? _vpnServers;
  bool _isLoadingVpnServers = false;
  String? _vpnServersError;

  @override
  void initState() {
    super.initState();
    _loadVpnServers();
  }

  Future<void> _loadVpnServers() async {
    setState(() {
      _isLoadingVpnServers = true;
      _vpnServersError = null;
    });
    try {
      final servers = await OrbGuardApiClient.instance.getVpnServers();
      if (!mounted) return;
      setState(() {
        _vpnServers = servers;
        _isLoadingVpnServers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vpnServersError = 'Failed to load server list: $e';
        _isLoadingVpnServers = false;
      });
    }
  }

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
          // Honest informational card: OrbGuard does not run a VPN tunnel.
          GlassCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D9FF).withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: DuotoneIcon('lock', size: 24, color: Color(0xFF00D9FF)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VPN protection is provided by OrbVPN',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'OrbGuard does not run a VPN tunnel itself. To encrypt '
                        'your traffic and hide your IP address, install and '
                        'connect with the separate OrbVPN app.',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Benefits section
          const Text(
            'Why use a VPN',
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
          if (!provider.isCurrentNetworkSecure) ...[
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
                          'You\'re on an unsecured network. Connect through '
                          'OrbVPN for protection.',
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
          const SizedBox(height: 24),
          // Informational OrbVPN server list (read-only).
          const Text(
            'OrbVPN Server Network',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildVpnServerList(),
        ],
      ),
    );
  }

  Widget _buildVpnServerList() {
    if (_isLoadingVpnServers) {
      return const GlassCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF00D9FF),
            ),
          ),
        ),
      );
    }

    if (_vpnServersError != null) {
      return GlassCard(
        child: Column(
          children: [
            Text(
              _vpnServersError!,
              style: TextStyle(color: Colors.red[300], fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadVpnServers,
              child: const Text(
                'Retry',
                style: TextStyle(color: Color(0xFF00D9FF)),
              ),
            ),
          ],
        ),
      );
    }

    final servers = _vpnServers ?? const [];
    if (servers.isEmpty) {
      return GlassCard(
        child: Center(
          child: Text(
            'No VPN servers are currently published.',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ),
      );
    }

    return Column(
      children: servers.map((server) {
        final name = server['name'] as String? ?? 'Unknown server';
        final location = server['location'] as String? ??
            server['region'] as String? ??
            '';
        final status = server['status'] as String?;
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const DuotoneIcon('server', size: 20, color: Color(0xFF00D9FF)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (location.isNotEmpty)
                      Text(
                        location,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (status != null && status.isNotEmpty)
                Text(
                  status,
                  style: TextStyle(
                    color: status.toLowerCase() == 'online' ||
                            status.toLowerCase() == 'active'
                        ? Colors.green
                        : Colors.grey[500],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        );
      }).toList(),
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
          // Honest guidance card: DNS filtering is configured at the OS level.
          GlassCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D9FF).withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child:
                        DuotoneIcon('server', size: 24, color: Color(0xFF00D9FF)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Secure DNS is set up in your device settings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'OrbGuard does not change your device DNS. You can '
                        'enable encrypted, threat-blocking DNS at the '
                        'operating-system level using the steps below.',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // DNS hijack check: real client-side canary resolution verified by
          // the backend against known-good answer sets.
          const Text(
            'DNS Security Check',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Resolves well-known canary domains through this device\'s DNS '
            'resolver and verifies the answers against known-good records.',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  provider.isCheckingDns ? null : () => provider.runDnsCheck(),
              icon: provider.isCheckingDns
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const DuotoneIcon('shield_check', size: 20),
              label: Text(provider.isCheckingDns
                  ? 'Checking DNS...'
                  : 'Run DNS Hijack Check'),
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
          if (provider.dnsCheckError != null) ...[
            const SizedBox(height: 12),
            GlassCard(
              child: Row(
                children: [
                  const DuotoneIcon('danger_circle', size: 20, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      provider.dnsCheckError!,
                      style: TextStyle(color: Colors.red[300], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (provider.dnsCheckResult != null) ...[
            const SizedBox(height: 12),
            _buildDnsCheckResultCard(provider.dnsCheckResult!),
          ],
          const SizedBox(height: 24),
          const Text(
            'How to Enable Private DNS',
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
                  'Android',
                  'Open Settings > Network & internet > Private DNS, choose '
                      '"Private DNS provider hostname" and paste a hostname '
                      'from the list below.',
                ),
                _buildDnsInfoRow(
                  '2',
                  'iOS / macOS',
                  'Secure DNS on Apple devices is configured through a DNS '
                      'configuration profile from your chosen DNS provider.',
                ),
                _buildDnsInfoRow(
                  '3',
                  'What it does',
                  'DNS queries are encrypted and known malware or phishing '
                      'domains are blocked by the resolver before they load.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Threat-Blocking DNS Providers',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Independent public resolvers (not operated by OrbGuard). '
            'Tap to copy the hostname.',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          const SizedBox(height: 12),
          ..._privateDnsProviders.map(
            (p) => _buildDnsProviderCard(p.name, p.host, p.description),
          ),
        ],
      ),
    );
  }

  /// Renders the verified DNS check result, distinguishing three states
  /// honestly: hijack check performed, hijack check not run, and the leak
  /// check (explicitly unavailable — no controlled canary domain deployed).
  Widget _buildDnsCheckResultCard(DnsCheckResult result) {
    final hijackColor = !result.hijackCheckPerformed
        ? Colors.grey
        : result.isHijacked
            ? Colors.red
            : Colors.green;

    String statusDetail(String status) {
      final idx = status.indexOf(':');
      return idx >= 0 ? status.substring(idx + 1).trim() : status;
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hijack verdict
          Row(
            children: [
              DuotoneIcon(
                !result.hijackCheckPerformed
                    ? 'info_circle'
                    : result.isHijacked
                        ? 'danger_triangle'
                        : 'shield_check',
                size: 24,
                color: hijackColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      !result.hijackCheckPerformed
                          ? 'Hijack check not performed'
                          : result.isHijacked
                              ? 'DNS hijacking detected'
                              : 'No DNS hijacking detected',
                      style: TextStyle(
                        color: hijackColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      !result.hijackCheckPerformed
                          ? statusDetail(result.hijackCheckStatus)
                          : result.hijackDescription ??
                              statusDetail(result.hijackCheckStatus),
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (result.hijackCheckPerformed && result.hijackConfidence != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Confidence: ${(result.hijackConfidence! * 100).toInt()}%',
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ),
          if (result.providerName != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Resolver provider: ${result.providerName}',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ),
          if (result.issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...result.issues.map((issue) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DuotoneIcon('danger_triangle',
                          size: 14, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          issue,
                          style: TextStyle(
                              color: Colors.orange[300], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          // Leak check — explicitly unavailable, never fabricated.
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DuotoneIcon('info_circle', size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.leakCheckUnavailable
                        ? 'DNS leak check unavailable: '
                            '${statusDetail(result.leakCheckStatus)}'
                        : 'Leak check: ${result.leakCheckStatus}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          // What this device actually measured.
          if (result.canaryResolutions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Measured on this device',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ...result.canaryResolutions.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    r.lookupError != null
                        ? '${r.canary} → lookup failed (${r.lookupError})'
                        : '${r.canary} → ${r.resolvedIps.join(', ')}',
                    style: TextStyle(
                      color: r.lookupError != null
                          ? Colors.orange[300]
                          : Colors.grey[500],
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                )),
          ],
          if (result.resolverHint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Resolver: ${result.resolverHint}',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDnsProviderCard(String name, String host, String description) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const DuotoneIcon('server', size: 20, color: Color(0xFF00D9FF)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  host,
                  style: const TextStyle(
                    color: Color(0xFF00D9FF),
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
            tooltip: 'Copy hostname',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: host));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied $host to clipboard')),
              );
            },
          ),
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
                  provider.isCurrentNetworkSecure,
                  'Connect to secured networks only',
                  'lock',
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

}
