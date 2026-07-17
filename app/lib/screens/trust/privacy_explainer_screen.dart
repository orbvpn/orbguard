/// Privacy Explainer — Phase 3.1 trust surface.
///
/// The anti-surveillance brand's credibility moment: in calm, plain English,
/// explains that OrbGuard runs ON THE DEVICE and cannot see the user's data.
/// Tone is reassuring and confident — honest limits (no message reading, no
/// call listening) are framed as a strength, never an apology. Every claim
/// here must stay literally true (see the honesty guardrails in
/// `app/CLAUDE.md`): scans run on-device, OrbGuard never sees the user's data
/// on a server, and it never claims to read inside messaging apps or listen
/// to calls.
///
/// Pure Dart UI — builds identically on iOS/Android/macOS/Windows/Linux.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/on_device_trust_badge.dart';

/// The four trust promises, each shown as its own glass card:
///  1. Everything runs on your phone.
///  2. We can't read your messages or listen to your calls.
///  3. What we keep.
///  4. Your data is yours.
class PrivacyExplainerScreen extends StatelessWidget {
  const PrivacyExplainerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GlassPage(
      title: 'Your privacy',
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const SizedBox(height: 4),

          // ── Hero: the headline promise ─────────────────────────────────
          Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentInk.withAlpha(28),
                border: Border.all(color: AppColors.accentInk.withAlpha(70), width: 2),
              ),
              child: Center(
                child: DuotoneIcon('shield_keyhole', size: 40, color: AppColors.accentInk),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Built to see less, not more',
            textAlign: TextAlign.center,
            style: BrandText.h2(color: cs.onSurface, size: 25),
          ),
          const SizedBox(height: 8),
          Text(
            'Exactly how OrbGuard treats your data — plainly, and without '
            'the fine print.',
            textAlign: TextAlign.center,
            style: BrandText.body(color: cs.onSurfaceVariant, size: 15),
          ),
          const SizedBox(height: 16),
          const Center(child: OnDeviceTrustBadge()),

          const SizedBox(height: 26),

          // ── The four trust promises ────────────────────────────────────
          _TrustCard(
            icon: 'smartphone',
            tint: AppColors.accentInk,
            title: 'Everything runs on your phone',
            body: 'Every scan happens locally, right here on your device — '
                'never sent to a server first. Results stay on your phone '
                'unless you choose to share them, for example when '
                'contacting support.',
          ),
          _TrustCard(
            icon: 'microphone_slash',
            tint: AppColors.secondaryInk,
            title: "We can't read your messages or listen to your calls",
            body: 'OrbGuard cannot open WhatsApp, Signal, or Telegram, and it '
                'cannot listen in on a call — your phone simply does not '
                'allow any app that kind of access. That is not a gap. It is '
                'by design, and it is a good thing.',
          ),
          _TrustCard(
            icon: 'folder_check',
            tint: AppColors.amberInk,
            title: 'What we keep',
            body: 'We keep the minimum needed to show your protection '
                'status — scan results and your settings — stored locally '
                'on this device. Nothing is collected just in case.',
          ),
          _TrustCard(
            icon: 'incognito',
            tint: AppColors.accentInk,
            title: 'Your data is yours',
            body: 'No accounts sold, no tracking across apps, and no ads. '
                'OrbGuard answers to you — never to an advertiser or a data '
                'broker.',
          ),
        ],
      ),
    );
  }
}

class _TrustCard extends StatelessWidget {
  final String icon;
  final Color tint;
  final String title;
  final String body;

  const _TrustCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint.withAlpha(30),
              borderRadius: BorderRadius.circular(Brand.rMd),
            ),
            child: Center(child: DuotoneIcon(icon, size: 22, color: tint)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: BrandText.title(color: cs.onSurface, size: 16)),
                const SizedBox(height: 6),
                Text(body, style: BrandText.body(color: cs.onSurfaceVariant, size: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
