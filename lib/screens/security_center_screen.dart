/// Security Center Screen
///
/// Main security dashboard with animated score, quick actions, and threat overview.
/// Inspired by OrbX design with fear/urgency elements to drive engagement.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../presentation/theme/colors.dart';
import '../presentation/theme/glass_theme.dart';
import '../presentation/widgets/duotone_icon.dart';
import '../presentation/widgets/glass_container.dart';
import '../providers/dashboard_provider.dart';
import '../models/api/threat_indicator.dart';
import 'sms_protection/sms_protection_screen.dart';
import 'url_protection/url_protection_screen.dart';
import 'qr_scanner/qr_scanner_screen.dart';
import 'app_security/app_security_screen.dart';
import 'darkweb/darkweb_screen.dart';
import 'footprint/digital_footprint_screen.dart';
import 'intelligence/intelligence_core_screen.dart';

class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({super.key});

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _scanController;

  final DashboardProvider _provider = DashboardProvider();
  bool _isInitialized = false;

  // Protection toggle states
  bool _smsProtection = true;
  bool _urlProtection = true;
  bool _qrProtection = true;
  bool _networkProtection = true;

  @override
  void initState() {
    super.initState();

    // Pulse animation for score circle
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Scan animation
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _initProvider();
  }

  Future<void> _initProvider() async {
    await _provider.init();
    if (mounted) {
      setState(() => _isInitialized = true);
    }
    _provider.addListener(_onProviderChanged);
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    _provider.removeListener(_onProviderChanged);
    _provider.dispose();
    super.dispose();
  }

  int get _securityScore {
    if (!_isInitialized) return 0;
    final protection = _provider.summary?.protection;
    if (protection == null) return 85; // Default score

    int score = 100;

    // Deduct points for disabled protections
    if (!_smsProtection) score -= 10;
    if (!_urlProtection) score -= 10;
    if (!_qrProtection) score -= 5;
    if (!_networkProtection) score -= 10;

    // Deduct for active threats
    final threatCount = _provider.stats?.criticalAndHighCount ?? 0;
    score -= (threatCount * 15).clamp(0, 40);

    return score.clamp(0, 100);
  }

  int get _threatCount => _provider.stats?.criticalAndHighCount ?? 0;
  int get _blockedToday => _provider.summary?.threats.threatsBlockedToday ?? 0;

  Color _getScoreColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.lightGreen;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _getStatusText(int score) {
    if (score >= 90) return 'Excellent Protection';
    if (score >= 70) return 'Good Protection';
    if (score >= 50) return 'Needs Attention';
    return 'At Risk - Action Required';
  }

  Future<void> _onRefresh() async {
    await _provider.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final score = _securityScore;
    final scoreColor = _getScoreColor(score);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0F) : Colors.grey[100],
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(isDark),
                const SizedBox(height: 20),

                // Security Score Hero Card
                _buildSecurityScoreCard(isDark, score, scoreColor),
                const SizedBox(height: 20),

                // Quick Actions Grid
                _buildQuickActionsGrid(isDark),
                const SizedBox(height: 20),

                // Threat Intelligence Card
                _buildThreatIntelCard(isDark),
                const SizedBox(height: 20),

                // Active Protections Card
                _buildActiveProtectionsCard(isDark),
                const SizedBox(height: 20),

                // Recent Activity
                _buildRecentActivityCard(isDark),
                const SizedBox(height: 20),

                // Security Features Grid
                _buildFeatureCardsGrid(isDark),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      children: [
        Text(
          'Security Center',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            // Show notifications
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: GlassTheme.circularGlassDecoration(isDark: isDark),
            child: ClipOval(
              child: BackdropFilter(
                filter: GlassTheme.blurFilter,
                child: Center(
                  child: DuotoneIcon(
                    'bell',
                    size: 22,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // SECURITY SCORE HERO CARD
  // ============================================================================

  Widget _buildSecurityScoreCard(bool isDark, int score, Color scoreColor) {
    final shouldPulse = score < 70;

    return GlassCard(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                // Animated Score Circle
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: shouldPulse ? _pulseAnimation.value : 1.0,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scoreColor.withAlpha(25),
                      border: Border.all(color: scoreColor, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: scoreColor.withAlpha(shouldPulse ? 100 : 50),
                          blurRadius: shouldPulse ? 30 : 20,
                          spreadRadius: shouldPulse ? 5 : 2,
                        ),
                      ],
                    ),
                    child: !_isInitialized
                        ? Center(
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scoreColor,
                              ),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$score',
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: scoreColor,
                                ),
                              ),
                              Text(
                                'Score',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scoreColor.withAlpha(180),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 24),

                // Status Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Security Status',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getStatusText(score),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scoreColor,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Mini Stats
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _buildMiniStat(
                            'shield_check',
                            '$_blockedToday',
                            'Blocked',
                            Colors.green,
                            isDark,
                          ),
                          _buildMiniStat(
                            'danger_triangle',
                            '$_threatCount',
                            'Threats',
                            _threatCount > 0 ? Colors.red : Colors.grey,
                            isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Warning Banner (if threats detected)
            if (_threatCount > 0 || score < 50)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    // Navigate to threat details
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const DuotoneIcon('danger_circle', size: 22, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _threatCount > 0
                                ? 'Security threats detected. Tap to review.'
                                : 'Your device needs attention. Review settings.',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const DuotoneIcon('alt_arrow_right', size: 18, color: Colors.red),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String icon, String value, String label, Color color, bool isDark) {
    return Row(
      children: [
        DuotoneIcon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // QUICK ACTIONS GRID
  // ============================================================================

  Widget _buildQuickActionsGrid(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionCard(
                icon: 'qr_code',
                label: 'Scan QR',
                color: const Color(0xFF00D4FF),
                isDark: isDark,
                onTap: () => _navigateTo(const QrScannerScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                icon: 'chat_dots',
                label: 'Check SMS',
                color: Colors.purple,
                isDark: isDark,
                onTap: () => _navigateTo(const SmsProtectionScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                icon: 'link',
                label: 'Check URL',
                color: Colors.orange,
                isDark: isDark,
                onTap: () => _navigateTo(const UrlProtectionScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                icon: 'widget',
                label: 'Scan Apps',
                color: Colors.green,
                isDark: isDark,
                onTap: () => _navigateTo(const AppSecurityScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required String icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: GlassCard(
        isDark: isDark,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: DuotoneIcon(icon, size: 24, color: color),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // THREAT INTELLIGENCE CARD
  // ============================================================================

  Widget _buildThreatIntelCard(bool isDark) {
    final stats = _provider.stats;

    return GlassCard(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DuotoneIcon('radar', size: 22, color: Color(0xFF00D4FF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Threat Intelligence',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _navigateTo(const IntelligenceCoreScreen()),
                  child: Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Stats Grid
            Row(
              children: [
                Expanded(
                  child: _buildStatTile(
                    'Total IOCs',
                    _formatNumber(stats?.totalIndicators ?? 0),
                    'fingerprint',
                    Colors.blue,
                    isDark,
                  ),
                ),
                Expanded(
                  child: _buildStatTile(
                    'Last 24h',
                    _formatNumber(stats?.indicatorsLast24h ?? 0),
                    'clock_circle',
                    Colors.green,
                    isDark,
                  ),
                ),
                Expanded(
                  child: _buildStatTile(
                    'Last 7d',
                    _formatNumber(stats?.indicatorsLast7d ?? 0),
                    'calendar',
                    Colors.orange,
                    isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Severity Breakdown
            Text(
              'By Severity',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 8),
            _buildSeverityBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(String label, String value, String icon, Color color, bool isDark) {
    return Column(
      children: [
        DuotoneIcon(icon, size: 24, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSeverityBar(bool isDark) {
    // Get severity distribution from provider
    final critical = _provider.getThreatsBySeverity(SeverityLevel.critical);
    final high = _provider.getThreatsBySeverity(SeverityLevel.high);
    final medium = _provider.getThreatsBySeverity(SeverityLevel.medium);
    final low = _provider.getThreatsBySeverity(SeverityLevel.low);
    final total = critical + high + medium + low;

    // If no data, show empty state
    if (total == 0) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[300],
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              if (critical > 0) Expanded(flex: critical, child: Container(height: 8, color: Colors.red[900])),
              if (high > 0) Expanded(flex: high, child: Container(height: 8, color: Colors.red)),
              if (medium > 0) Expanded(flex: medium, child: Container(height: 8, color: Colors.orange)),
              if (low > 0) Expanded(flex: low, child: Container(height: 8, color: Colors.yellow[700])),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSeverityLabel('Critical', critical, Colors.red[900]!, isDark),
            _buildSeverityLabel('High', high, Colors.red, isDark),
            _buildSeverityLabel('Medium', medium, Colors.orange, isDark),
            _buildSeverityLabel('Low', low, Colors.yellow[700]!, isDark),
          ],
        ),
      ],
    );
  }

  Widget _buildSeverityLabel(String label, int count, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$count%',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // ACTIVE PROTECTIONS CARD
  // ============================================================================

  Widget _buildActiveProtectionsCard(bool isDark) {
    return GlassCard(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DuotoneIcon('shield_check', size: 22, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Active Protections',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildProtectionRow(
              'SMS Protection',
              'Scans messages for phishing',
              'chat_dots',
              _smsProtection,
              (value) => setState(() => _smsProtection = value),
              isDark,
            ),
            _buildDivider(isDark),
            _buildProtectionRow(
              'URL Protection',
              'Blocks malicious links',
              'link',
              _urlProtection,
              (value) => setState(() => _urlProtection = value),
              isDark,
            ),
            _buildDivider(isDark),
            _buildProtectionRow(
              'QR Code Protection',
              'Scans QR codes before opening',
              'qr_code',
              _qrProtection,
              (value) => setState(() => _qrProtection = value),
              isDark,
            ),
            _buildDivider(isDark),
            _buildProtectionRow(
              'Network Protection',
              'Monitors network security',
              'wi_fi_router',
              _networkProtection,
              (value) => setState(() => _networkProtection = value),
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProtectionRow(
    String title,
    String subtitle,
    String icon,
    bool isEnabled,
    Function(bool) onChanged,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isEnabled ? Colors.green : Colors.grey).withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: DuotoneIcon(
                icon,
                size: 20,
                color: isEnabled ? Colors.green : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isEnabled,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              onChanged(value);
            },
            activeTrackColor: Colors.green.withAlpha(150),
            activeThumbColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      color: isDark ? Colors.white12 : Colors.black12,
    );
  }

  // ============================================================================
  // RECENT ACTIVITY CARD
  // ============================================================================

  Widget _buildRecentActivityCard(bool isDark) {
    final alerts = _provider.recentAlerts.take(3).toList();

    return GlassCard(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DuotoneIcon('history', size: 22, color: Color(0xFF00D4FF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                if (alerts.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      // Navigate to full history
                    },
                    child: Text(
                      'View All',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            if (alerts.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      DuotoneIcon(
                        'check_circle',
                        size: 48,
                        color: isDark ? Colors.white38 : Colors.black26,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No recent security activity',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your recent scans will appear here',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black26,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...alerts.map((alert) => _buildActivityItem(
                    icon: _getAlertIcon(alert.type),
                    title: alert.title,
                    subtitle: alert.message,
                    time: alert.timestamp,
                    isAlert: alert.severity == SeverityLevel.critical || alert.severity == SeverityLevel.high,
                    isDark: isDark,
                  )),
          ],
        ),
      ),
    );
  }

  String _getAlertIcon(String type) {
    switch (type) {
      case 'sms': return 'chat_dots';
      case 'url': return 'link';
      case 'qr': return 'qr_code';
      case 'app': return 'widget';
      case 'network': return 'wi_fi_router';
      default: return 'shield';
    }
  }

  Widget _buildActivityItem({
    required String icon,
    required String title,
    required String subtitle,
    required DateTime time,
    required bool isAlert,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isAlert ? Colors.red : Colors.green).withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: DuotoneIcon(
                icon,
                size: 20,
                color: isAlert ? Colors.red : Colors.green,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isAlert ? Colors.red : (isDark ? Colors.white : Colors.black),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            _formatTimeAgo(time),
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // FEATURE CARDS GRID
  // ============================================================================

  Widget _buildFeatureCardsGrid(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Security Features',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _buildFeatureCard(
              icon: 'bug',
              title: 'Spyware Check',
              description: 'Detect Pegasus & stalkerware',
              color: Colors.red,
              isDark: isDark,
              onTap: () {
                // Navigate to spyware check
              },
            ),
            _buildFeatureCard(
              icon: 'incognito',
              title: 'Dark Web Monitor',
              description: 'Check data breaches',
              color: Colors.purple,
              isDark: isDark,
              onTap: () => _navigateTo(const DarkWebScreen()),
            ),
            _buildFeatureCard(
              icon: 'map_point_wave',
              title: 'Digital Footprint',
              description: 'Your online exposure',
              color: Colors.blue,
              isDark: isDark,
              onTap: () => _navigateTo(const DigitalFootprintScreen()),
            ),
            _buildFeatureCard(
              icon: 'radar',
              title: 'Threat Feed',
              description: 'Live threat intelligence',
              color: const Color(0xFF00D4FF),
              isDark: isDark,
              onTap: () => _navigateTo(const IntelligenceCoreScreen()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
    required String icon,
    required String title,
    required String description,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: GlassCard(
        isDark: isDark,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: DuotoneIcon(icon, size: 24, color: color),
                ),
              ),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  void _navigateTo(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
