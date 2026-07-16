// Secure Call — the consumer "Secure call" shield (Phase 2.4).
//
// The HONEST version of "detect if someone is listening to my calls". It never
// claims to read, decrypt or detect eavesdropping inside a call — no app can.
// It checks THIS device for the conditions an eavesdropper would need and
// reports the posture calmly. The honesty is stated plainly on-screen.
//
// Wiring: the parent Protect hub routes the "Secure call" shield to
// [SecureCallScreen]. This screen is self-contained (runs [SecureCallCheck]).

import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/security/secure_call_check.dart';

class SecureCallScreen extends StatefulWidget {
  const SecureCallScreen({super.key});

  @override
  State<SecureCallScreen> createState() => _SecureCallScreenState();
}

class _SecureCallScreenState extends State<SecureCallScreen> {
  SecureCallPosture? _posture;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    final posture = await SecureCallCheck().run();
    if (!mounted) return;
    setState(() {
      _posture = posture;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Secure call',
      body: _posture == null
          ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
          : _buildReport(context, _posture!),
    );
  }

  Widget _buildReport(BuildContext context, SecureCallPosture posture) {
    final cs = Theme.of(context).colorScheme;
    final items = [...posture.items]..sort(
        (a, b) => _priority(a).compareTo(_priority(b)),
      );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const SizedBox(height: 6),
        // Honest one-liner: we check the DEVICE, not the call.
        Text(
          'This checks your device — not the call itself — for the conditions '
          'someone would need to listen in.',
          textAlign: TextAlign.center,
          style: BrandText.body(color: cs.onSurfaceVariant, size: 14.5),
        ),
        const SizedBox(height: 24),

        // ── Verdict hero ────────────────────────────────────────────────
        _Hero(posture: posture),

        const SizedBox(height: 28),

        // The single lime action on the screen.
        BrandButton(
          label: 'Check my device again',
          isLoading: _loading,
          expand: true,
          onPressed: _loading ? null : _run,
        ),

        const SizedBox(height: 28),

        // ── The checklist ───────────────────────────────────────────────
        GlassCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WHAT WE CHECKED ON THIS DEVICE',
                style: BrandText.label(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 22,
                    thickness: 1,
                    color: cs.outline.withValues(alpha: 0.5),
                  ),
                _CheckRow(item: items[i]),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── The honest part ─────────────────────────────────────────────
        GlassCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DuotoneIcon(AppIcons.infoCircle,
                      size: 18, color: AppColors.secondaryInk),
                  const SizedBox(width: 8),
                  Text('THE HONEST PART',
                      style: BrandText.label(color: AppColors.secondaryInk)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "No app — including OrbGuard — can listen inside WhatsApp, "
                "Signal, Telegram or a normal phone call, or tell you a "
                "specific call is being tapped. End-to-end encryption and the "
                "phone's app sandbox make that impossible.",
                style: BrandText.body(color: cs.onSurfaceVariant, size: 14),
              ),
              const SizedBox(height: 10),
              Text(
                'What OrbGuard can do is check THIS device for the conditions '
                'an eavesdropper would need first. That is everything listed '
                'above.',
                style: BrandText.body(color: cs.onSurfaceVariant, size: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Sort actionable findings to the top, unavailable checks to the bottom.
  static int _priority(SecureCallCheckItem i) {
    switch (i.status) {
      case CallCheckStatus.warning:
        return i.isHigh ? 0 : 1;
      case CallCheckStatus.error:
        return 2;
      case CallCheckStatus.info:
        return 3;
      case CallCheckStatus.clear:
        return 4;
      case CallCheckStatus.unavailable:
        return 5;
    }
  }
}

/// Verdict headline + icon ring, driven by the aggregated posture.
class _Hero extends StatelessWidget {
  final SecureCallPosture posture;
  const _Hero({required this.posture});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _color();
    final headlineColor =
        posture.verdict == CallPostureVerdict.warnings ? color : cs.onSurface;

    return Column(
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(28),
            border: Border.all(color: color.withAlpha(90), width: 2),
          ),
          child: Center(child: DuotoneIcon(_icon(), size: 44, color: color)),
        ),
        const SizedBox(height: 20),
        Text(
          _headline(),
          textAlign: TextAlign.center,
          style: BrandText.h2(color: headlineColor, size: 26),
        ),
        const SizedBox(height: 8),
        Text(
          _subline(),
          textAlign: TextAlign.center,
          style: BrandText.body(color: cs.onSurfaceVariant, size: 15),
        ),
      ],
    );
  }

  Color _color() {
    switch (posture.verdict) {
      case CallPostureVerdict.clean:
        return AppColors.accentInk;
      case CallPostureVerdict.warnings:
        return posture.anyHighSeverity
            ? AppColors.errorInk
            : AppColors.secondaryInk;
      case CallPostureVerdict.cannotCheck:
        return AppColors.text2;
    }
  }

  String _icon() {
    switch (posture.verdict) {
      case CallPostureVerdict.clean:
        return AppIcons.shieldCheck;
      case CallPostureVerdict.warnings:
        return AppIcons.shieldWarning;
      case CallPostureVerdict.cannotCheck:
        return AppIcons.shield;
    }
  }

  String _headline() {
    switch (posture.verdict) {
      case CallPostureVerdict.clean:
        return 'Your device looks clean for private calls';
      case CallPostureVerdict.warnings:
        return 'A few things to review first';
      case CallPostureVerdict.cannotCheck:
        return 'These checks need iPhone or Android';
    }
  }

  String _subline() {
    switch (posture.verdict) {
      case CallPostureVerdict.clean:
        return 'None of the conditions an eavesdropper would need are present '
            'on this device.';
      case CallPostureVerdict.warnings:
        final n = posture.warningCount;
        return '$n condition${n == 1 ? '' : 's'} below could make '
            'eavesdropping possible. Sort them out before a sensitive call.';
      case CallPostureVerdict.cannotCheck:
        return 'OrbGuard runs the device posture check on a phone, not on this '
            'platform.';
    }
  }
}

