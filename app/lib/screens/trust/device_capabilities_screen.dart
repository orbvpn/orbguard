// Device Capabilities — "What OrbGuard can do on this device" (Phase 3.2).
//
// The honest capability matrix. Every protection area OrbGuard offers, shown
// with the truthful status for the CURRENT platform: fully available,
// limited (with the reason), or not available on this OS (with the reason
// AND what we check instead). This screen exists so a user never expects a
// protection their operating system does not allow.
//
// ── Honesty contract (read before editing) ─────────────────────────────────
// This is a reference screen, not a scan — every row is a static fact about
// what the OS allows, computed instantly from the platform. Never upgrade a
// status here without a real capability behind it elsewhere in the app,
// and never soften a genuine "not available" into "limited" to look better.
// A missing capability is framed as the OS protecting its users (the same
// sandboxing that keeps OTHER apps out of yours) — never as a weakness, and
// never in alarm red; see [_statusColor].

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

/// Whether a protection area works fully, partially, or not at all on the
/// current platform. This is a CAPABILITY signal, not a threat verdict —
/// never colored as danger (see [_statusColor]).
enum _CapabilityStatus { available, limited, unavailable }

/// One row of the capability matrix: a protection area plus its honest
/// status and plain-English explanation for the CURRENT platform.
@immutable
class _CapabilityRow {
  final String id;
  final String icon;
  final String area;
  final _CapabilityStatus status;
  final String explanation;

  const _CapabilityRow({
    required this.id,
    required this.icon,
    required this.area,
    required this.status,
    required this.explanation,
  });
}

/// Short, friendly device noun for body copy ("this Mac", "this iPhone"…).
String _platformNoun(TargetPlatform platform) => switch (platform) {
      TargetPlatform.iOS => 'iPhone',
      TargetPlatform.android => 'Android phone',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows PC',
      TargetPlatform.linux => 'Linux desktop',
      TargetPlatform.fuchsia => 'device',
    };

