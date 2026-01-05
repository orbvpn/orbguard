/// Recent Alerts Widget
/// Displays recent security alerts and real-time events

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/api/threat_stats.dart';
import '../../models/api/threat_indicator.dart';
import '../../services/realtime/websocket_service.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_container.dart';

/// Widget displaying recent security alerts
class RecentAlertsWidget extends StatelessWidget {
  final List<RecentAlert> alerts;
  final bool isLoading;
  final VoidCallback? onViewAll;
  final Function(String)? onAlertTap;
  final Function(String)? onDismiss;

  const RecentAlertsWidget({
    super.key,
    required this.alerts,
    this.isLoading = false,
    this.onViewAll,
    this.onAlertTap,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          if (isLoading)
            _buildLoadingState()
          else if (alerts.isEmpty)
            _buildEmptyState()
          else
            _buildAlertsList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final unreadCount = alerts.where((a) => !a.isRead).length;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: unreadCount > 0
                ? Colors.red.withOpacity(0.2)
                : Colors.cyan.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              Icon(
                Icons.notifications,
                color: unreadCount > 0 ? Colors.red : Colors.cyan,
                size: 20,
              ),
              if (unreadCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
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
              const Text(
                'Recent Alerts',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (unreadCount > 0)
                Text(
                  '$unreadCount unread',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red[300],
                  ),
                ),
            ],
          ),
        ),
        if (onViewAll != null && alerts.isNotEmpty)
          TextButton(
            onPressed: onViewAll,
            child: const Text('View All'),
          ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.green[400]),
            const SizedBox(height: 12),
            Text(
              'No recent alerts',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your device is secure',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsList() {
    return Column(
      children: alerts.take(5).map((alert) {
        return Dismissible(
          key: Key(alert.id),
          direction: onDismiss != null
              ? DismissDirection.endToStart
              : DismissDirection.none,
          onDismissed: (_) => onDismiss?.call(alert.id),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            color: Colors.red.withOpacity(0.2),
            child: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          child: _AlertTile(
            alert: alert,
            onTap: () => onAlertTap?.call(alert.id),
          ),
        );
      }).toList(),
    );
  }
}

/// Single alert tile widget
class _AlertTile extends StatelessWidget {
  final RecentAlert alert;
  final VoidCallback? onTap;

  const _AlertTile({
    required this.alert,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSeverityIcon(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                alert.isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!alert.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.cyan,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alert.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildTypeChip(),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(alert.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityIcon() {
    Color color;
    IconData icon;

    switch (alert.severity) {
      case SeverityLevel.critical:
        color = Colors.red;
        icon = Icons.error;
        break;
      case SeverityLevel.high:
        color = Colors.orange;
        icon = Icons.warning;
        break;
      case SeverityLevel.medium:
        color = Colors.amber;
        icon = Icons.info;
        break;
      default:
        color = Colors.grey;
        icon = Icons.info_outline;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _buildTypeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        alert.type.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}';
  }
}

/// Real-time threat events list
class RealtimeEventsWidget extends StatelessWidget {
  final List<ThreatEvent> events;
  final bool isConnected;
  final VoidCallback? onConnect;
  final Function(ThreatEvent)? onEventTap;

  const RealtimeEventsWidget({
    super.key,
    required this.events,
    required this.isConnected,
    this.onConnect,
    this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          if (!isConnected)
            _buildDisconnectedState()
          else if (events.isEmpty)
            _buildEmptyState()
          else
            _buildEventsList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isConnected
                ? Colors.green.withOpacity(0.2)
                : Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.stream,
            color: isConnected ? Colors.green : Colors.grey,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Live Threat Feed',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        _buildConnectionStatus(),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withOpacity(0.2)
            : Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isConnected ? 'Live' : 'Offline',
            style: TextStyle(
              fontSize: 11,
              color: isConnected ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 12),
            Text(
              'Not connected to threat stream',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
            if (onConnect != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Connect'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyan,
                  side: const BorderSide(color: Colors.cyan),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.hourglass_empty, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 12),
            Text(
              'Waiting for threat events...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsList() {
    return Column(
      children: events.take(10).map((event) {
        return _RealtimeEventTile(
          event: event,
          onTap: () => onEventTap?.call(event),
        );
      }).toList(),
    );
  }
}

/// Single real-time event tile
class _RealtimeEventTile extends StatelessWidget {
  final ThreatEvent event;
  final VoidCallback? onTap;

  const _RealtimeEventTile({
    required this.event,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
          ),
        ),
        child: Row(
          children: [
            _buildSeverityIndicator(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.type,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.value,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildSeverityBadge(),
                const SizedBox(height: 4),
                Text(
                  _formatTime(event.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityIndicator() {
    return Container(
      width: 4,
      height: 32,
      decoration: BoxDecoration(
        color: _getSeverityColor(),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildSeverityBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getSeverityColor().withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        event.severity.value.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: _getSeverityColor(),
        ),
      ),
    );
  }

  Color _getSeverityColor() {
    switch (event.severity) {
      case SeverityLevel.critical:
        return Colors.red;
      case SeverityLevel.high:
        return Colors.orange;
      case SeverityLevel.medium:
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }
}
