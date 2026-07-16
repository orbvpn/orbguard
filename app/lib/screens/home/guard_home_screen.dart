import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/theme/protection_verdict.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/dashboard_provider.dart';

/// The consumer **Guard Home** — the calm centre of the app.
///
/// One honest verdict, one primary action ("Check my phone"), and a plain-
/// language reminder of what OrbGuard watches for. No score theatre, no jargon,
/// no fear. Replaces the busier Security Center as the Home tab in Guard mode
/// (Pro mode keeps the fuller dashboard).
class GuardHomeScreen extends StatefulWidget {
  /// Runs the device checkup — wired by the shell to the real scan flow.
  final VoidCallback onCheckMyPhone;

  const GuardHomeScreen({super.key, required this.onCheckMyPhone});

  @override
  State<GuardHomeScreen> createState() => _GuardHomeScreenState();
}

class _GuardHomeScreenState extends State<GuardHomeScreen> {
  final DashboardProvider _provider = DashboardProvider();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onChange);
    _provider.init();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_onChange);
    _provider.dispose();
    super.dispose();
  }

  /// The device protection score, or -1 when the backend hasn't assessed this
  /// device yet (so it reads "let's check" rather than a misleading "at risk").
  int get _score {
    final p = _provider.summary?.protection;
    if (p == null || !p.available) return -1;
    return p.protectionScore.round();
  }

  DateTime? get _lastScan {
    final p = _provider.summary?.protection;
    return (p != null && p.available) ? p.lastScan : null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final verdict = ProtectionVerdict.fromScore(_score);
    final headlineColor =
        verdict.level == ProtectionLevel.notAssessed ? cs.onSurface : verdict.ink;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),

          // ── Verdict hero ──────────────────────────────────────────────
          Center(
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: verdict.fill.withAlpha(28),
                border: Border.all(color: verdict.fill.withAlpha(90), width: 2),
              ),
              child: Center(
                child: DuotoneIcon(
                  _heroIcon(verdict.level),
                  size: 46,
                  color: verdict.ink,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _headline(verdict.level),
            textAlign: TextAlign.center,
            style: BrandText.h2(color: headlineColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            _subline(verdict),
            textAlign: TextAlign.center,
            style: BrandText.body(color: cs.onSurfaceVariant, size: 15),
          ),

          const SizedBox(height: 30),

          // ── The one primary action ────────────────────────────────────
          BrandButton(
            label: 'Check my phone',
            expand: true,
            onPressed: widget.onCheckMyPhone,
          ),

          const SizedBox(height: 30),

          // ── What we watch for (plain language, honest) ────────────────
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OrbGuard keeps watch for',
                  style: BrandText.label(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                ..._watchItems.map((it) => _WatchRow(icon: it.$1, label: it.$2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _heroIcon(ProtectionLevel level) {
    switch (level) {
      case ProtectionLevel.excellent:
      case ProtectionLevel.good:
        return AppIcons.shieldCheck;
      case ProtectionLevel.attention:
        return AppIcons.shield;
      case ProtectionLevel.atRisk:
        return AppIcons.dangerTriangle;
      case ProtectionLevel.notAssessed:
        return AppIcons.shield;
    }
  }

  String _headline(ProtectionLevel level) {
    switch (level) {
      case ProtectionLevel.excellent:
      case ProtectionLevel.good:
        return "You're protected";
      case ProtectionLevel.attention:
        return 'A few things to review';
      case ProtectionLevel.atRisk:
        return 'Your phone needs attention';
      case ProtectionLevel.notAssessed:
        return "Let's check your phone";
    }
  }

  String _subline(ProtectionVerdict verdict) {
    final scan = _lastScan;
    final when = scan == null ? 'Not checked yet' : 'Last checked ${_ago(scan)}';
    if (verdict.level == ProtectionLevel.notAssessed) {
      return 'Run your first checkup to see where you stand.';
    }
    return '${verdict.label} · $when';
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  // Plain-language protections, each mapped to a real capability area.
  static const List<(String, String)> _watchItems = [
    ('magnifer_bug', 'Spyware & Pegasus'),
    ('eye_closed', 'Stalkerware & hidden trackers'),
    ('danger_triangle', 'Scam texts, links & QR codes'),
    ('wi_fi_router', 'Unsafe Wi-Fi & hidden VPNs'),
    ('global', 'Your accounts on the dark web'),
  ];
}

class _WatchRow extends StatelessWidget {
  final String icon;
  final String label;
  const _WatchRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          DuotoneIcon(icon, size: 20, color: AppColors.secondaryInk),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: BrandText.title(color: cs.onSurface, size: 15)),
          ),
          DuotoneIcon(AppIcons.checkCircle, size: 18, color: AppColors.accentInk),
        ],
      ),
    );
  }
}