/// One check row: leading icon box, title + detail (+ findings), status glyph.
class _CheckRow extends StatelessWidget {
  final SecureCallCheckItem item;
  const _CheckRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = item.status == CallCheckStatus.unavailable;
    final tint = _tint(context);
    final titleColor = muted ? cs.onSurfaceVariant : cs.onSurface;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: tint.withAlpha(muted ? 20 : 30),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Center(child: DuotoneIcon(_icon(item.id), size: 22, color: tint)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title,
                  style: BrandText.title(color: titleColor, size: 15)),
              const SizedBox(height: 3),
              Text(
                item.detail,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (item.findings.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  _findingsText(item.findings),
                  style: BrandText.mono(color: tint, size: 11.5),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: DuotoneIcon(_statusGlyph(item.status), size: 20, color: tint),
        ),
      ],
    );
  }

  Color _tint(BuildContext context) {
    switch (item.status) {
      case CallCheckStatus.clear:
        return AppColors.accentInk;
      case CallCheckStatus.warning:
        return item.isHigh ? AppColors.errorInk : AppColors.secondaryInk;
      case CallCheckStatus.info:
        return AppColors.secondaryInk;
      case CallCheckStatus.error:
        return AppColors.amberInk;
      case CallCheckStatus.unavailable:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  static String _statusGlyph(CallCheckStatus status) {
    switch (status) {
      case CallCheckStatus.clear:
        return AppIcons.checkCircle;
      case CallCheckStatus.warning:
        return AppIcons.dangerTriangle;
      case CallCheckStatus.info:
        return AppIcons.infoCircle;
      case CallCheckStatus.error:
        return AppIcons.dangerCircle;
      case CallCheckStatus.unavailable:
        return AppIcons.forbiddenCircle;
    }
  }

  static String _icon(CallCheckId id) {
    switch (id) {
      case CallCheckId.screenCapture:
        return 'screencast';
      case CallCheckId.accessibilityServices:
        return 'eye_scan';
      case CallCheckId.trafficProxy:
        return 'routing';
      case CallCheckId.hostileCerts:
        return 'diploma';
      case CallCheckId.jailbreakRoot:
        return 'shield_keyhole';
      case CallCheckId.appTampering:
        return 'bug';
      case CallCheckId.microphoneApps:
        return 'microphone';
    }
  }

  static String _findingsText(List<String> f) {
    if (f.length <= 3) return f.join('   ·   ');
    return '${f.take(3).join('   ·   ')}   ·   +${f.length - 3} more';
  }
}
