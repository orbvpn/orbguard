// Dashboard Screen
// Main dashboard with real-time threat intelligence and protection status

import 'package:flutter/material.dart';

import '../presentation/theme/glass_theme.dart';
import '../presentation/widgets/duotone_icon.dart';
import '../presentation/widgets/glass_container.dart';
import '../presentation/widgets/glass_app_bar.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/dashboard/protection_status_card.dart';
import '../widgets/dashboard/threat_stats_card.dart';
import '../widgets/dashboard/recent_alerts_widget.dart';
import '../widgets/dashboard/connection_indicator.dart';
import '../services/realtime/websocket_service.dart';
import '../services/realtime/connection_manager.dart';
import '../services/security/device_scan_service.dart';
import 'analytics/analytics_dashboard_screen.dart';
import 'scanning_screen.dart';
import 'settings/settings_screen.dart';

/// Main dashboard screen
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final DashboardProvider _dashboardProvider = DashboardProvider();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDashboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dashboardProvider.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _dashboardProvider.refresh(silent: true);
    }
  }

  Future<void> _initDashboard() async {
    await _dashboardProvider.init();
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
    _dashboardProvider.addListener(_onProviderChanged);
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onRefresh() async {
    await _dashboardProvider.refresh();
  }

  void _navigateToScan() async {
    final result = await Navigator.push<ScanResult>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ScanningScreen(
          // Real native scan flow (same engine as the home screen's scan),
          // with genuine per-stage progress callbacks.
          onScanWithProgress: (onProgress) =>
              DeviceScanService.instance.performScan(onProgress: onProgress),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );

    if (result != null) {
      // Refresh dashboard after scan
      _dashboardProvider.refresh(silent: true);
    }
  }

  void _showConnectionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: GlassTheme.gradientTop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ConnectionBottomSheet(
        health: _dashboardProvider.connectionHealth,
        onConnect: () {
          Navigator.pop(context);
          _dashboardProvider.connectRealtime();
        },
        onDisconnect: () {
          Navigator.pop(context);
          _dashboardProvider.disconnectRealtime();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white.withAlpha(150) : Colors.black.withAlpha(100);

    return GlassPage(
      title: 'Dashboard',
      showBackButton: true,
      actions: [
        GestureDetector(
          onTap: _showConnectionSheet,
          child: DuotoneIcon('wi_fi_router', size: 22, color: iconColor),
        ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
          child: DuotoneIcon('settings', size: 22, color: iconColor),
        ),
      ],
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _onRefresh,
              color: const Color(0xFF00D9FF),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Connection status banner (if disconnected)
                    if (!_dashboardProvider.isConnected)
                      _buildConnectionBanner(),

                    // Protection Status Card
                    ProtectionStatusCard(
                      protection: _dashboardProvider.summary?.protection,
                      status: _dashboardProvider.protectionStatus,
                      isLoading: _dashboardProvider.isLoading,
                      onScanTap: _navigateToScan,
                    ),
                    const SizedBox(height: 16),

                    // Threat Stats Card
                    ThreatStatsCard(
                      stats: _dashboardProvider.stats,
                      threatOverview: _dashboardProvider.summary?.threats,
                      isLoading: _dashboardProvider.isLoading,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AnalyticsDashboardScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Recent Alerts (no dedicated "all alerts" screen exists,
                    // so no view-all affordance is shown).
                    RecentAlertsWidget(
                      alerts: _dashboardProvider.recentAlerts,
                      isLoading: _dashboardProvider.isLoading,
                      onAlertTap: (alertId) =>
                          _dashboardProvider.markAlertAsRead(alertId),
                    ),
                    const SizedBox(height: 16),

                    // Real-time Events
                    RealtimeEventsWidget(
                      events: _dashboardProvider.realtimeEvents,
                      isConnected: _dashboardProvider.isConnected,
                      onConnect: () => _dashboardProvider.connectRealtime(),
                    ),
                    const SizedBox(height: 16),

                    // Device Health Card
                    DeviceHealthCard(
                      health: _dashboardProvider.deviceHealth,
                      isLoading: _dashboardProvider.isLoading,
                    ),

                    // Last refresh indicator
                    if (_dashboardProvider.timeSinceRefresh != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Center(
                          child: Text(
                            'Updated ${_dashboardProvider.timeSinceRefresh}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildConnectionBanner() {
    final health = _dashboardProvider.connectionHealth;
    final state = _dashboardProvider.connectionState;

    Color bannerColor;
    String message;
    String icon;

    if (!health.hasNetwork) {
      bannerColor = Colors.red;
      message = 'No network connection';
      icon = 'wi_fi_router';
    } else if (state == WebSocketState.error) {
      bannerColor = Colors.orange;
      message = 'Connection error. Tap to retry.';
      icon = 'danger_circle';
    } else if (state == WebSocketState.reconnecting) {
      bannerColor = Colors.amber;
      message = 'Reconnecting to threat stream...';
      icon = 'refresh';
    } else {
      bannerColor = Colors.grey;
      message = 'Not connected to live threat stream';
      icon = 'cloud_storage';
    }

    return GestureDetector(
      onTap: health.hasNetwork ? () => _dashboardProvider.connectRealtime() : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bannerColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            DuotoneIcon(icon, color: bannerColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: bannerColor,
                ),
              ),
            ),
            if (health.hasNetwork && state != WebSocketState.reconnecting)
              DuotoneIcon('alt_arrow_right', color: bannerColor, size: 20),
            if (state == WebSocketState.reconnecting)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(bannerColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Connection bottom sheet
class _ConnectionBottomSheet extends StatelessWidget {
  final ConnectionHealth health;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _ConnectionBottomSheet({
    required this.health,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Content
          ConnectionHealthCard(
            health: health,
            onConnect: onConnect,
            onDisconnect: onDisconnect,
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Dashboard summary bar for other screens
class DashboardSummaryBar extends StatelessWidget {
  final int threatsBlocked;
  final double protectionScore;
  final WebSocketState connectionState;
  final VoidCallback? onTap;

  const DashboardSummaryBar({
    super.key,
    required this.threatsBlocked,
    required this.protectionScore,
    required this.connectionState,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          ProtectionStatusIndicator(
            isProtected: protectionScore >= 50,
            score: protectionScore,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ThreatStatsCompact(
              blockedToday: threatsBlocked,
              criticalCount: 0,
              highCount: 0,
            ),
          ),
          ConnectionIndicator(
            state: connectionState,
            compact: true,
          ),
        ],
      ),
    );
  }
}
