// Hidden VPN & Proxy Watch (Phase 2.3) — "Is your traffic being secretly
// rerouted?"
//
// A calm, plain-English consumer screen over [VpnProxyDetector]. It gives one
// honest verdict, shows the underlying signals (active tunnel? system proxy?
// on Android: which VPN apps are installed, with OrbVPN recognised and never
// flagged), is explicit about what a given platform cannot check, and guides
// the user to their system VPN settings. It NEVER claims to silently turn off
// another app's VPN — detect and guide only.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/network_firewall_provider.dart';
import '../../services/security/vpn_proxy_detector.dart';
import '../../services/security/vpn_watch.dart';
import '../../utils/platform_info.dart';
import '../../widgets/scan_credits/scan_gate.dart';

class HiddenVpnProxyScreen extends StatefulWidget {
  const HiddenVpnProxyScreen({
    super.key,
    VpnProxyDetector? detector,
    VpnWatch? watch,
    this.ownFirewallOn,
  })  : _detector = detector,
        _watch = watch;

  /// Injectable for tests/previews. A [detector] alone gets a watch of its
  /// own; with neither, the screen answers [VpnWatch.shared], the same watch
  /// Home reads.
  final VpnProxyDetector? _detector;
  final VpnWatch? _watch;

  /// Whether OrbGuard's own tracker firewall is running now. Defaults to the
  /// [NetworkFirewallProvider] above the screen, then to what Home last told
  /// the watch, then to false.
  final bool Function()? ownFirewallOn;

  @override
  State<HiddenVpnProxyScreen> createState() => _HiddenVpnProxyScreenState();
}

class _HiddenVpnProxyScreenState extends State<HiddenVpnProxyScreen> {
  late final VpnWatch _watch = widget._watch ??
      (widget._detector != null
          ? VpnWatch(detector: widget._detector)
          : VpnWatch.shared);

  VpnProxyStatus? _status;
  bool _loading = true;
  bool _showGuide = false;

  /// The watch's answer behind [_status]: true when something active is
  /// neither OrbGuard's firewall nor the person's own.
  bool? _unknown;
  bool _mine = false;

  /// The tunnel is OrbGuard's own firewall (native fact, else the flag).
  bool _firewall = false;

  /// The tunnel is treated as the person's own because genuine OrbVPN is
  /// installed (Android, signature checked natively).
  bool _orbVpn = false;

  @override
  void initState() {
    super.initState();
    // A subscriber's look starts with the screen. For anyone else a new look
    // is theirs to start, since it is a check to pay for: the screen opens
    // on what the watch last saw (Home asks the watch by itself, and that is
    // never counted), or on nothing when it has not looked yet.
    if (checksAreUnlimited(context)) {
      _check();
    } else if (_watch.lastStatus != null) {
      _showLast();
    } else {
      _loading = false;
    }
  }