/// Computes the 7-row capability matrix for [platform]. Every status +
/// explanation here is grounded in a REAL engine elsewhere in the app (see
/// the file header) — this function only re-expresses those honestly.
List<_CapabilityRow> _capabilityRows(TargetPlatform platform) {
  final isIOS = platform == TargetPlatform.iOS;
  final isAndroid = platform == TargetPlatform.android;
  final isDesktop = platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
  final noun = _platformNoun(platform);

  return [
    _CapabilityRow(
      id: 'spyware',
      icon: AppIcons.forensics,
      area: 'Spyware & Pegasus scan',
      status: isIOS
          ? _CapabilityStatus.unavailable
          : isAndroid
              ? _CapabilityStatus.available
              : _CapabilityStatus.limited,
      explanation: isIOS
          ? 'iOS sandboxes every app, so no tool — including OrbGuard — can '
              "scan other apps for malware. Here's what we check instead: "
              'jailbreak status, screen recording, and proxy or certificate '
              'interception — the conditions spyware like Pegasus needs.'
          : isAndroid
              ? 'OrbGuard analyzes system logs, installed apps, and '
                  'research-grade indicators of compromise to flag '
                  'sophisticated spyware such as Pegasus, Predator, and '
                  'commercial stalkerware.'
              : 'Pegasus-class spyware targets phones, not desktops, so '
                  "there's no phone-artifact scan here. OrbGuard still runs "
                  'a general scan for known malware indicators on this '
                  '$noun.',
    ),
    _CapabilityRow(
      id: 'stalkerware',
      icon: 'eye_closed',
      area: 'Stalkerware & trackers',
      status:
          isAndroid ? _CapabilityStatus.available : _CapabilityStatus.limited,
      explanation: isAndroid
          ? 'OrbGuard inspects installed apps, risky permissions, and '
              'abused accessibility-service access — the exact mechanism '
              'most stalkerware relies on to hide and spy.'
          : isIOS
              ? 'iOS keeps every app sandboxed from inspecting others, so '
                  "OrbGuard can't list what's installed or which permissions "
                  'another app holds. We show a reference catalog of known '
                  "trackers and point you to iPhone's own camera/mic "
                  'indicator dots and Settings > Privacy for a manual check.'
              : "Classic phone stalkerware isn't a desktop pattern. Instead "
                  'OrbGuard watches startup items and running processes for '
                  'hidden monitoring tools on this $noun.',
    ),
    _CapabilityRow(
      id: 'scam',
      icon: 'danger_triangle',
      area: 'Scam text, link & QR',
      status: _CapabilityStatus.available,
      explanation: isDesktop
          ? 'Paste a suspicious text, link, or phone number for the same '
              'instant scam check as mobile. Scanning a QR code needs a '
              'device with a camera.'
          : 'Paste a suspicious text, link, or phone number for an instant '
              'scam check, or scan a QR code with your camera.',
    ),
    _CapabilityRow(
      id: 'vpn_proxy',
      icon: 'wi_fi_router',
      area: 'Hidden VPN & proxy',
      status: _CapabilityStatus.available,
      explanation: isAndroid
          ? 'OrbGuard checks for an active VPN tunnel or system proxy '
              'quietly rerouting your traffic, and lists other VPN apps '
              'installed on this phone.'
          : 'OrbGuard checks for an active VPN tunnel or system proxy '
              'quietly rerouting your traffic on this $noun.',
    ),
    _CapabilityRow(
      id: 'secure_call',
      icon: 'phone_calling',
      area: 'Secure-call device posture',
      status: isDesktop
          ? _CapabilityStatus.unavailable
          : _CapabilityStatus.available,
      explanation: isDesktop
          ? 'Not available on desktop: OrbGuard runs this device-posture '
              'check on a phone (iPhone or Android) — a $noun doesn\'t '
              'carry the call posture this check looks for.'
          : 'Before a sensitive call, OrbGuard checks this device for '
              'screen recording, risky accessibility access, network '
              'interception, and jailbreak or root — the conditions an '
              'eavesdropper would need first.',
    ),
    _CapabilityRow(
      id: 'dark_web',
      icon: 'global',
      area: 'Dark-web & breach lookup',
      status: _CapabilityStatus.available,
      explanation: 'OrbGuard checks your email, phone number, or password '
          "against known breach databases. It's the same everywhere — a "
          'lookup, not a device scan.',
    ),
    _CapabilityRow(
      id: 'firewall',
      icon: AppIcons.firewall,
      area: 'Firewall & network filtering',
      status: (isAndroid || isDesktop)
          ? _CapabilityStatus.available
          : _CapabilityStatus.limited,
      explanation: isAndroid
          ? 'A real on-device DNS filter blocks known-malicious domains '
              'directly on this phone — no server round-trip required.'
          : isDesktop
              ? 'OrbGuard installs real OS firewall rules — pf on Mac, '
                  'netsh on Windows, iptables on Linux — that block '
                  'known-malicious IPs at the network level.'
              : 'On iPhone, OrbGuard filters DNS on-device while '
                  'connected — no MDM required for that. Full system-wide '
                  'content filtering needs enterprise MDM supervision, '
                  "which most personal iPhones don't have.",
    ),
  ];
}

