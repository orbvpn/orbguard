/// Connection Indicator Widget
/// Real-time WebSocket connection status indicator

import 'package:flutter/material.dart';

import '../../services/realtime/websocket_service.dart';
import '../../services/realtime/connection_manager.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../presentation/widgets/duotone_icon.dart';

/// Connection status indicator for app bar or status bar
class ConnectionIndicator extends StatelessWidget {
  final WebSocketState state;
  final bool compact;
  final VoidCallback? onTap;

  const ConnectionIndicator({
    super.key,
    required this.state,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact();
    }
    return _buildFull();
  }

  Widget _buildCompact() {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _getColor().withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(),
            const SizedBox(width: 4),
            if (_isConnecting())
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            else
              DuotoneIcon(_getIcon(), size: 14, color: _getColor()),
          ],
        ),
      ),
    );
  }

  Widget _buildFull() {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getColor().withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _getColor().withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(),
            const SizedBox(width: 8),
            if (_isConnecting())
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(_getColor()),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            Text(
              _getText(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _getColor(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot() {
    if (_isConnecting()) {
      return _PulsingDot(color: _getColor());
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: _getColor(),
        shape: BoxShape.circle,
        boxShadow: state == WebSocketState.connected
            ? [
                BoxShadow(
                  color: _getColor().withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }

  bool _isConnecting() {
    return state == WebSocketState.connecting ||
        state == WebSocketState.reconnecting;
  }

  Color _getColor() {
    switch (state) {
      case WebSocketState.connected:
        return Colors.green;
      case WebSocketState.connecting:
      case WebSocketState.reconnecting:
        return Colors.amber;
      case WebSocketState.error:
        return Colors.red;
      case WebSocketState.disconnected:
        return Colors.grey;
    }
  }

  String _getText() {
    switch (state) {
      case WebSocketState.connected:
        return 'Connected';
      case WebSocketState.connecting:
        return 'Connecting...';
      case WebSocketState.reconnecting:
        return 'Reconnecting...';
      case WebSocketState.error:
        return 'Error';
      case WebSocketState.disconnected:
        return 'Disconnected';
    }
  }

  String _getIcon() {
    switch (state) {
      case WebSocketState.connected:
        return AppIcons.cloudStorage;
      case WebSocketState.connecting:
      case WebSocketState.reconnecting:
        return AppIcons.refresh;
      case WebSocketState.error:
        return AppIcons.dangerCircle;
      case WebSocketState.disconnected:
        return AppIcons.cloudStorage;
    }
  }
}

/// Pulsing dot animation
class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color.withOpacity(_animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

/// Detailed connection health card
class ConnectionHealthCard extends StatelessWidget {
  final ConnectionHealth health;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  const ConnectionHealthCard({
    super.key,
    required this.health,
    this.onConnect,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildDetails(),
          const SizedBox(height: 16),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _getStateColor().withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DuotoneIcon(
            _getStateIcon(),
            color: _getStateColor(),
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Connection Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                health.statusText,
                style: TextStyle(
                  fontSize: 13,
                  color: _getStateColor(),
                ),
              ),
            ],
          ),
        ),
        ConnectionIndicator(
          state: health.state,
          compact: true,
        ),
      ],
    );
  }

  Widget _buildDetails() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildDetailRow('Network', health.networkTypeText,
              health.hasNetwork ? Colors.green : Colors.red),
          const SizedBox(height: 8),
          _buildDetailRow(
            'Events Received',
            health.eventsReceived.toString(),
            Colors.cyan,
          ),
          if (health.lastEventTime != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow(
              'Last Event',
              _formatTime(health.lastEventTime!),
              Colors.grey,
            ),
          ],
          if (health.lastHealthCheck != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow(
              'Last Check',
              _formatTime(health.lastHealthCheck!),
              Colors.grey,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        if (!health.isConnected && onConnect != null)
          Expanded(
            child: ElevatedButton.icon(
              onPressed: health.hasNetwork ? onConnect : null,
              icon: DuotoneIcon(AppIcons.urlProtection, size: 18, color: Colors.black),
              label: const Text('Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        if (health.isConnected && onDisconnect != null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onDisconnect,
              icon: DuotoneIcon(AppIcons.closeCircle, size: 18, color: Colors.orange),
              label: const Text('Disconnect'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
      ],
    );
  }

  Color _getStateColor() {
    switch (health.state) {
      case WebSocketState.connected:
        return Colors.green;
      case WebSocketState.connecting:
      case WebSocketState.reconnecting:
        return Colors.amber;
      case WebSocketState.error:
        return Colors.red;
      case WebSocketState.disconnected:
        return Colors.grey;
    }
  }

  String _getStateIcon() {
    switch (health.state) {
      case WebSocketState.connected:
        return AppIcons.cloudStorage;
      case WebSocketState.connecting:
      case WebSocketState.reconnecting:
        return AppIcons.refresh;
      case WebSocketState.error:
        return AppIcons.dangerCircle;
      case WebSocketState.disconnected:
        return AppIcons.cloudStorage;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// App bar connection status action
class ConnectionStatusAction extends StatelessWidget {
  final WebSocketState state;
  final VoidCallback onTap;

  const ConnectionStatusAction({
    super.key,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Stack(
        children: [
          DuotoneIcon(
            _getIcon(),
            color: _getColor(),
          ),
          if (state == WebSocketState.error)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      tooltip: _getTooltip(),
    );
  }

  Color _getColor() {
    switch (state) {
      case WebSocketState.connected:
        return Colors.green;
      case WebSocketState.connecting:
      case WebSocketState.reconnecting:
        return Colors.amber;
      case WebSocketState.error:
        return Colors.red;
      case WebSocketState.disconnected:
        return Colors.grey;
    }
  }

  String _getIcon() {
    switch (state) {
      case WebSocketState.connected:
        return AppIcons.cloudStorage;
      case WebSocketState.connecting:
      case WebSocketState.reconnecting:
        return AppIcons.refresh;
      case WebSocketState.error:
        return AppIcons.dangerCircle;
      case WebSocketState.disconnected:
        return AppIcons.cloudStorage;
    }
  }

  String _getTooltip() {
    switch (state) {
      case WebSocketState.connected:
        return 'Connected to threat stream';
      case WebSocketState.connecting:
        return 'Connecting...';
      case WebSocketState.reconnecting:
        return 'Reconnecting...';
      case WebSocketState.error:
        return 'Connection error';
      case WebSocketState.disconnected:
        return 'Disconnected';
    }
  }
}
