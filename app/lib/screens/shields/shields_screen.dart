import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_rows.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/page_head.dart';
import '../../services/home/home_brief.dart';
import '../../utils/host_platform.dart';
import '../../widgets/shields/shield_look.dart';
import '../darkweb/darkweb_screen.dart';
import '../device_security/device_security_screen.dart';
import '../forensics/forensics_screen.dart';
import '../privacy/privacy_protection_screen.dart';
import '../scam/scam_detection_screen.dart';
import 'hidden_vpn_proxy_screen.dart';
import 'secure_call_screen.dart';

/// Where a shield opens. Home's orbit and the Protect list both go through
/// here, so one shield always leads to one place.
Widget shieldScreen(Shield shield) => switch (shield) {
      // Four of these screens predate the shields and carry an expert name
      // of their own. Opened as a shield, each is headed by the shield's
      // name; the last two were built as shields and already are.
      Shield.spyware => ForensicsScreen(title: shield.name),
      Shield.watching => PrivacyProtectionScreen(title: shield.name),
      Shield.scam => ScamDetectionScreen(title: shield.name),
      Shield.identity => DarkWebScreen(title: shield.name),
      Shield.hiddenVpn => const HiddenVpnProxyScreen(),
      Shield.secureCall => const SecureCallScreen(),
    };

/// The **Protect** tab: the six shields by the names, icons and order they
/// have on Home, each a doorway into a real protection.
///
/// It lists what each shield covers and nothing about whether it is on: only
/// Home reads the real guard states, so only Home may say that.
///
/// On a phone, a "Lost or stolen" section under the shields leads to the
/// anti-theft screen.
class ShieldsScreen extends StatelessWidget {
  const ShieldsScreen({super.key, this.platform});

  /// The platform the page is drawn for. Null is the one this runs on; tests
  /// name one.
  final TargetPlatform? platform;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Brand tokens flip with the theme
    final bool phone = isPhonePlatform(platform ?? hostPlatform());

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        24 +
            GlassTheme.bottomNavClearance +
            MediaQuery.of(context).padding.bottom,
      ),
      children: [
        // The line says what the tab is for and nothing about whether a
        // shield is on: this tab reads no guard state.
        const PageHead(
          title: 'Protect',
          subtitle: 'Six shields. Open any one to see what it covers.',
        ),
        for (final Shield shield in Shield.values) _ShieldCard(shield: shield),
        if (phone) ...[
          // Each card keeps 12 under itself; with this the gap is the kit's
          // 26 between sections.
          const SectionLabel('Lost or stolen', top: 14),
          GlassRows(rows: [
            // Nothing here says whether anti-theft is set up: this tab reads
            // no state, so the row only says what the screen does.
            GlassRow(
              icon: AppIcons.mapPointWave,
              iconColor: Brand.text,
              title: 'Find this phone',
              line: 'Locate it, ring it, or photograph whoever has it',
              onTap: () => showAppSheet<void>(
                context,
                heightFactor: 0.94,
                child: const DeviceSecurityScreen(),
              ),
            ),
          ]),
        ],
      ],
    );
  }
}

class _ShieldCard extends StatelessWidget {
  final Shield shield;
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
          MaterialPageRoute(builder: (_) => shieldScreen(shield)),
        ),
        child: Row(
          children: [
            // A plain tile: on Home colour says what state a shield is in, so
            // here, where no state is read, the icon carries no colour.
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Brand.glassFill,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Brand.glassBorder),
              ),
              child: Center(
                child: DuotoneIcon(shield.icon, size: 23, color: cs.onSurface),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shield.name,
                      style: BrandText.title(color: cs.onSurface, size: 16)),
                  const SizedBox(height: 3),
                  Text(shield.covers,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          BrandText.body(color: cs.onSurfaceVariant, size: 12.5)
                              .copyWith(height: Brand.bodyHeight(1.3))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DuotoneIcon(AppIcons.chevronRight,
                size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
