// Network Firewall Screen
// Network connection monitoring and blocking

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/network_firewall_provider.dart';
import '../../services/security/network_firewall_service.dart';

class NetworkFirewallScreen extends StatefulWidget {
  const NetworkFirewallScreen({super.key});

  @override
  State<NetworkFirewallScreen> createState() => _NetworkFirewallScreenState();
}

class _NetworkFirewallScreenState extends State<NetworkFirewallScreen> {
  final _domainController = TextEditingController();
  final _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NetworkFirewallProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _domainController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkFirewallProvider>(
      builder: (context, provider, _) {
        final cs = Theme.of(context).colorScheme;
        return GlassTabPage(
          title: 'Network Firewall',
          tabs: [
            GlassTab(
              label: 'Live',
              iconPath: 'chart',
              content: _buildLiveContent(provider),
            ),
            GlassTab(
              label: 'Alerts',
              iconPath: 'shield',
              content: _buildAlertsContent(provider),
            ),
            GlassTab(
              label: 'Rules',
              iconPath: 'settings',
              content: _buildRulesContent(provider),
            ),
            GlassTab(
              label: 'Apps',
              iconPath: 'file',
              content: _buildAppsContent(provider),
            ),
          ],
          headerContent: Column(
            children: [
              // Actions row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: DuotoneIcon('shield_check', size: 22, color: cs.onSurface),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        provider.toggle();
                      },
                      tooltip: 'Toggle Firewall',
                    ),
                  ],
                ),
              ),
              if (!provider.isLoading) ...[
                // Status card
                _buildStatusCard(provider),
                const SizedBox(height: 16),
                // Stats row
                _buildStatsRow(provider),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLiveContent(NetworkFirewallProvider provider) {
    if (provider.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentInk),
      );
    }
    return _buildConnectionsTab(provider);
  }

  Widget _buildAlertsContent(NetworkFirewallProvider provider) {
    if (provider.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentInk),
      );
    }
    return _buildAlertsTab(provider);
  }

  Widget _buildRulesContent(NetworkFirewallProvider provider) {
    if (provider.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentInk),
      );
    }
    return _buildRulesTab(provider);
  }

  Widget _buildAppsContent(NetworkFirewallProvider provider) {
    if (provider.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accentInk),
      );
    }
    return _buildAppsTab(provider);
  }

  Widget _buildStatusCard(NetworkFirewallProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        margin: EdgeInsets.zero,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (provider.isEnabled
                        ? GlassTheme.successColor
                        : cs.onSurfaceVariant)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
              ),
              child: Center(
                child: DuotoneIcon(
                  'shield_check',
                  color: provider.isEnabled ? AppColors.accentInk : cs.onSurfaceVariant,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.isEnabled ? 'Firewall Active' : 'Firewall Disabled', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: provider.isEnabled
                          ? AppColors.accentInk
                          : cs.onSurfaceVariant,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider.isEnabled
                        ? 'Monitoring network connections'
                        : 'Tap shield icon to enable', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: provider.isEnabled,
              onChanged: (_) => provider.toggle(),
              activeThumbColor: GlassTheme.successColor,
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
            'forbidden',
            AppColors.errorInk,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Allowed',
            provider.stats.allowedConnections.toString(),
            'check_circle',
            AppColors.accentInk,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Rules',
            provider.stats.activeRules.toString(),
            'filter',
            AppColors.secondaryInk,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GlassCard(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            DuotoneIcon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: BrandText.heading(size: 24, color: color),
            ),
            Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionsTab(NetworkFirewallProvider provider) {
    if (provider.connections.isEmpty) {
      return _buildEmptyState(
        'transfer_vertical',
        'No Connections',
        'Network activity will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.connections.length,
      itemBuilder: (context, index) =>
          _buildConnectionCard(provider.connections[index]),
    );
  }

  Widget _buildConnectionCard(NetworkConnection conn) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = Color(NetworkFirewallProvider.getStatusColor(conn.status));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
            ),
            child: Center(
              child: DuotoneIcon(
                conn.status == ConnectionStatus.blocked
                    ? 'forbidden'
                    : conn.direction == ConnectionDirection.inbound
                        ? 'arrow_down'
                        : 'arrow_up',
                color: statusColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conn.remoteDomain ?? conn.remoteAddress,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        conn.appName ?? conn.appId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ':${conn.remotePort}',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
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
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
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
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
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
        'bell_off',
        'No Alerts',
        'Blocked connections will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.recentAlerts.length,
      itemBuilder: (context, index) =>
          _buildAlertCard(provider.recentAlerts[index], provider),
    );
  }

  Widget _buildAlertCard(NetworkConnection alert, NetworkFirewallProvider provider) {
    final cs = Theme.of(context).colorScheme;
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
                  color: GlassTheme.errorColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: Center(
                  child: DuotoneIcon(
                    'shield_cross',
                    color: AppColors.errorInk,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.blockReason?.displayName ?? 'Connection Blocked', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.errorInk,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      alert.appName ?? alert.appId, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatTime(alert.timestamp),
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Destination', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        alert.remoteDomain ?? alert.remoteAddress,
                        style: TextStyle(
                          color: cs.onSurface,
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
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      '${alert.remotePort}',
                      style: TextStyle(
                        color: cs.onSurface,
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
                child: Text(
                  'Allow',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _showBlockDetails(alert),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                  foregroundColor: Brand.onLime,
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
                  'globus',
                  () => _showAddBlockDialog(RuleType.domain),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickBlockButton(
                  'Block IP',
                  'monitor',
                  () => _showAddBlockDialog(RuleType.ip),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Rules list
        Expanded(
          child: provider.rules.isEmpty
              ? _buildEmptyState(
                  'filter',
                  'No Custom Rules',
                  'Add rules to block specific domains or IPs',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: provider.rules.length,
                  itemBuilder: (context, index) =>
                      _buildRuleCard(provider.rules[index], provider),
                ),
        ),
      ],
    );
  }

  Widget _buildQuickBlockButton(String label, String icon, VoidCallback onTap) {
    return GlassCard(
      onTap: onTap,
      margin: EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DuotoneIcon(icon, color: AppColors.accentInk, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: AppColors.accentInk,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(FirewallRule rule, NetworkFirewallProvider provider) {
    final cs = Theme.of(context).colorScheme;
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
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
            ),
            child: Center(
              child: DuotoneIcon(
                rule.action == RuleAction.block ? 'forbidden' : 'check_circle',
                color: rule.action == RuleAction.block
                    ? AppColors.errorInk
                    : AppColors.accentInk,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                      ),
                      child: Text(
                        rule.type.displayName,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.pattern,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
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
            activeThumbColor: GlassTheme.primaryAccent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          IconButton(
            icon: DuotoneIcon(
              'trash_bin_minimalistic',
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
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
        'smartphone',
        'No App Data',
        'App network profiles will appear here',
      );
    }

    final sortedApps = List<AppNetworkProfile>.from(provider.appProfiles)
      ..sort((a, b) => b.connectionCount.compareTo(a.connectionCount));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: sortedApps.length,
      itemBuilder: (context, index) =>
          _buildAppProfileCard(sortedApps[index], provider),
    );
  }

  Widget _buildAppProfileCard(
      AppNetworkProfile profile, NetworkFirewallProvider provider) {
    final cs = Theme.of(context).colorScheme;
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
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
            ),
            child: Center(
              child: DuotoneIcon(
                'smartphone',
                color: AppColors.accentInk,
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
                  profile.appName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${profile.connectionCount} connections',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    if (profile.blockedCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${profile.blockedCount} blocked',
                        style: TextStyle(
                          color: AppColors.errorInk,
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
            icon: DuotoneIcon(
              'menu_dots',
              color: cs.onSurfaceVariant,
              size: 20,
            ),
            color: cs.surface,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: profile.isAllowed ? 'block' : 'allow',
                child: Row(
                  children: [
                    DuotoneIcon(
                      profile.isAllowed ? 'forbidden' : 'check_circle',
                      color: profile.isAllowed
                          ? AppColors.errorInk
                          : AppColors.accentInk,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      profile.isAllowed ? 'Block App' : 'Allow App',
                      style: TextStyle(color: cs.onSurface),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'details',
                child: Row(
                  children: [
                    DuotoneIcon('info_circle', color: cs.onSurfaceVariant, size: 18),
                    const SizedBox(width: 8),
                    Text('View Details', style: TextStyle(color: cs.onSurface)),
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

  Widget _buildEmptyState(String icon, String title, String subtitle) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DuotoneIcon(icon, size: 64, color: cs.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showAddBlockDialog(RuleType type) {
    final cs = Theme.of(context).colorScheme;
    final controller = type == RuleType.domain ? _domainController : _ipController;
    controller.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GlassTheme.radiusLarge)),
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
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Block ${type.displayName}',
              style: BrandText.heading(size: 20),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              style: TextStyle(color: cs.onSurface),
              decoration: InputDecoration(
                hintText: type == RuleType.domain
                    ? 'e.g., malware.com'
                    : 'e.g., 192.168.1.100',
                hintStyle: TextStyle(color: cs.onSurfaceVariant),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DuotoneIcon(
                    type == RuleType.domain ? 'globus' : 'monitor',
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                filled: true,
                fillColor: cs.onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
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
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  ),
                ),
                child: Text(
                  'Block',
                  style: TextStyle(
                    color: Brand.onDanger,
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
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GlassTheme.radiusLarge)),
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
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Connection Details',
              style: BrandText.heading(size: 20),
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
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(GlassTheme.radiusLarge)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: GlassTheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
                    ),
                    child: Center(
                      child: DuotoneIcon(
                        'smartphone',
                        color: AppColors.accentInk,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.appName, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          profile.appId, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
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
                Text(
                  'Connected Domains',
                  style: BrandText.title(),
                ),
                const SizedBox(height: 12),
                ...profile.connectedDomains.take(10).map(
                      (domain) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          domain,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
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
