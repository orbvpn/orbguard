/// Webhooks Screen
/// Webhook configuration and management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../services/api/orbguard_api_client.dart';

class WebhooksScreen extends StatefulWidget {
  const WebhooksScreen({super.key});

  @override
  State<WebhooksScreen> createState() => _WebhooksScreenState();
}

class _WebhooksScreenState extends State<WebhooksScreen> {
  bool _isLoading = false;
  String? _error;
  final List<Webhook> _webhooks = [];
  final _api = OrbGuardApiClient.instance;

  @override
  void initState() {
    super.initState();
    _loadWebhooks();
  }

  Future<void> _loadWebhooks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final webhooksData = await _api.getWebhooks();
      final webhooks = webhooksData.map((data) => Webhook.fromJson(data)).toList();
      setState(() {
        _webhooks.clear();
        _webhooks.addAll(webhooks);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Webhooks',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : _error != null
              ? _buildErrorState()
              : Column(
              children: [
                // Actions row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const DuotoneIcon('add_circle', size: 22, color: Colors.white),
                        onPressed: () => _showAddWebhookDialog(context),
                        tooltip: 'Add Webhook',
                      ),
                      IconButton(
                        icon: const DuotoneIcon('refresh', size: 22, color: Colors.white),
                        onPressed: _isLoading ? null : _loadWebhooks,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _webhooks.isEmpty
                      ? _buildEmptyState()
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            // Stats
                            Row(
                              children: [
                                _buildStatCard('Active', _webhooks.where((w) => w.isEnabled).length.toString(), GlassTheme.successColor),
                                const SizedBox(width: 12),
                                _buildStatCard('Total Sent', _formatSentCount(_webhooks.fold(0, (sum, w) => sum + w.sentCount)), GlassTheme.primaryAccent),
                              ],
                            ),
                            const SizedBox(height: 24),

                            const GlassSectionHeader(title: 'Configured Webhooks'),
                            ..._webhooks.map((webhook) => _buildWebhookCard(webhook)),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  String _formatSentCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    return count.toString();
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

  Widget _buildWebhookCard(Webhook webhook) {
    return GlassCard(
      onTap: () => _showWebhookDetails(context, webhook),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassDuotoneIconBox(
                icon: _getWebhookSvgIcon(webhook.type),
                color: webhook.isEnabled ? GlassTheme.primaryAccent : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(webhook.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(webhook.type, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: webhook.isEnabled,
                onChanged: (v) => setState(() => webhook.isEnabled = v),
                activeColor: GlassTheme.successColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            webhook.url,
            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12, fontFamily: 'monospace'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildWebhookStat('forward', '${webhook.sentCount} sent'),
              const SizedBox(width: 16),
              _buildWebhookStat(
                webhook.lastStatus == 'success' ? 'check_circle' : 'danger_circle',
                webhook.lastStatus == 'success' ? 'Healthy' : 'Failed',
                color: webhook.lastStatus == 'success' ? GlassTheme.successColor : GlassTheme.errorColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: webhook.events.take(3).map((event) => GlassBadge(
                  text: event,
                  color: GlassTheme.primaryAccent,
                  fontSize: 10,
                )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWebhookStat(String icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: color ?? Colors.white.withAlpha(128)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color ?? Colors.white.withAlpha(128), fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon('link', size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          const Text(
            'No Webhooks',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure webhooks to receive threat notifications',
            style: TextStyle(color: Colors.white.withAlpha(153)),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddWebhookDialog(context),
            icon: const DuotoneIcon('add_circle', size: 18, color: Colors.white),
            label: const Text('Add Webhook'),
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon('danger_circle', size: 64, color: GlassTheme.errorColor.withAlpha(128)),
            const SizedBox(height: 16),
            const Text(
              'Failed to Load Webhooks',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'An unknown error occurred',
              style: TextStyle(color: Colors.white.withAlpha(153)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadWebhooks,
              icon: const DuotoneIcon('refresh', size: 18, color: Colors.white),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createWebhook(String name, String url) async {
    try {
      final data = {
        'name': name,
        'url': url,
        'type': 'Custom',
        'events': ['threat.detected'],
        'is_enabled': true,
      };
      await _api.createWebhook(data);
      await _loadWebhooks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create webhook: $e'),
            backgroundColor: GlassTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _deleteWebhook(Webhook webhook) async {
    try {
      await _api.deleteWebhook(webhook.id);
      await _loadWebhooks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete webhook: $e'),
            backgroundColor: GlassTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showAddWebhookDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Add Webhook', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                hintText: 'e.g., Slack Notifications',
                hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Webhook URL',
                labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
                hintText: 'https://...',
                hintStyle: TextStyle(color: Colors.white.withAlpha(77)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
                Navigator.pop(context);
                _createWebhook(nameController.text, urlController.text);
              }
            },
            child: const Text('Add', style: TextStyle(color: GlassTheme.primaryAccent)),
          ),
        ],
      ),
    );
  }

  void _showWebhookDetails(BuildContext context, Webhook webhook) {
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
              Text(webhook.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GlassBadge(text: webhook.type, color: GlassTheme.primaryAccent),
              const SizedBox(height: 16),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  webhook.url,
                  style: TextStyle(color: Colors.white.withAlpha(204), fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Status', webhook.isEnabled ? 'Active' : 'Disabled'),
                    _buildDetailRow('Last Status', webhook.lastStatus.toUpperCase()),
                    _buildDetailRow('Total Sent', '${webhook.sentCount}'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Events', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: webhook.events.map((event) => GlassBadge(text: event, color: GlassTheme.primaryAccent)).toList(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        // Test webhook
                      },
                      icon: const DuotoneIcon('forward', size: 18, color: GlassTheme.primaryAccent),
                      label: const Text('Test'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GlassTheme.primaryAccent,
                        side: const BorderSide(color: GlassTheme.primaryAccent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteWebhook(webhook);
                      },
                      icon: const DuotoneIcon('trash_bin_minimalistic', size: 18, color: GlassTheme.errorColor),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: GlassTheme.errorColor,
                        side: const BorderSide(color: GlassTheme.errorColor),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

  String _getWebhookSvgIcon(String type) {
    switch (type.toLowerCase()) {
      case 'slack':
        return 'hashtag';
      case 'teams':
        return 'users_group_rounded';
      case 'discord':
        return 'chat_dots';
      case 'pagerduty':
        return 'bell_bing';
      default:
        return 'link';
    }
  }
}

class Webhook {
  final String id;
  final String name;
  final String url;
  final String type;
  final List<String> events;
  final int sentCount;
  final String lastStatus;
  bool isEnabled;

  Webhook({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    required this.events,
    this.sentCount = 0,
    this.lastStatus = 'success',
    this.isEnabled = true,
  });

  factory Webhook.fromJson(Map<String, dynamic> json) {
    return Webhook(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      type: json['type'] as String? ?? 'Custom',
      events: (json['events'] as List<dynamic>?)?.cast<String>() ?? [],
      sentCount: json['sent_count'] as int? ?? json['sentCount'] as int? ?? 0,
      lastStatus: json['last_status'] as String? ?? json['lastStatus'] as String? ?? 'success',
      isEnabled: json['is_enabled'] as bool? ?? json['isEnabled'] as bool? ?? true,
    );
  }
}
