import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../darkweb/darkweb_screen.dart';
import '../forensics/forensics_screen.dart';
import '../privacy/privacy_protection_screen.dart';
import '../scam/scam_detection_screen.dart';
import 'hidden_vpn_proxy_screen.dart';
import 'secure_call_screen.dart';

/// The consumer **Protect** hub — the six plain-English shields, each a doorway
/// into a real protection. This is the Guard-mode organising layer over the
/// underlying feature screens (no jargon, no SOC console).
///
/// The two new-feature shields (Hidden VPN & Proxy, Secure Call) currently open
/// their nearest real screen; Phase 2.3 / 2.4 give them dedicated destinations.
class ShieldsScreen extends StatelessWidget {
  const ShieldsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final shields = <_Shield>[
      _Shield('magnifer_bug', 'Spyware & Pegasus',
          'Check for professional spy software', AppColors.secondaryInk,
          (_) => const ForensicsScreen()),
      _Shield('eye_closed', "Who's watching you",
          'Hidden trackers, stalkerware & risky permissions',
          AppColors.errorInk, (_) => const PrivacyProtectionScreen()),
      _Shield('danger_triangle', 'Scam shield',
          'Texts, links & QR codes', AppColors.amberInk,
          (_) => const ScamDetectionScreen()),
      _Shield('wi_fi_router', 'Hidden VPN & proxy',
          'Spot traffic being secretly rerouted', AppColors.accentInk,
          (_) => const HiddenVpnProxyScreen()),
      _Shield('phone_calling', 'Secure call',
          'Check your device before sensitive calls', AppColors.secondaryInk,
          (_) => const SecureCallScreen()),
      _Shield('global', 'Identity & breach',
          'Find your accounts exposed on the dark web', AppColors.accentInk,
          (_) => const DarkWebScreen()),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        8 + GlassTheme.headerClearance,
        16,
        24 +
            GlassTheme.bottomNavClearance +
            MediaQuery.of(context).padding.bottom,
      ),
      children: [
        Text('Your protection',
            style: BrandText.h2(color: cs.onSurface, size: 26)),
        const SizedBox(height: 4),
        Text('Six shields, always watching. Tap any to look closer.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 15)),
        const SizedBox(height: 18),
        ...shields.map((s) => _ShieldCard(shield: s)),
      ],
    );
  }
}

class _Shield {
  final String icon;
  final String title;
  final String subtitle;
  final Color tint;
  final WidgetBuilder builder;
  const _Shield(this.icon, this.title, this.subtitle, this.tint, this.builder);
}

class _ShieldCard extends StatelessWidget {
  final _Shield shield;
  const _ShieldCard({required this.shield});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        margin: EdgeInsets.zero,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: shield.builder),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: shield.tint.withAlpha(30),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: DuotoneIcon(shield.icon, size: 24, color: shield.tint),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shield.title,
                      style: BrandText.title(color: cs.onSurface, size: 16)),
                  const SizedBox(height: 3),
                  Text(shield.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DuotoneIcon('alt_arrow_right', size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
