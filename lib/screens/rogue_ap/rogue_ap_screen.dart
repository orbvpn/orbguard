/// Rogue AP Detection Screen
/// Detects and monitors rogue access points and WiFi threats

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/rogue_ap_provider.dart';

class RogueAPScreen extends StatefulWidget {
  const RogueAPScreen({super.key});

  @override
  State<RogueAPScreen> createState() => _RogueAPScreenState();
}

class _RogueAPScreenState extends State<RogueAPScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RogueAPProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RogueAPProvider>(
      builder: (context, provider, _) {
        return GlassPage(
          title: 'Rogue AP Detection',
          body: Column(
            children: [
              // Actions row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (provider.isScanning)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: GlassTheme.primaryAccent,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
                        onPressed: () => provider.scanForAPs(),
                        tooltip: 'Scan',
                      ),
                    IconButton(
                      icon: const DuotoneIcon('settings', size: 22, color: Colors.white),
                      onPressed: () => _showSettings(context, provider),
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
                        Tab(text: 'Nearby APs'),
                        Tab(text: 'Threats'),
                        Tab(text: 'Trusted'),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: provider.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: GlassTheme.primaryAccent,
                        ),
                      )
                    : Column(
                        children: [
                          // Scan progress
                          if (provider.isScanning) _buildScanProgress(provider),
                          // Current connection status
                          if (provider.currentConnection != null && !provider.isScanning)
                            _buildCurrentConnection(provider),
                          // Stats summary
                          if (!provider.isScanning) _buildStats(provider),
                          // Tab content
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                _buildNearbyAPsTab(provider),
                                _buildThreatsTab(provider),
                                _buildTrustedTab(provider),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScanProgress(RogueAPProvider provider) {
    return GlassContainer(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GlassTheme.primaryAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  provider.scanStatus,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              Text(
                '${(provider.scanProgress * 100).toInt()}%',
                style: const TextStyle(
                  color: GlassTheme.primaryAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: provider.scanProgress,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(
                GlassTheme.primaryAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentConnection(RogueAPProvider provider) {
    final ap = provider.currentConnection!;
    return GlassContainer(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Color(ap.threatLevel.color).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: DuotoneIcon(
                'wi_fi_router_round',
                size: 24,
                color: Color(ap.threatLevel.color),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Connected to: ${ap.ssid}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Color(ap.threatLevel.color).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        ap.threatLevel.displayName,
                        style: TextStyle(
                          color: Color(ap.threatLevel.color),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${ap.security.displayName} • Channel ${ap.channel} • ${RogueAPProvider.getSignalDescription(ap.signalStrength)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          DuotoneIcon(
            _getSignalIconName(ap.signalStrength),
            size: 24,
            color: GlassTheme.primaryAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildStats(RogueAPProvider provider) {
    final stats = provider.stats;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildStatItem(
            'Total',
            stats.totalAPs.toString(),
            GlassTheme.primaryAccent,
          ),
          _buildStatItem(
            'Rogue',
            stats.rogueAPs.toString(),
            GlassTheme.errorColor,
          ),
          _buildStatItem(
            'Suspicious',
            stats.suspiciousAPs.toString(),
            GlassTheme.warningColor,
          ),
          _buildStatItem(
            'Safe',
            stats.safeAPs.toString(),
            GlassTheme.successColor,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyAPsTab(RogueAPProvider provider) {
    if (provider.detectedAPs.isEmpty) {
      return _buildEmptyState(
        icon: 'radar',
        title: 'No Access Points Found',
        subtitle: 'Tap scan to detect nearby WiFi networks',
      );
    }

    // Sort by signal strength
    final sortedAPs = List<DetectedAP>.from(provider.detectedAPs)
      ..sort((a, b) => b.signalStrength.compareTo(a.signalStrength));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedAPs.length,
      itemBuilder: (context, index) {
        return _buildAPCard(sortedAPs[index], provider);
      },
    );
  }

  Widget _buildThreatsTab(RogueAPProvider provider) {
    final threats = provider.detectedAPs
        .where((ap) =>
            ap.threatLevel == APThreatLevel.dangerous ||
            ap.threatLevel == APThreatLevel.suspicious)
        .toList();

    if (threats.isEmpty) {
      return _buildEmptyState(
        icon: 'shield_check',
        title: 'No Threats Detected',
        subtitle: 'Your WiFi environment appears safe',
        color: GlassTheme.successColor,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: threats.length,
      itemBuilder: (context, index) {
        return _buildThreatCard(threats[index], provider);
      },
    );
  }

  Widget _buildTrustedTab(RogueAPProvider provider) {
    if (provider.trustedAPs.isEmpty) {
      return _buildEmptyState(
        icon: 'verified_check',
        title: 'No Trusted Networks',
        subtitle: 'Add networks you trust to whitelist them',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.trustedAPs.length,
      itemBuilder: (context, index) {
        return _buildTrustedCard(provider.trustedAPs[index], provider);
      },
    );
  }

  Widget _buildAPCard(DetectedAP ap, RogueAPProvider provider) {
    final isTrusted = provider.isTrusted(ap);

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showAPDetails(context, ap, provider),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Color(ap.threatLevel.color).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: DuotoneIcon(
                        _getSignalIconName(ap.signalStrength),
                        size: 24,
                        color: Color(ap.threatLevel.color),
                      ),
                    ),
                    if (ap.isConnected)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: GlassTheme.successColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: GlassTheme.gradientTop,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ap.ssid.isEmpty ? '<Hidden Network>' : ap.ssid,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isTrusted)
                          const DuotoneIcon(
                            'verified_check',
                            size: 16,
                            color: GlassTheme.primaryAccent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildSecurityBadge(ap.security),
                        const SizedBox(width: 8),
                        Text(
                          'Ch ${ap.channel}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${ap.signalStrength} dBm',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (ap.threats.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: ap.threats.take(2).map((threat) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Color(ap.threatLevel.color).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              threat.displayName,
                              style: TextStyle(
                                color: Color(ap.threatLevel.color),
                                fontSize: 10,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Color(ap.threatLevel.color).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  ap.threatLevel.displayName,
                  style: TextStyle(
                    color: Color(ap.threatLevel.color),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThreatCard(DetectedAP ap, RogueAPProvider provider) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color(ap.threatLevel.color).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      ap.threatLevel == APThreatLevel.dangerous
                          ? 'danger_circle'
                          : 'danger_triangle',
                      size: 24,
                      color: Color(ap.threatLevel.color),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ap.ssid.isEmpty ? '<Hidden Network>' : ap.ssid,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        ap.bssid,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Color(ap.threatLevel.color),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    ap.threatLevel.displayName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Detected Threats',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...ap.threats.map((threat) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      DuotoneIcon(
                        _getThreatIconName(threat),
                        size: 18,
                        color: Color(ap.threatLevel.color),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              threat.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              threat.description,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const DuotoneIcon('forbidden', size: 18),
                    label: const Text('Block'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: GlassTheme.errorColor,
                      side: const BorderSide(
                        color: GlassTheme.errorColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => provider.addTrustedAP(ap),
                    icon: const DuotoneIcon('shield_check', size: 18),
                    label: const Text('Trust'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: GlassTheme.primaryAccent,
                      side: const BorderSide(
                        color: GlassTheme.primaryAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustedCard(TrustedAP ap, RogueAPProvider provider) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: GlassTheme.primaryAccent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: DuotoneIcon(
              'verified_check',
              size: 24,
              color: GlassTheme.primaryAccent,
            ),
          ),
        ),
        title: Text(
          ap.ssid,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'Added ${_formatDate(ap.addedAt)}',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
        trailing: IconButton(
          icon: const DuotoneIcon(
            'minus_circle',
            size: 24,
            color: GlassTheme.errorColor,
          ),
          onPressed: () => _confirmRemoveTrusted(context, ap, provider),
        ),
      ),
    );
  }

  Widget _buildSecurityBadge(WiFiSecurity security) {
    final color = security.isSecure
        ? GlassTheme.successColor
        : GlassTheme.warningColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(
            security.isSecure ? 'lock' : 'lock_unlocked',
            size: 10,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            security.displayName,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
    Color color = GlassTheme.primaryAccent,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon(icon, size: 64, color: color.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _getSignalIconName(int strength) {
    // All signal strengths use the same wifi router icon
    if (strength >= -80) return 'wi_fi_router';
    return 'wi_fi_router';
  }

  String _getThreatIconName(APThreatType threat) {
    switch (threat) {
      case APThreatType.evilTwin:
        return 'copy';
      case APThreatType.fakeHotspot:
        return 'danger_circle';
      case APThreatType.sslStripping:
        return 'lock_unlocked';
      case APThreatType.deauthAttack:
        return 'wi_fi_router';
      case APThreatType.weakEncryption:
        return 'lock_unlocked';
      case APThreatType.openNetwork:
        return 'lock_keyhole';
      case APThreatType.suspiciousSSID:
        return 'danger_triangle';
      case APThreatType.macSpoofing:
        return 'devices';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showAPDetails(
    BuildContext context,
    DetectedAP ap,
    RogueAPProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              GlassTheme.gradientTop,
              GlassTheme.gradientBottom,
            ],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Color(ap.threatLevel.color).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      _getSignalIconName(ap.signalStrength),
                      size: 28,
                      color: Color(ap.threatLevel.color),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ap.ssid.isEmpty ? '<Hidden Network>' : ap.ssid,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        ap.bssid,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDetailRow('Security', ap.security.displayName),
            _buildDetailRow('Channel', ap.channel.toString()),
            _buildDetailRow(
              'Signal',
              '${ap.signalStrength} dBm (${RogueAPProvider.getSignalDescription(ap.signalStrength)})',
            ),
            _buildDetailRow('Vendor', ap.vendor ?? 'Unknown'),
            _buildDetailRow('Threat Level', ap.threatLevel.displayName),
            if (ap.threats.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Detected Threats',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ap.threats.map((threat) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Color(ap.threatLevel.color).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      threat.displayName,
                      style: TextStyle(
                        color: Color(ap.threatLevel.color),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (!provider.isTrusted(ap))
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        provider.addTrustedAP(ap);
                        Navigator.pop(context);
                      },
                      icon: const DuotoneIcon('shield_check', size: 20),
                      label: const Text('Add to Trusted'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GlassTheme.primaryAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const DuotoneIcon('verified_check', size: 20),
                      label: const Text('Already Trusted'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GlassTheme.successColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
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

  void _showSettings(BuildContext context, RogueAPProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              GlassTheme.gradientTop,
              GlassTheme.gradientBottom,
            ],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Protection Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _buildSettingSwitch(
              'Auto Protection',
              'Automatically enable VPN when threats detected',
              provider.autoProtect,
              (value) => provider.updateSettings(autoProtect: value),
            ),
            _buildSettingSwitch(
              'Rogue AP Alerts',
              'Notify when dangerous networks are found',
              provider.alertOnRogue,
              (value) => provider.updateSettings(alertOnRogue: value),
            ),
            _buildSettingSwitch(
              'Open Network Alerts',
              'Warn about unencrypted networks',
              provider.alertOnOpen,
              (value) => provider.updateSettings(alertOnOpen: value),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingSwitch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: GlassTheme.primaryAccent,
          ),
        ],
      ),
    );
  }

  void _confirmRemoveTrusted(
    BuildContext context,
    TrustedAP ap,
    RogueAPProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text(
          'Remove Trusted Network?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove "${ap.ssid}" from your trusted networks?',
          style: TextStyle(color: Colors.white.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.removeTrustedAP(ap.id);
              Navigator.pop(context);
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: GlassTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}
