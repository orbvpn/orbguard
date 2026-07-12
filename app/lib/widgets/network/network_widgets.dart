/// Network Widgets
/// Reusable widgets for network security screens

import 'package:flutter/material.dart';

import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/network_provider.dart';

/// WiFi security badge
class WifiSecurityBadge extends StatelessWidget {
  final WifiSecurityLevel security;
  final bool compact;

  const WifiSecurityBadge({
    super.key,
    required this.security,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(security.color);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 2 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(compact ? 4 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(
            security.isSecure ? AppIcons.lock : AppIcons.lockUnlocked,
            size: compact ? 12 : 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            security.displayName,
            style: TextStyle(
              color: color,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Signal strength indicator
class SignalStrengthIndicator extends StatelessWidget {
  final int strength;
  final bool showLabel;

  const SignalStrengthIndicator({
    super.key,
    required this.strength,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final bars = _getBars();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (index) {
            final isActive = index < bars;
            return Container(
              width: 4,
              height: 6 + (index * 4).toDouble(),
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: isActive ? color : Colors.grey.withAlpha(77),
                borderRadius: BorderRadius.circular(1),
              ),
            );
          }),
        ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            NetworkProvider.getSignalDescription(strength),
            style: TextStyle(
              color: color,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Color _getColor() {
    if (strength > -60) return Colors.green;
    if (strength > -70) return Colors.orange;
    return Colors.red;
  }

  int _getBars() {
    if (strength > -50) return 4;
    if (strength > -60) return 3;
    if (strength > -70) return 2;
    return 1;
  }
}

/// WiFi network card
class WifiNetworkCard extends StatelessWidget {
  final WifiNetwork network;
  final VoidCallback? onTap;

  const WifiNetworkCard({
    super.key,
    required this.network,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = network.isConnected
        ? const Color(0xFF00D9FF).withAlpha(75)
        : !network.security.isSecure
            ? Colors.red.withAlpha(75)
            : Colors.white10;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            // WiFi icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: network.isConnected
                    ? const Color(0xFF00D9FF).withAlpha(40)
                    : !network.security.isSecure
                        ? Colors.red.withAlpha(40)
                        : const Color(0xFF2A2B40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DuotoneIcon(
                network.security.isSecure ? AppIcons.wifi : AppIcons.wifi,
                color: network.isConnected
                    ? const Color(0xFF00D9FF)
                    : !network.security.isSecure
                        ? Colors.red
                        : Colors.grey,
              ),
            ),
            const SizedBox(width: 14),
            // Network info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          network.ssid.isEmpty ? '(Hidden Network)' : network.ssid,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: network.isHidden ? Colors.grey : Colors.white,
                            fontStyle:
                                network.isHidden ? FontStyle.italic : FontStyle.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (network.isConnected)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D9FF).withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Connected',
                            style: TextStyle(
                              color: Color(0xFF00D9FF),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      WifiSecurityBadge(security: network.security, compact: true),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          network.is5GHz ? '5 GHz' : '2.4 GHz',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Signal strength
            SignalStrengthIndicator(strength: network.signalStrength),
          ],
        ),
      ),
    );
  }
}

/// Network threat card
class NetworkThreatCard extends StatelessWidget {
  final NetworkThreat threat;
  final VoidCallback? onDismiss;
  final VoidCallback? onTap;

  const NetworkThreatCard({
    super.key,
    required this.threat,
    this.onDismiss,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = threat.isCritical ? Colors.red : Colors.orange;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(75)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                DuotoneIcon(
                  _getThreatIcon(),
                  color: color,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        threat.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        threat.severity.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    icon: const DuotoneIcon(AppIcons.closeCircle, size: 18, color: Colors.grey),
                    onPressed: onDismiss,
                    color: Colors.grey,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              threat.description,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
              ),
            ),
            if (threat.recommendation != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    DuotoneIcon(AppIcons.lightbulb, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        threat.recommendation!,
                        style: TextStyle(
                          color: color.withAlpha(204),
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

  String _getThreatIcon() {
    switch (threat.type) {
      case 'evil_twin':
        return AppIcons.wifiRouter;
      case 'insecure_wifi':
        return AppIcons.lockUnlocked;
      case 'mitm':
        return AppIcons.transferHorizontal;
      case 'arp_spoofing':
        return AppIcons.dangerTriangle;
      default:
        return AppIcons.shieldCheck;
    }
  }
}

/// VPN status card
class VpnStatusCard extends StatelessWidget {
  final VpnStatus status;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  const VpnStatusCard({
    super.key,
    required this.status,
    this.onConnect,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status.isConnected
              ? Colors.green.withAlpha(75)
              : Colors.white10,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // VPN icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: status.isConnected
                      ? Colors.green.withAlpha(40)
                      : Colors.grey.withAlpha(40),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: DuotoneIcon(
                  status.isConnected ? AppIcons.vpn : AppIcons.key,
                  color: status.isConnected ? Colors.green : Colors.grey,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Status info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        color: status.isConnected ? Colors.green : Colors.grey,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (status.isConnected && status.serverLocation != null)
                      Text(
                        status.serverLocation!,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                      ),
                    if (!status.isConnected)
                      Text(
                        'Your connection is not protected',
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
          if (status.isConnected) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Protocol', status.protocol ?? 'N/A'),
                _buildStatItem('IP', status.serverIp ?? 'N/A'),
                _buildStatItem(
                  'Duration',
                  _formatDuration(status.connectionDuration),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: status.isConnected ? onDisconnect : onConnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: status.isConnected
                    ? Colors.red.withAlpha(40)
                    : const Color(0xFF00D9FF),
                foregroundColor: status.isConnected ? Colors.red : Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                status.isConnected ? 'Disconnect' : 'Connect to VPN',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'N/A';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

/// DNS protection card
class DnsProtectionCard extends StatelessWidget {
  final DnsProtectionStatus status;
  final VoidCallback? onToggle;
  final VoidCallback? onSettings;

  const DnsProtectionCard({
    super.key,
    required this.status,
    this.onToggle,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: status.isEnabled
                      ? const Color(0xFF00D9FF).withAlpha(40)
                      : Colors.grey.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DuotoneIcon(
                  AppIcons.server,
                  color: status.isEnabled ? const Color(0xFF00D9FF) : Colors.grey,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DNS Protection',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      status.isEnabled ? status.provider : 'Not Configured',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: status.isEnabled,
                onChanged: (_) => onToggle?.call(),
                activeColor: const Color(0xFF00D9FF),
              ),
            ],
          ),
          if (status.isEnabled) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildFeatureChip(
                    'Malware',
                    status.isMalwareBlocking,
                    AppIcons.bug,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFeatureChip(
                    'Ads',
                    status.isAdBlocking,
                    AppIcons.forbidden,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildFeatureChip(
                    'Trackers',
                    status.isTrackingBlocking,
                    AppIcons.radar,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2B40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const DuotoneIcon(AppIcons.shield, size: 18, color: Color(0xFF00D9FF)),
                  const SizedBox(width: 10),
                  Text(
                    '${status.blockedQueries} threats blocked',
                    style: const TextStyle(
                      color: Color(0xFF00D9FF),
                      fontWeight: FontWeight.w500,
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

  Widget _buildFeatureChip(String label, bool enabled, String icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: enabled
            ? Colors.green.withAlpha(30)
            : Colors.grey.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(
            icon,
            size: 14,
            color: enabled ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.green : Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Network stats card
class NetworkStatsCard extends StatelessWidget {
  final NetworkSecurityStats stats;

  const NetworkStatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Network Security',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Scans',
                  stats.totalScans.toString(),
                  AppIcons.radar,
                  const Color(0xFF00D9FF),
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Threats',
                  stats.threatsDetected.toString(),
                  AppIcons.dangerTriangle,
                  stats.threatsDetected > 0 ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Open Networks',
                  stats.openNetworksFound.toString(),
                  AppIcons.lockUnlocked,
                  Colors.orange,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'DNS Blocked',
                  stats.dnsQueriesBlocked.toString(),
                  AppIcons.shield,
                  Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, String icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          DuotoneIcon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Current network status card
class CurrentNetworkCard extends StatelessWidget {
  final WifiNetwork? network;
  final VoidCallback? onScan;

  const CurrentNetworkCard({
    super.key,
    required this.network,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    if (network == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            DuotoneIcon(
              AppIcons.wifi,
              size: 48,
              color: Colors.grey.withAlpha(128),
            ),
            const SizedBox(height: 12),
            const Text(
              'Not Connected',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            Text(
              'Connect to a WiFi network',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: network!.security.isSecure
              ? Colors.green.withAlpha(75)
              : Colors.red.withAlpha(75),
        ),
      ),
      child: Column(
        children: [
          // Network icon and name
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: network!.security.isSecure
                      ? Colors.green.withAlpha(40)
                      : Colors.red.withAlpha(40),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: DuotoneIcon(
                  network!.security.isSecure ? AppIcons.wifi : AppIcons.wifi,
                  color: network!.security.isSecure ? Colors.green : Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      network!.ssid,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    WifiSecurityBadge(security: network!.security),
                  ],
                ),
              ),
              SignalStrengthIndicator(strength: network!.signalStrength),
            ],
          ),
          const SizedBox(height: 16),
          // Network details
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2B40),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDetailItem('Frequency', network!.is5GHz ? '5 GHz' : '2.4 GHz'),
                _buildDetailItem('Signal', '${network!.signalStrength} dBm'),
                _buildDetailItem('BSSID', _formatBssid(network!.bssid)),
              ],
            ),
          ),
          if (!network!.security.isSecure) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const DuotoneIcon(AppIcons.dangerTriangle, color: Colors.red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This network is not secure. Use a VPN for protection.',
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
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  String _formatBssid(String bssid) {
    if (bssid.length > 8) {
      return '${bssid.substring(0, 8)}...';
    }
    return bssid;
  }
}