/// Status chip / icon-box color. Deliberately NEVER red — a missing
/// capability here is an OS boundary, not a threat.
Color _statusColor(BuildContext context, _CapabilityStatus status) {
  switch (status) {
    case _CapabilityStatus.available:
      return AppColors.accentInk;
    case _CapabilityStatus.limited:
      return AppColors.amberInk;
    case _CapabilityStatus.unavailable:
      return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

String _statusLabel(_CapabilityStatus status) => switch (status) {
      _CapabilityStatus.available => 'Available',
      _CapabilityStatus.limited => 'Limited',
      _CapabilityStatus.unavailable => 'Not available',
    };

/// **What OrbGuard can do on this device** — the honest per-platform
/// capability matrix (Phase 3.2). Pass [platformOverride] in tests to force
/// a platform; production code falls back to [defaultTargetPlatform].
class DeviceCapabilitiesScreen extends StatelessWidget {
  const DeviceCapabilitiesScreen({super.key, this.platformOverride});

  /// Forces the platform this screen reports on. Tests only — production
  /// leaves this null and gets the real [defaultTargetPlatform].
  final TargetPlatform? platformOverride;

  TargetPlatform get _platform => platformOverride ?? defaultTargetPlatform;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final platform = _platform;
    final noun = _platformNoun(platform);
    final rows = _capabilityRows(platform);

    final available =
        rows.where((r) => r.status == _CapabilityStatus.available).length;
    final limited =
        rows.where((r) => r.status == _CapabilityStatus.limited).length;
    final unavailable = rows.length - available - limited;

    return GlassPage(
      title: 'What OrbGuard can do',
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const SizedBox(height: 4),
          Text(
            'ON YOUR ${noun.toUpperCase()}',
            style: BrandText.label(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            "Here's exactly what OrbGuard can check on this device — and an "
            'honest answer everywhere the operating system draws the line.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 14.5),
          ),
          const SizedBox(height: 16),
          _SummaryStrip(
              available: available, limited: limited, unavailable: unavailable),
          const SizedBox(height: 20),
          ...rows.map((r) => _CapabilityCard(row: r)),
          const SizedBox(height: 4),
          _HonestyFooter(platformNoun: noun),
        ],
      ),
    );
  }
}

/// At-a-glance counts across the three statuses.
class _SummaryStrip extends StatelessWidget {
  final int available;
  final int limited;
  final int unavailable;

  const _SummaryStrip({
    required this.available,
    required this.limited,
    required this.unavailable,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            count: available,
            label: 'Available',
            color: AppColors.accentInk,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            count: limited,
            label: 'Limited',
            color: AppColors.amberInk,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            count: unavailable,
            label: 'Not available',
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _StatChip({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: BrandText.heading(color: color, size: 21)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: BrandText.label(color: color, size: 10),
          ),
        ],
      ),
    );
  }
}

/// One protection area: icon, title, honest status chip, and the plain-
/// English explanation. Keyed by [_CapabilityRow.id] so tests can target a
/// specific row without depending on layout or ordering.
class _CapabilityCard extends StatelessWidget {
  final _CapabilityRow row;
  const _CapabilityCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _statusColor(context, row.status);

    return GlassCard(
      key: ValueKey('capability_${row.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: DuotoneIcon(row.icon, size: 22, color: color),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.area,
                      style: BrandText.title(color: cs.onSurface, size: 15),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withAlpha(28),
                        borderRadius:
                            BorderRadius.circular(GlassTheme.radiusXSmall),
                      ),
                      child: Text(
                        _statusLabel(row.status),
                        style: BrandText.label(color: color, size: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            row.explanation,
            style: BrandText.body(color: cs.onSurfaceVariant, size: 13),
          ),
        ],
      ),
    );
  }
}

/// Closing honesty note: frames every gap above as the OS protecting its
/// users, never as OrbGuard cutting a corner.
class _HonestyFooter extends StatelessWidget {
  final String platformNoun;
  const _HonestyFooter({required this.platformNoun});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon(AppIcons.infoCircle,
                  size: 18, color: AppColors.secondaryInk),
              const SizedBox(width: 8),
              Text(
                "WHY SOME CHECKS AREN'T HERE",
                style: BrandText.label(color: AppColors.secondaryInk),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Every phone and computer sandboxes apps away from each other on '
            "purpose — it's the same protection that keeps other apps from "
            'reading yours. When OrbGuard says a check is limited or not '
            'available on your $platformNoun, that\'s the operating system '
            'telling the truth, not OrbGuard cutting a corner.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 13.5),
          ),
        ],
      ),
    );
  }
}
