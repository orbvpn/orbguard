/// GuardGrid — the "YOUR GUARDS" 2-column tile grid for the home control
/// panel (P4.2).
///
/// Each tile mirrors one REAL [GuardStatus] from [GuardStatusController]'s
/// probes: `active` shows a lime dot + "On", `actionNeeded` shows "+ Set up"
/// (the tile is the in-context ask), and `unavailable` guards are NOT
/// rendered at all — a platform is never shown a control it cannot have.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/home/guard_status_controller.dart';

/// Duotone icon (assets/icons/) for a guard id; unknown ids get the shield.
String guardIconFor(String guardId) => switch (guardId) {
      'spyware_watch' => AppIcons.searchBug, // magnifer_bug
      'firewall' => AppIcons.network, // wi_fi_router
      'sms_filter' => 'chat_round_check',
      'alerts' => AppIcons.bell, // bell
      'breach' => AppIcons.global, // global
      'hidden_vpn' => AppIcons.eyeClosed, // eye_closed
      'malware_scan' => 'virus',
      _ => AppIcons.shieldCheck, // shield_check
    };

class GuardGrid extends StatelessWidget {
  final List<GuardStatus> guards;
  final void Function(String guardId)? onGuardTap;

  const GuardGrid({super.key, required this.guards, this.onGuardTap});

  @override
  Widget build(BuildContext context) {
    // Unavailable guards are hidden — never shown, never greyed-out teased.
    final visible =
        guards.where((g) => g.state != GuardState.unavailable).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (int i = 0; i < visible.length; i += 2)
          Padding(
            padding:
                EdgeInsets.only(bottom: i + 2 < visible.length ? 12 : 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _GuardTile(
                      guard: visible[i],
                      onTap: onGuardTap == null
                          ? null
                          : () => onGuardTap!(visible[i].id),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: i + 1 < visible.length
                        ? _GuardTile(
                            guard: visible[i + 1],
                            onTap: onGuardTap == null
                                ? null
                                : () => onGuardTap!(visible[i + 1].id),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _GuardTile extends StatelessWidget {
  final GuardStatus guard;
  final VoidCallback? onTap;

  const _GuardTile({required this.guard, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool active = guard.state == GuardState.active;

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DuotoneIcon(
                guardIconFor(guard.id),
                size: 22,
                // Lime ink = the kit's live/protected state; idle guards muted.
                color: active ? AppColors.accentInk : cs.onSurfaceVariant,
              ),
              const Spacer(),
              _StateChip(active: active),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            guard.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BrandText.title(size: 14.5, color: cs.onSurface),
          ),
          const SizedBox(height: 3),
          Text(
            guard.detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BrandText.body(size: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// active → lime dot + "On" · actionNeeded → "+ Set up" (amber ask).
class _StateChip extends StatelessWidget {
  final bool active;

  const _StateChip({required this.active});

  @override
  Widget build(BuildContext context) {
    if (active) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accentPill,
          borderRadius: BorderRadius.circular(Brand.rPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentInk,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'On',
              style: BrandText.mono(
                  size: 11, color: AppColors.accentInk, weight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.severityLow.withAlpha(26),
        borderRadius: BorderRadius.circular(Brand.rPill),
      ),
      child: Text(
        '+ Set up',
        style: BrandText.mono(
            size: 11, color: AppColors.amberInk, weight: FontWeight.w600),
      ),
    );
  }
}
