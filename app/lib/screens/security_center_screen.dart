/// Security Center Screen
///
/// Main security dashboard with the protection score, quick actions, and a
/// calm threat overview — status is conveyed honestly by color and plain
/// wording, with no fear/urgency framing.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../presentation/theme/app_theme.dart';
import '../presentation/theme/brand.dart';
import '../presentation/theme/colors.dart';
import '../presentation/theme/glass_theme.dart';
import '../presentation/widgets/duotone_icon.dart';
import '../presentation/widgets/glass_container.dart';
import '../providers/dashboard_provider.dart';
import '../providers/settings_provider.dart';
import '../models/api/threat_indicator.dart';
import 'sms_protection/sms_protection_screen.dart';
import 'url_protection/url_protection_screen.dart';
import 'qr_scanner/qr_scanner_screen.dart';
import 'app_security/app_security_screen.dart';
import 'darkweb/darkweb_screen.dart';
import 'footprint/digital_footprint_screen.dart';
import 'intelligence/intelligence_core_screen.dart';
import 'settings/settings_screen.dart';
import '../presentation/theme/protection_verdict.dart';
import 'security/threat_hunting_screen.dart';

class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({super.key});

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  final DashboardProvider _provider = DashboardProvider();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();

    // Load the persisted protection settings (shared with the Settings
    // screen) so the Active Protections switches reflect real state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SettingsProvider>().init();
    });

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
    _provider.removeListener(_onProviderChanged);
    _provider.dispose();
    super.dispose();
  }

  /// Sentinel returned by [_securityScore] when the backend has not
  /// produced a real device-protection assessment. Rendered as "—" /
  /// "Not assessed yet" — never as a fabricated number.
  static const int _scoreNotAssessed = -1;

  /// The REAL device protection score, straight from the backend
  /// (`GET /api/v1/stats/dashboard` → `protection.score`, 0–100).
  ///
  /// Returns [_scoreNotAssessed] when there is no genuine measurement to
  /// show: either the dashboard summary has not loaded yet, or the backend
  /// omitted the protection section (no device identity), in which case
  /// `protection.available` is false and its score is only a placeholder.
  /// We never synthesise a score from local toggles or feed counts.
  int _securityScore() {
    final protection = _provider.summary?.protection;
    if (protection == null || !protection.available) {
      return _scoreNotAssessed;
    }
    return protection.protectionScore.round();
  }

  int get _blockedToday => _provider.summary?.threats.threatsBlockedToday ?? 0;

  // Status wording + colors come from the ONE shared verdict source
  // ([ProtectionVerdict]) so the home and the Dashboard never disagree.
  Color _getScoreColor(int score) => ProtectionVerdict.fromScore(score).fill;
  Color _getScoreInk(int score) => ProtectionVerdict.fromScore(score).ink;
  String _getStatusText(int score) => ProtectionVerdict.fromScore(score).label;

  Future<void> _onRefresh() async {
    await _provider.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();
    final score = _securityScore();
    final scoreColor = _getScoreColor(score);
    final scoreInk = _getScoreInk(score);

    return Scaffold(
      // Transparent so the app-wide ambient gradient shows through —
      // keeps this tab visually consistent with the other glass tabs.
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.accentInk,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(isDark),
                const SizedBox(height: 16),

                // Security Score Hero Card
                _buildSecurityScoreCard(isDark, score, scoreColor, scoreInk),
                const SizedBox(height: 24),

                // Quick Actions Grid
                _buildQuickActionsGrid(isDark),
                const SizedBox(height: 24),

                // Threat Intelligence Card
                _buildThreatIntelCard(isDark),
                const SizedBox(height: 24),

                // Active Protections Card
                _buildActiveProtectionsCard(isDark, settings),
                const SizedBox(height: 24),

                // Recent Activity
                _buildRecentActivityCard(isDark),
                const SizedBox(height: 24),

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
          style: BrandText.heading(size: 28, color: context.onSurface),
        ),
      ],
    );
  }

  // ============================================================================
  // SECURITY SCORE HERO CARD
  // ============================================================================

  Widget _buildSecurityScoreCard(
      bool isDark, int score, Color scoreColor, Color scoreInk) {
    return GlassCard(
      isDark: isDark,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            Row(
              children: [
                // Calm, static score ring — status is conveyed honestly by
                // color and plain wording; the pulsing "urgency" was removed.
                Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scoreColor.withAlpha(25),
                      border: Border.all(color: scoreColor, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: scoreColor.withAlpha(50),
                          blurRadius: 20,
                          spreadRadius: 2,
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
                                color: scoreInk,
                              ),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                score < 0 ? '—' : '$score',
                                style: BrandText.display(
                                    size: 40, color: scoreInk),
                              ),
                              Text(
                                'Score',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scoreInk.withAlpha(180),
                                ),
                              ),
                            ],
                          ),
                  ),
                const SizedBox(width: 24),

                // Status Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Security Status', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: BrandText.heading(
                            size: 20, color: context.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getStatusText(score), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: scoreInk,
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
                            AppColors.accentInk,
                            isDark,
                          ),
                          _buildMiniStat(
                            'history',
                            '${_provider.summary?.threats.threatsDetectedWeek ?? 0}',
                            'Past 7 days',
                            AppColors.accentInk,
                            isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Attention banner — only when THIS DEVICE's protection score is
            // genuinely low. (It used to also fire on the global feed's IOC
            // count, turning a permanent alarm on for everyone; removed.)
            if (score >= 0 && score < 50)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    // Low device score → take the user to their protection
                    // settings to improve it, not to the global threat feed.
                    _navigateTo(const SettingsScreen());
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: GlassTheme.tintedGlassDecoration(
                      tintColor: AppColors.error,
                      radius: GlassTheme.radiusSmall,
                      opacity: 0.1,
                    ),
                    child: Row(
                      children: [
                        DuotoneIcon('danger_circle',
                            size: 22, color: AppColors.errorInk),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your device needs attention. Tap to review your protection.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.errorInk,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        DuotoneIcon('alt_arrow_right',
                            size: 18, color: AppColors.errorInk),
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
            color: context.onSurfaceMuted,
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
          style: BrandText.heading(size: 18, color: context.onSurface),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionCard(
                icon: 'qr_code',
                label: 'Scan QR',
                color: AppColors.secondaryInk,
                isDark: isDark,
                onTap: () => _navigateTo(const QrScannerScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                icon: 'chat_dots',
                label: 'Check SMS',
                color: AppColors.chartColors[4], // spectrum purple
                isDark: isDark,
                onTap: () => _navigateTo(const SmsProtectionScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                icon: 'link_round',
                label: 'Check URL',
                color: AppColors.amberInk,
                isDark: isDark,
                onTap: () => _navigateTo(const UrlProtectionScreen()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionCard(
                icon: 'widget',
                label: 'Scan Apps',
                color: AppColors.accentInk,
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
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.onSurfaceMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DuotoneIcon('radar', size: 22, color: AppColors.secondaryInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Threat Intelligence',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.heading(
                        size: 18, color: context.onSurface),
                  ),
                ),
                GestureDetector(
                  onTap: () => _navigateTo(const IntelligenceCoreScreen()),
                  child: Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 13,
                      // Lime is fill-only — links use the lime-family ink.
                      color: AppColors.accentInk,
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
                    AppColors.secondaryInk,
                    isDark,
                  ),
                ),
                Expanded(
                  child: _buildStatTile(
                    'Last 24h',
                    _formatNumber(stats?.indicatorsLast24h ?? 0),
                    'clock_circle',
                    AppColors.accentInk,
                    isDark,
                  ),
                ),
                Expanded(
                  child: _buildStatTile(
                    'Last 7d',
                    _formatNumber(stats?.indicatorsLast7d ?? 0),
                    'calendar',
                    AppColors.amberInk,
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
                color: context.onSurfaceMuted,
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
          style: BrandText.heading(size: 22, color: context.onSurface),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: context.onSurfaceMuted,
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
          color: Brand.surface2,
          // Half-height radius on the 8px meter (kept: radiusXSmall clamps
          // to the same rounded-end shape).
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
              if (critical > 0) Expanded(flex: critical, child: Container(height: 8, color: AppColors.severityCritical)),
              if (high > 0) Expanded(flex: high, child: Container(height: 8, color: AppColors.severityHigh)),
              if (medium > 0) Expanded(flex: medium, child: Container(height: 8, color: AppColors.severityMedium)),
              if (low > 0) Expanded(flex: low, child: Container(height: 8, color: AppColors.severityLow)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSeverityLabel('Critical', critical, AppColors.severityCritical, isDark),
            _buildSeverityLabel('High', high, AppColors.severityHigh, isDark),
            _buildSeverityLabel('Medium', medium, AppColors.severityMedium, isDark),
            _buildSeverityLabel('Low', low, AppColors.severityLow, isDark),
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
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: context.onSurfaceMuted,
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // ACTIVE PROTECTIONS CARD
  // ============================================================================

  /// Switches read from and write to the persisted [ProtectionSettings]
  /// (SharedPreferences-backed), the same source of truth used by the
  /// Settings screen's Protection Features section.
  Widget _buildActiveProtectionsCard(bool isDark, SettingsProvider settings) {
    final prot = settings.protection;

    return GlassCard(
      isDark: isDark,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DuotoneIcon('shield_check',
                    size: 22, color: AppColors.accentInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Active Protections',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.heading(
                        size: 18, color: context.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildProtectionRow(
              'SMS Protection',
              'Scans messages for phishing',
              'chat_dots',
              prot.smsProtectionEnabled,
              (value) => settings.updateProtection(
                  prot.copyWith(smsProtectionEnabled: value)),
              isDark,
            ),
            _buildDivider(isDark),
            _buildProtectionRow(
              'URL Protection',
              'Blocks malicious links',
              'link_round',
              prot.urlProtectionEnabled,
              (value) => settings.updateProtection(
                  prot.copyWith(urlProtectionEnabled: value)),
              isDark,
            ),
            _buildDivider(isDark),
            _buildProtectionRow(
              'QR Code Protection',
              'Scans QR codes before opening',
              'qr_code',
              prot.qrProtectionEnabled,
              (value) => settings.updateProtection(
                  prot.copyWith(qrProtectionEnabled: value)),
              isDark,
            ),
            _buildDivider(isDark),
            _buildProtectionRow(
              'Network Protection',
              'Monitors network security',
              'wi_fi_router',
              prot.networkProtectionEnabled,
              (value) => settings.updateProtection(
                  prot.copyWith(networkProtectionEnabled: value)),
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
              color: (isEnabled ? AppColors.success : context.onSurfaceMuted)
                  .withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: DuotoneIcon(
                icon,
                size: 20,
                color:
                    isEnabled ? AppColors.accentInk : context.onSurfaceMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.onSurface,
                  ),
                ),
                Text(
                  subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.onSurfaceMuted,
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
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      color: context.colors.outline,
    );
  }

  // ============================================================================
  // RECENT ACTIVITY CARD
  // ============================================================================

  Widget _buildRecentActivityCard(bool isDark) {
    final alerts = _provider.recentAlerts.take(3).toList();

    return GlassCard(
      isDark: isDark,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DuotoneIcon('history', size: 22, color: AppColors.secondaryInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recent Activity',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.heading(
                        size: 18, color: context.onSurface),
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
                        color: context.onSurfaceMuted.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No recent security activity',
                        style: TextStyle(
                          color: context.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your recent scans will appear here',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.onSurfaceMuted.withValues(alpha: 0.7),
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
      case 'url': return 'link_round';
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
              color: (isAlert ? AppColors.error : AppColors.success)
                  .withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: DuotoneIcon(
                icon,
                size: 20,
                color: isAlert ? AppColors.errorInk : AppColors.accentInk,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isAlert ? AppColors.errorInk : context.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.onSurfaceMuted,
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
              color: context.onSurfaceMuted.withValues(alpha: 0.7),
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
          style: BrandText.heading(size: 18, color: context.onSurface),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: [
            _buildFeatureCard(
              icon: 'bug',
              title: 'Spyware Check',
              description: 'Detect Pegasus & stalkerware',
              color: AppColors.errorInk,
              isDark: isDark,
              // Spyware/stalkerware detection runs as threat hunts.
              onTap: () => _navigateTo(const ThreatHuntingScreen()),
            ),
            _buildFeatureCard(
              icon: 'incognito',
              title: 'Dark Web Monitor',
              description: 'Check data breaches',
              color: AppColors.chartColors[4], // spectrum purple
              isDark: isDark,
              onTap: () => _navigateTo(const DarkWebScreen()),
            ),
            _buildFeatureCard(
              icon: 'map_point_wave',
              title: 'Digital Footprint',
              description: 'Your online exposure',
              color: AppColors.secondaryInk,
              isDark: isDark,
              onTap: () => _navigateTo(const DigitalFootprintScreen()),
            ),
            _buildFeatureCard(
              icon: 'radar',
              title: 'Threat Feed',
              description: 'Live threat intelligence',
              color: AppColors.chartColors[2], // spectrum cyan
              isDark: isDark,
              onTap: () => _navigateTo(const IntelligenceCoreScreen()),
            ),
          ],
        ),
        const SizedBox(height: 30),
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
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  borderRadius:
                      BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: Center(
                  child: DuotoneIcon(icon, size: 24, color: color),
                ),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: context.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: context.onSurfaceMuted,
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