  /// Shows what the watch last saw, without a new look.
  Future<void> _showLast() async {
    await _reanswer();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// The button and the pull: a new look, which a person starts.
  Future<void> _startCheck() async {
    if (!await ensureScanCredit(context) || !mounted) return;
    await _check();
  }

  bool _firewallOn() {
    final injected = widget.ownFirewallOn;
    if (injected != null) return injected();
    final provider =
        Provider.of<NetworkFirewallProvider?>(context, listen: false);
    return provider?.isEnabled ?? _watch.lastOwnFirewallOn ?? false;
  }

  Future<void> _check() async {
    setState(() => _loading = true);
    final firewall = _firewallOn();
    final unknown =
        await _watch.unknownVpnActive(ownFirewallOn: firewall, force: true);
    await _readAnswer(unknown);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Re-reads the answer from the last look (no new look).
  Future<void> _reanswer() async {
    final firewall = _firewallOn();
    final unknown = await _watch.lastAnswer(ownFirewallOn: firewall);
    await _readAnswer(unknown);
  }

  Future<void> _readAnswer(bool? unknown) async {
    final mine = await _watch.saidItIsMine;
    if (!mounted) return;
    setState(() {
      _status = _watch.lastStatus;
      _unknown = unknown;
      _mine = mine;
      _firewall = _watch.lastTunnelIsOwnFirewall;
      _orbVpn = _watch.lastTunnelTreatedAsOrbVpn;
    });
  }

  Future<void> _markMine() async {
    await _watch.markAsMine();
    await _reanswer();
  }

  Future<void> _forgetMine() async {
    await _watch.forgetMine();
    await _reanswer();
  }

  Future<void> _openVpnSettings() async {
    final opened = await _watch.detector.openSystemVpnSettings();
    if (!mounted) return;
    if (opened) return;
    // No settings deep-link on this build — reveal the written steps instead of
    // pretending a button did something.
    setState(() => _showGuide = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_settingsHint())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Hidden VPN & proxy',
      body: _loading
          ? _buildLoading(context)
          : _status == null
              ? _buildNotLooked(context)
              : _buildResult(context, _status!),
    );
  }

  /// Nothing has been looked at yet: what the check is, and the one action
  /// that starts it.
  Widget _buildNotLooked(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color ink = cs.onSurfaceVariant;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ink.withAlpha(28),
              border: Border.all(color: ink.withAlpha(90), width: 2),
            ),
            child: Center(
                child: DuotoneIcon(AppIcons.route, size: 44, color: ink)),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Not checked yet',
          textAlign: TextAlign.center,
          style: BrandText.h2(color: cs.onSurface, size: 25),
        ),
        const SizedBox(height: 8),
        Text(
          'This looks for an active VPN tunnel or a system proxy on this '
          'device.',
          textAlign: TextAlign.center,
          style: BrandText.body(color: cs.onSurfaceVariant, size: 14.5),
        ),
        const SizedBox(height: 24),
        // The one primary action.
        BrandButton(
          label: 'Check now',
          expand: true,
          onPressed: _startCheck,
        ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.accentInk),
          const SizedBox(height: 18),
          Text(
            'Checking whether your traffic is being rerouted…',
            textAlign: TextAlign.center,
            style: BrandText.body(color: context.colors.onSurfaceVariant, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, VpnProxyStatus s) {
    final cs = Theme.of(context).colorScheme;
    final v = _visuals(context, s.verdict, calm: _calm(s));

    return RefreshIndicator(
      color: AppColors.accentInk,
      onRefresh: _startCheck,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const SizedBox(height: 8),

          // ── Verdict hero ────────────────────────────────────────────────
          Center(
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: v.ring.withAlpha(28),
                border: Border.all(color: v.ring.withAlpha(90), width: 2),
              ),
              child: Center(child: DuotoneIcon(v.icon, size: 44, color: v.ink)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            v.headline,
            textAlign: TextAlign.center,
            style: BrandText.h2(
                color: s.verdict == RerouteVerdict.clear ? v.ink : cs.onSurface,
                size: 25),
          ),
          const SizedBox(height: 8),
          Text(
            _subline(s),
            textAlign: TextAlign.center,
            style: BrandText.body(color: cs.onSurfaceVariant, size: 14.5),
          ),
          if (s.verdict == RerouteVerdict.active)
            ..._buildOwnership(context, s),
          const SizedBox(height: 24),

          // ── The two core signals ────────────────────────────────────────
          GlassCard(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _SignalRow(
                  icon: AppIcons.route,
                  label: 'VPN tunnel',
                  state: s.activeTunnel,
                  activeText: 'Active',
                  clearText: 'Not detected',
                ),
                Divider(height: 20, color: cs.onSurface.withAlpha(15)),
                _SignalRow(
                  icon: AppIcons.global,
                  label: 'System proxy',
                  state: s.systemProxy,
                  activeText: s.proxyHost == null
                      ? 'Active'
                      : 'Active at ${s.proxyHost}',
                  clearText: 'Not detected',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Installed VPN apps (Android) ────────────────────────────────
          if (s.installedVpnApps.isNotEmpty) ...[
            _buildInstalledApps(context, s),
            const SizedBox(height: 14),
          ],

          // ── What we couldn't check here (honesty) ───────────────────────
          if (s.limitations.isNotEmpty) ...[
            _buildLimitations(context, s),
            const SizedBox(height: 14),
          ],

          // ── Manage / guide ──────────────────────────────────────────────
          _buildManage(context, s),
          const SizedBox(height: 20),

          // ── The one primary action ──────────────────────────────────────
          BrandButton(
            label: 'Check again',
            expand: true,
            onPressed: _startCheck,
          ),
        ],
      ),
    );
  }

  /// Only OrbGuard's own firewall is active: nothing for the person to answer.
  bool _firewallOnly(VpnProxyStatus s) =>
      _firewall &&
      s.activeTunnel == TriState.yes &&
      s.systemProxy != TriState.yes;

  /// Only a tunnel is active and genuine OrbVPN is installed: treated as
  /// theirs, so nothing is asked, and the screen says why.
  bool _orbVpnOnly(VpnProxyStatus s) =>
      _orbVpn &&
      s.activeTunnel == TriState.yes &&
      s.systemProxy != TriState.yes;

  /// Everything active is accounted for (OrbGuard's firewall, OrbVPN, or
  /// what the person said is theirs): no amber alarm.
  bool _calm(VpnProxyStatus s) =>
      s.verdict == RerouteVerdict.active && _unknown == false;

  /// Under the explanation: ask once whether what is active is theirs, or
  /// say what they answered, with a way to take it back.
  List<Widget> _buildOwnership(BuildContext context, VpnProxyStatus s) {
    final cs = Theme.of(context).colorScheme;
    final line = BrandText.body(color: cs.onSurface, size: 14);
    if (_firewallOnly(s)) {
      return [
        const SizedBox(height: 14),
        Text('This tunnel is OrbGuard’s own tracker firewall.',
            textAlign: TextAlign.center, style: line),
      ];
    }
    if (_orbVpnOnly(s)) {
      return [
        const SizedBox(height: 14),
        Text(
            'A VPN is active. OrbVPN is installed on this phone, so OrbGuard '
            'treats it as yours. Android does not tell any app which app runs '
            'a VPN.',
            textAlign: TextAlign.center,
            style: line),
      ];
    }
    if (_mine) {
      return [
        const SizedBox(height: 14),
        Text('You told OrbGuard this one is yours.',
            textAlign: TextAlign.center, style: line),
        const SizedBox(height: 2),
        Center(
          child: TextButton(
            onPressed: _forgetMine,
            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
            child: Text('It is not mine any more',
                style: BrandText.title(
                    size: 14,
                    weight: FontWeight.w500,
                    color: cs.onSurfaceVariant)),
          ),
        ),
      ];
    }
    if (_unknown != true) return const [];
    // Name what is still unanswered: the tunnel unless the firewall or
    // OrbVPN accounts for it.
    final onlyProxy = s.systemProxy == TriState.yes &&
        (s.activeTunnel != TriState.yes || _firewall || _orbVpn);
    return [
      const SizedBox(height: 16),
      BrandButton.secondary(
        label: onlyProxy ? 'This proxy is mine' : 'This VPN is mine',
        expand: true,
        onPressed: _markMine,
      ),
    ];
  }

  Widget _buildInstalledApps(BuildContext context, VpnProxyStatus s) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VPN apps on this phone',
              style: BrandText.title(color: cs.onSurface, size: 15)),
          const SizedBox(height: 4),
          Text(
            'These apps can route your traffic. Android can’t tell us which one '
            '(if any) is active right now.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5),
          ),
          const SizedBox(height: 12),
          ...s.installedVpnApps.map((a) => _VpnAppRow(app: a)),
        ],
      ),
    );
  }

  Widget _buildLimitations(BuildContext context, VpnProxyStatus s) {
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
              Text('What we can’t check on ${_inSentence(s.platformLabel)}',
                  style: BrandText.title(color: cs.onSurface, size: 14)),
            ],
          ),
          const SizedBox(height: 10),
          ...s.limitations.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(l,
                        style: BrandText.body(
                            color: cs.onSurfaceVariant, size: 12.5)),
                  ),
                ],
              ),
            ),
          ),
          if (s.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(s.errorMessage!,
                style: BrandText.body(
                    color: cs.onSurfaceVariant, size: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildManage(BuildContext context, VpnProxyStatus s) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manage or turn this off',
              style: BrandText.title(color: cs.onSurface, size: 15)),
          const SizedBox(height: 6),
          Text(
            'OrbGuard never switches off another app’s VPN for you. You stay in '
            'control. Open your system settings to review or disconnect it.',
            style: BrandText.body(color: cs.onSurfaceVariant, size: 12.5),
          ),
          const SizedBox(height: 12),
          BrandButton.secondary(
            label: 'Open VPN settings',
            expand: true,
            onPressed: _openVpnSettings,
          ),
          if (_showGuide) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.onSurface.withAlpha(10),
                borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DuotoneIcon(AppIcons.route,
                      size: 18, color: AppColors.accentInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_settingsHint(),
                        style: BrandText.body(
                            color: cs.onSurface, size: 12.5)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _subline(VpnProxyStatus s) {
    switch (s.verdict) {
      case RerouteVerdict.active:
        final bits = <String>[];
        if (s.activeTunnel == TriState.yes) bits.add('a VPN tunnel');
        if (s.systemProxy == TriState.yes) bits.add('a system proxy');
        final what = bits.isEmpty ? 'a reroute' : bits.join(' and ');
        final owner = _ownerHint(s);
        return 'Your internet traffic is going through $what.$owner';
      case RerouteVerdict.clear:
        return 'Nothing is sitting between ${_inSentence(s.platformLabel)} and '
            'the internet right now.';
      case RerouteVerdict.inconclusive:
        return 'No active VPN or proxy was found, but some checks aren’t '
            'available on ${_inSentence(s.platformLabel)}. See below.';
      case RerouteVerdict.unavailable:
        return 'This check isn’t available on ${_inSentence(s.platformLabel)}.';
    }
  }

  /// Hedged ownership hint — Android/iOS can't name the tunnel owner, so we
  /// never assert it.
  String _ownerHint(VpnProxyStatus s) {
    if (s.activeTunnel != TriState.yes) return '';
    if (s.orbVpnInstalled && s.otherVpnApps.isEmpty) {
      return ' This is most likely your OrbVPN.';
    }
    if (s.installedVpnApps.isNotEmpty) {
      return ' It’s likely one of your VPN apps.';
    }
    return '';
  }

  String _settingsHint() {
    if (PlatformInfo.isAndroid) {
      return 'Open Settings, then Network & internet, then VPN, and disconnect '
          'or remove any VPN you don’t recognise. For a proxy: open Settings, '
          'then Wi-Fi, then your network, then Proxy.';
    }
    if (PlatformInfo.isIOS) {
      return 'Open Settings, then General, then VPN & Device Management, and '
          'review or delete any VPN profile you don’t recognise.';
    }
    if (PlatformInfo.isMacOS) {
      return 'Open System Settings, then Network, then VPN, and disconnect any '
          'VPN you don’t recognise.';
    }
    if (PlatformInfo.isWindows) {
      return 'Open Settings, then Network & internet, then VPN & proxy, and '
          'disconnect anything you don’t recognise.';
    }
    return 'Open your system network settings, then VPN, and disconnect any '
        'VPN you don’t recognise.';
  }

  _VerdictVisuals _visuals(BuildContext context, RerouteVerdict verdict,
      {bool calm = false}) {
    if (calm && verdict == RerouteVerdict.active) {
      // Still active (the headline says so), drawn in the calm tone.
      return _VerdictVisuals(
        ring: AppColors.success,
        ink: AppColors.accentInk,
        icon: AppIcons.route,
        headline: 'A VPN or proxy is active',
      );
    }
    switch (verdict) {
      case RerouteVerdict.clear:
        return _VerdictVisuals(
          ring: AppColors.success,
          ink: AppColors.accentInk,
          icon: AppIcons.shieldCheck,
          headline: 'No hidden VPN or proxy',
        );
      case RerouteVerdict.active:
        return _VerdictVisuals(
          ring: AppColors.severityLow,
          ink: AppColors.amberInk,
          icon: AppIcons.route,
          headline: 'A VPN or proxy is active',
        );
      case RerouteVerdict.inconclusive:
        return _VerdictVisuals(
          ring: AppColors.info,
          ink: AppColors.secondaryInk,
          icon: AppIcons.shieldKeyhole,
          headline: 'No active VPN or proxy found',
        );
      case RerouteVerdict.unavailable:
        return _VerdictVisuals(
          ring: context.colors.onSurfaceVariant,
          ink: context.colors.onSurfaceVariant,
          icon: AppIcons.infoCircle,
          headline: 'Can’t check on this device',
        );
    }
  }
}

class _VerdictVisuals {
  final Color ring;
  final Color ink;
  final String icon;
  final String headline;
  const _VerdictVisuals({
    required this.ring,
    required this.ink,
    required this.icon,
    required this.headline,
  });
}

/// One tunnel/proxy signal row with an honest tri-state chip.
class _SignalRow extends StatelessWidget {
  final String icon;
  final String label;
  final TriState state;
  final String activeText;
  final String clearText;

  const _SignalRow({
    required this.icon,
    required this.label,
    required this.state,
    required this.activeText,
    required this.clearText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color ink, String text) = switch (state) {
      TriState.yes => (AppColors.amberInk, activeText),
      TriState.no => (AppColors.accentInk, clearText),
      TriState.unknown => (cs.onSurfaceVariant, 'Can’t check here'),
    };
    return Row(
      children: [
        DuotoneIcon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: BrandText.title(color: cs.onSurface, size: 15)),
        ),
        const SizedBox(width: 10),
        // A long proxy address wraps inside its pill rather than push the
        // row off the screen.
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: ink.withAlpha(28),
              borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            ),
            child: Text(
              text,
              textAlign: TextAlign.end,
              style: BrandText.label(color: ink, size: 11.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// One installed VPN app. OrbVPN is shown as trusted; others are neutral —
/// never a threat.
class _VpnAppRow extends StatelessWidget {
  final InstalledVpnApp app;
  const _VpnAppRow({required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = app.isOrbVpn ? AppColors.accentInk : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          DuotoneIcon(
            app.isOrbVpn ? AppIcons.shieldCheck : AppIcons.wifi,
            size: 20,
            color: ink,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.title(color: cs.onSurface, size: 14)),
                Text(app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BrandText.label(
                        color: cs.onSurfaceVariant, size: 10.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: ink.withAlpha(app.isOrbVpn ? 28 : 18),
              borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            ),
            child: Text(
              app.isOrbVpn ? 'Your OrbVPN, trusted' : 'VPN app',
              style: BrandText.label(color: ink, size: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// A device's label inside a sentence: "This Mac" reads "this Mac", and a
/// proper name keeps its capital.
String _inSentence(String label) =>
    label.isEmpty ? label : label[0].toLowerCase() + label.substring(1);
