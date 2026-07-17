/// ControlPanelHomeScreen — the living control-panel home (P4.2).
///
/// Replaces the calm one-verdict home the product owner rejected ("looks like
/// the app is not doing anything") with a Norton/McAfee-style control panel
/// that is 100% honest:
///
///  • the pulsing orb and the "Monitoring live" dot animate ONLY while
///    [GuardStatusController.activeCount] > 0 — something real is running;
///  • the privacy score is computed by the pure [PrivacyScoreEngine] from
///    verifiable signals (last scan verdict, guard states) — every point maps
///    to a genuine action;
///  • unavailable guards are hidden, not faked;
///  • the LIVE TODAY feed only shows real counts/timestamps and says plainly
///    when there is nothing to show yet.
///
/// Everything is injected (controllers + callbacks) so the shell wires real
/// sources and tests inject fakes. This widget performs no I/O of its own.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/protection_verdict.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/habit/protection_streak_controller.dart';
import '../../services/home/guard_status_controller.dart';
import '../../services/home/last_scan_verdict_controller.dart';
import '../../services/home/privacy_score_engine.dart';
import '../../widgets/home/guard_grid.dart';
import '../../widgets/home/live_activity_card.dart';
import '../../widgets/home/privacy_score_card.dart';
import '../../widgets/home/pulse_orb.dart';

class ControlPanelHomeScreen extends StatelessWidget {
  /// Launches the real checkup flow — the screen's single lime action.
  final VoidCallback onRunCheck;

  /// Verdict of the latest on-device scan (score −1 until one has run).
  final LastScanVerdictController verdict;

  /// Live guard states; `activeCount > 0` is the only thing that may make
  /// this screen claim live monitoring.
  final GuardStatusController guardsController;

  /// Optional days-protected streak for the hero status line.
  final ProtectionStreakController? streak;

  /// When provided, used WHOLESALE instead of the internally-built signals —
  /// lets the shell enrich with breach/permission/VPN data and lets tests
  /// pin the score deterministically.
  final PrivacySignals Function()? signalsOverride;

  /// Tap on a guard tile → route to that guard's setup/detail flow.
  final void Function(String guardId)? onGuardTap;

  /// Tap on a score factor → route to the flow that earns those points.
  final void Function(String factorId)? onFactorTap;

  /// Real count of tracker/surveillance domains blocked today, or null when
  /// no counting source exists (never fabricate).
  final int Function()? blockedTodayCount;

  /// When the breach monitor last checked the user's email, or null if never.
  final DateTime? Function()? breachLastChecked;

  const ControlPanelHomeScreen({
    super.key,
    required this.onRunCheck,
    required this.verdict,
    required this.guardsController,
    this.streak,
    this.signalsOverride,
    this.onGuardTap,
    this.onFactorTap,
    this.blockedTodayCount,
    this.breachLastChecked,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([verdict, guardsController, streak]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final v = ProtectionVerdict.fromScore(verdict.score);
        final bool live = guardsController.activeCount > 0;
        final PrivacyScore score =
            const PrivacyScoreEngine().compute(_buildSignals());
        final int? blocked = blockedTodayCount?.call();
        final DateTime? breachAt = breachLastChecked?.call();
        final headlineColor =
            v.level == ProtectionLevel.notAssessed ? cs.onSurface : v.ink;

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              20, 8, 20, AppSpacing.bottomNavHeight),
          children: [
            const SizedBox(height: 4),

            // ── 1 · Hero: the verdict orb IS the scan button ──────────────
            Center(
              child: PulseOrb(
                icon: _heroIcon(v.level),
                fill: v.fill,
                ink: v.ink,
                live: live,
                onTap: onRunCheck,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _headline(v.level),
              textAlign: TextAlign.center,
              style: BrandText.h2(size: 27, color: headlineColor),
            ),
            const SizedBox(height: 10),
            _statusLine(context, live),
            const SizedBox(height: 24),

            // ── 2 · Privacy score ────────────────────────────────────────
            PrivacyScoreCard(score: score, onFactorTap: onFactorTap),
            const SizedBox(height: 16),

            // ── 3 · The one lime action (the orb triggers the same scan) ──
            BrandButton(
              label: 'Run scan',
              expand: true,
              onPressed: onRunCheck,
            ),

            // ── 4 · Your guards ──────────────────────────────────────────
            if (guardsController.guards
                .any((g) => g.state != GuardState.unavailable)) ...[
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  'YOUR GUARDS',
                  style:
                      BrandText.label(size: 11.5, color: cs.onSurfaceVariant),
                ),
              ),
              GuardGrid(
                guards: guardsController.guards,
                onGuardTap: onGuardTap,
              ),
            ],
            const SizedBox(height: 16),

            // ── 5 · Proof-of-work feed ───────────────────────────────────
            LiveActivityCard(blockedToday: blocked, breachCheckedAt: breachAt),
          ],
        );
      },
    );
  }

  /// Signals for the score engine. [signalsOverride] wins wholesale;
  /// otherwise every field comes from the injected controllers — the fields
  /// this screen has no real source for stay null ("not checked yet"), which
  /// the engine scores as an action, never as safe.
  PrivacySignals _buildSignals() {
    final override = signalsOverride;
    if (override != null) return override();

    final DateTime? lastAt = verdict.lastScanAt;
    // Alerts reachable = the alerts guard's probe verified the permission.
    final bool alertsActive = guardsController.guards.any(
        (g) => g.id == 'alerts' && g.state == GuardState.active);

    return PrivacySignals(
      lastScanScore: verdict.score,
      daysSinceScan:
          lastAt == null ? null : DateTime.now().difference(lastAt).inDays,
      openThreats: verdict.threatCount,
      guardsActive: guardsController.activeCount,
      guardsAvailable: guardsController.availableCount,
      breachedAccounts: null,
      riskyPermissionApps: null,
      unknownVpnActive: null,
      notificationsGranted: alertsActive,
    );
  }

  /// Live line under the headline. The lime dot exists ONLY when at least one
  /// guard is verified running; otherwise the line says protection is off.
  Widget _statusLine(BuildContext context, bool live) {
    final cs = Theme.of(context).colorScheme;
    if (!live) {
      return Text(
        'Protection is off — set up your guards',
        textAlign: TextAlign.center,
        style: BrandText.mono(size: 12, color: cs.onSurfaceVariant),
      );
    }
    final int days = streak?.currentStreak ?? 0;
    final String label = days > 0
        ? 'Monitoring live · protected $days day${days == 1 ? '' : 's'}'
        : 'Monitoring live';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const LiveDot(),
        const SizedBox(width: 7),
        Text(label, style: BrandText.mono(size: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }

  static String _headline(ProtectionLevel level) => switch (level) {
        ProtectionLevel.notAssessed => "Let's check your phone",
        ProtectionLevel.excellent ||
        ProtectionLevel.good =>
          "You're not being watched",
        ProtectionLevel.attention => 'A few things to review',
        ProtectionLevel.atRisk => 'Your phone needs attention',
      };

  static String _heroIcon(ProtectionLevel level) => switch (level) {
        ProtectionLevel.excellent ||
        ProtectionLevel.good =>
          AppIcons.shieldCheck,
        ProtectionLevel.atRisk => AppIcons.dangerTriangle,
        ProtectionLevel.attention ||
        ProtectionLevel.notAssessed =>
          AppIcons.shield,
      };
}
