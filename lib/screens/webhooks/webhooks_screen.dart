/// Webhooks Screen
/// Webhook configuration and management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';

class WebhooksScreen extends StatefulWidget {
  const WebhooksScreen({super.key});

  @override
  State<WebhooksScreen> createState() => _WebhooksScreenState();
}

class _WebhooksScreenState extends State<WebhooksScreen> {
  bool _isLoading = false;
  final List<Webhook> _webhooks = [];

  @override
  void initState() {
    super.initState();
    _loadWebhooks();
  }

  Future<void> _loadWebhooks() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _webhooks.addAll(_getSampleWebhooks());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Webhooks',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddWebhookDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadWebhooks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : _webhooks.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Stats
                    Row(
                      children: [
                        _buildStatCard('Active', _webhooks.where((w) => w.isEnabled).length.toString(), GlassTheme.successColor),
                        const SizedBox(width: 12),
                        _buildStatCard('Total Sent', '1,247', GlassTheme.primaryAccent),
                      ],
                    ),
                    const SizedBox(height: 24),

                    const GlassSectionHeader(title: 'Configured Webhooks'),
                    ..._webhooks.map((webhook) => _buildWebhookCard(webhook)),
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
              GlassIconBox(
                icon: _getWebhookIcon(webhook.type),
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
              _buildWebhookStat(Icons.send, '${webhook.sentCount} sent'),
              const SizedBox(width: 16),
              _buildWebhookStat(
                webhook.lastStatus == 'success' ? Icons.check_circle : Icons.error,
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

  Widget _buildWebhookStat(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.white.withAlpha(128)),
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
          Icon(Icons.webhook, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
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
            icon: const Icon(Icons.add),
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
                setState(() {
                  _webhooks.add(Webhook(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text,
                    url: urlController.text,
                    type: 'Custom',
                    events: ['threat.detected'],
                  ));
                });
                Navigator.pop(context);
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
                      icon: const Icon(Icons.send),
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
                        setState(() => _webhooks.remove(webhook));
                      },
                      icon: const Icon(Icons.delete),
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

  IconData _getWebhookIcon(String type) {
    switch (type.toLowerCase()) {
      case 'slack':
        return Icons.tag;
      case 'teams':
        return Icons.groups;
      case 'discord':
        return Icons.chat;
      case 'pagerduty':
        return Icons.notifications_active;
      default:
        return Icons.webhook;
    }
  }

  List<Webhook> _getSampleWebhooks() {
    return [
      Webhook(
        id: '1',
        name: 'Slack Security Channel',
        url: 'https://hooks.slack.com/services/xxx/yyy/zzz',
        type: 'Slack',
        events: ['threat.detected', 'scan.complete', 'alert.critical'],
        sentCount: 847,
        lastStatus: 'success',
      ),
      Webhook(
        id: '2',
        name: 'PagerDuty Alerts',
        url: 'https://events.pagerduty.com/v2/enqueue',
        type: 'PagerDuty',
        events: ['alert.critical', 'alert.high'],
        sentCount: 23,
        lastStatus: 'success',
      ),
      Webhook(
        id: '3',
        name: 'SIEM Integration',
        url: 'https://siem.company.com/api/v1/events',
        type: 'Custom',
        events: ['threat.detected', 'indicator.matched'],
        sentCount: 377,
        lastStatus: 'failed',
        isEnabled: false,
      ),
    ];
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
}
