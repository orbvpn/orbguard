/// Network Firewall Screen
/// Network connection monitoring and blocking

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../providers/network_firewall_provider.dart';
import '../../services/security/network_firewall_service.dart';

class NetworkFirewallScreen extends StatefulWidget {
  const NetworkFirewallScreen({super.key});

  @override
  State<NetworkFirewallScreen> createState() => _NetworkFirewallScreenState();
}

class _NetworkFirewallScreenState extends State<NetworkFirewallScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _domainController = TextEditingController();
  final _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NetworkFirewallProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _domainController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Network Firewall',
        showBackButton: true,
        actions: [
          Consumer<NetworkFirewallProvider>(
            builder: (context, provider, _) => GlassAppBarAction(
              icon: provider.isEnabled ? Icons.shield : Icons.shield_outlined,
              onTap: () {
                HapticFeedback.mediumImpact();
                provider.toggle();
              },
            ),
          ),
        ],
      ),
      body: Consumer<NetworkFirewallProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
            );
          }

          return Column(
            children: [
              // Status card
              _buildStatusCard(provider),
              const SizedBox(height: 16),
              // Stats row
              _buildStatsRow(provider),
              const SizedBox(height: 16),
              // Tab bar
              _buildTabBar(),
              const SizedBox(height: 16),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildConnectionsTab(provider),
                    _buildAlertsTab(provider),
                    _buildRulesTab(provider),
                    _buildAppsTab(provider),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(NetworkFirewallProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (provider.isEnabled
                        ? GlassTheme.successColor
                        : Colors.grey)
                    .withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                provider.isEnabled ? Icons.shield : Icons.shield_outlined,
                color: provider.isEnabled ? GlassTheme.successColor : Colors.grey,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.isEnabled ? 'Firewall Active' : 'Firewall Disabled',
                    style: TextStyle(
                      color: provider.isEnabled
                          ? GlassTheme.successColor
                          : Colors.grey,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider.isEnabled
                        ? 'Monitoring network connections'
                        : 'Tap shield icon to enable',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: provider.isEnabled,
              onChanged: (_) => provider.toggle(),
              activeColor: GlassTheme.successColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(NetworkFirewallProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildStatCard(
            'Blocked',
            provider.stats.blockedConnections.toString(),
            Icons.block,
            GlassTheme.errorColor,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Allowed',
            provider.stats.allowedConnections.toString(),
            Icons.check_circle,
            GlassTheme.successColor,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Rules',
            provider.stats.activeRules.toString(),
            Icons.rule,
            GlassTheme.primaryAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: GlassCard(
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
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

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: GlassTheme.glassDecoration(),
            child: TabBar(
              controller: _tabController,
              indicatorColor: GlassTheme.primaryAccent,
              labelColor: GlassTheme.primaryAccent,
              unselectedLabelColor: Colors.white54,
              isScrollable: true,
              tabs: const [
                Tab(icon: Icon(Icons.swap_vert), text: 'Live'),
                Tab(icon: Icon(Icons.notifications), text: 'Alerts'),
                Tab(icon: Icon(Icons.rule), text: 'Rules'),
                Tab(icon: Icon(Icons.apps), text: 'Apps'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionsTab(NetworkFirewallProvider provider) {
    if (provider.connections.isEmpty) {
      return _buildEmptyState(
        Icons.swap_vert,
        'No Connections',
        'Network activity will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: provider.connections.length,
      itemBuilder: (context, index) =>
          _buildConnectionCard(provider.connections[index]),
    );
  }

  Widget _buildConnectionCard(NetworkConnection conn) {
    final statusColor = Color(NetworkFirewallProvider.getStatusColor(conn.status));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              conn.status == ConnectionStatus.blocked
                  ? Icons.block
                  : conn.direction == ConnectionDirection.inbound
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conn.remoteDomain ?? conn.remoteAddress,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      conn.appName ?? conn.appId,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ':${conn.remotePort}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  conn.status.displayName,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${conn.timestamp.hour.toString().padLeft(2, '0')}:${conn.timestamp.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsTab(NetworkFirewallProvider provider) {
    if (provider.recentAlerts.isEmpty) {
      return _buildEmptyState(
        Icons.notifications_none,
        'No Alerts',
        'Blocked connections will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: provider.recentAlerts.length,
      itemBuilder: (context, index) =>
          _buildAlertCard(provider.recentAlerts[index], provider),
    );
  }

  Widget _buildAlertCard(NetworkConnection alert, NetworkFirewallProvider provider) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: GlassTheme.errorColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.gpp_bad,
                  color: GlassTheme.errorColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.blockReason?.displayName ?? 'Connection Blocked',
                      style: const TextStyle(
                        color: GlassTheme.errorColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      alert.appName ?? alert.appId,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatTime(alert.timestamp),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Destination',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        alert.remoteDomain ?? alert.remoteAddress,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Port',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      '${alert.remotePort}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  if (alert.remoteDomain != null) {
                    provider.unblockDomain(alert.remoteDomain!);
                  } else {
                    provider.unblockIp(alert.remoteAddress);
                  }
                },
                child: const Text(
                  'Allow',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _showBlockDetails(alert),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Details'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRulesTab(NetworkFirewallProvider provider) {
    return Column(
      children: [
        // Quick add section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _buildQuickBlockButton(
                  'Block Domain',
                  Icons.language,
                  () => _showAddBlockDialog(RuleType.domain),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickBlockButton(
                  'Block IP',
                  Icons.computer,
                  () => _showAddBlockDialog(RuleType.ip),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Rules list
        Expanded(
          child: provider.rules.isEmpty
              ? _buildEmptyState(
                  Icons.rule,
                  'No Custom Rules',
                  'Add rules to block specific domains or IPs',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: provider.rules.length,
                  itemBuilder: (context, index) =>
                      _buildRuleCard(provider.rules[index], provider),
                ),
        ),
      ],
    );
  }

  Widget _buildQuickBlockButton(String label, IconData icon, VoidCallback onTap) {
    return GlassCard(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: GlassTheme.primaryAccent, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: GlassTheme.primaryAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(FirewallRule rule, NetworkFirewallProvider provider) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (rule.action == RuleAction.block
                      ? GlassTheme.errorColor
                      : GlassTheme.successColor)
                  .withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              rule.action == RuleAction.block ? Icons.block : Icons.check,
              color: rule.action == RuleAction.block
                  ? GlassTheme.errorColor
                  : GlassTheme.successColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        rule.type.displayName,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.pattern,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Switch(
            value: rule.isEnabled,
            onChanged: (enabled) => provider.toggleRule(rule.id, enabled),
            activeColor: GlassTheme.primaryAccent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: Colors.white.withOpacity(0.4),
              size: 20,
            ),
            onPressed: () => provider.removeRule(rule.id),
          ),
        ],
      ),
    );
  }

  Widget _buildAppsTab(NetworkFirewallProvider provider) {
    if (provider.appProfiles.isEmpty) {
      return _buildEmptyState(
        Icons.apps,
        'No App Data',
        'App network profiles will appear here',
      );
    }

    final sortedApps = List<AppNetworkProfile>.from(provider.appProfiles)
      ..sort((a, b) => b.connectionCount.compareTo(a.connectionCount));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sortedApps.length,
      itemBuilder: (context, index) =>
          _buildAppProfileCard(sortedApps[index], provider),
    );
  }

  Widget _buildAppProfileCard(
      AppNetworkProfile profile, NetworkFirewallProvider provider) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (profile.isAllowed
                      ? GlassTheme.primaryAccent
                      : GlassTheme.errorColor)
                  .withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.android,
              color: GlassTheme.primaryAccent,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.appName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${profile.connectionCount} connections',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                    if (profile.blockedCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${profile.blockedCount} blocked',
                        style: const TextStyle(
                          color: GlassTheme.errorColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: Colors.white.withOpacity(0.5),
            ),
            color: GlassTheme.gradientTop,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: profile.isAllowed ? 'block' : 'allow',
                child: Row(
                  children: [
                    Icon(
                      profile.isAllowed ? Icons.block : Icons.check,
                      color: profile.isAllowed
                          ? GlassTheme.errorColor
                          : GlassTheme.successColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      profile.isAllowed ? 'Block App' : 'Allow App',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'details',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white54, size: 18),
                    SizedBox(width: 8),
                    Text('View Details', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'block') {
                provider.blockApp(profile.appId);
              } else if (value == 'allow') {
                provider.unblockApp(profile.appId);
              } else if (value == 'details') {
                _showAppDetails(profile, provider);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withOpacity(0.4)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showAddBlockDialog(RuleType type) {
    final controller = type == RuleType.domain ? _domainController : _ipController;
    controller.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Block ${type.displayName}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: type == RuleType.domain
                    ? 'e.g., malware.com'
                    : 'e.g., 192.168.1.100',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: Icon(
                  type == RuleType.domain ? Icons.language : Icons.computer,
                  color: Colors.grey,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    final provider = context.read<NetworkFirewallProvider>();
                    provider.addRule(
                      name: 'Block ${controller.text}',
                      type: type,
                      pattern: controller.text,
                      action: RuleAction.block,
                    );
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.errorColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Block',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockDetails(NetworkConnection alert) {
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
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connection Details',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildDetailRow('App', alert.appName ?? alert.appId),
            _buildDetailRow('Destination', alert.remoteDomain ?? alert.remoteAddress),
            _buildDetailRow('Port', '${alert.remotePort}'),
            _buildDetailRow('Protocol', alert.protocol.displayName),
            _buildDetailRow('Block Reason', alert.blockReason?.displayName ?? 'Unknown'),
            if (alert.country != null) _buildDetailRow('Country', alert.country!),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showAppDetails(AppNetworkProfile profile, NetworkFirewallProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: GlassTheme.primaryAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.android,
                      color: GlassTheme.primaryAccent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.appName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          profile.appId,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailRow('Total Connections', '${profile.connectionCount}'),
              _buildDetailRow('Blocked', '${profile.blockedCount}'),
              _buildDetailRow('Data In', _formatBytes(profile.bytesIn)),
              _buildDetailRow('Data Out', _formatBytes(profile.bytesOut)),
              _buildDetailRow('Unique Domains', '${profile.connectedDomains.length}'),
              if (profile.lastActivity != null)
                _buildDetailRow('Last Activity', _formatTime(profile.lastActivity!)),
              if (profile.connectedDomains.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Connected Domains',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...profile.connectedDomains.take(10).map(
                      (domain) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          domain,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
