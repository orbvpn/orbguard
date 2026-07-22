// lib/screens/onboarding/permission_priming_screen.dart
//
// First-run permission priming — value-first, one honest ask per step.
//
// Shown once, right after onboarding (gated by the [kPermissionsPrimedPrefsKey]
// prefs flag). Each step primes a permission with its plain-English value
// BEFORE the OS dialog fires, Norton/Bitdefender-style; every step is
// independently skippable, and a persistent "Skip for now" opts out of the
// whole flow. Once every one-tap step is decided, the single lime CTA
// becomes "Run my first check" and hands control back via [onDone] — the
// parent decides what runs next (it should kick off the first checkup
// immediately).
//
// Honesty rules baked in:
//  • a step only shows the lime "On" chip when the post-request state really
//    is granted (the injected request functions return that state);
//  • denied and skipped read the same calm way — no guilt-tripping;
//  • the advanced steps say they open system Settings and NEVER claim to be
//    on afterwards (we can't verify them from here).

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../permissions/special_permissions_manager.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/notifications/notification_service.dart';
import 'priming_copy.dart';

/// Prefs flag set (true) before [PermissionPrimingScreen.onDone] fires — the
/// parent gates the priming screen on this exact key.
const String kPermissionsPrimedPrefsKey = 'permissions_primed';

/// The injectable bundle of permission request functions the priming screen
/// fires. Production wiring comes from [PrimingRequests.production]; tests
/// inject fakes so no platform channel is ever touched.
///
/// The four `request*` functions must return the REAL post-request granted
/// state — the screen renders exactly what they report. The two `open*`
/// functions only deep-link into system Settings (their outcome cannot be
/// confirmed from here, and the UI says so).
class PrimingRequests {
  final Future<bool> Function() requestNotifications;
  final Future<bool> Function() requestSms;
  final Future<bool> Function() requestLocation;
  final Future<void> Function() openUsageAccess;
  final Future<void> Function() openAccessibility;

  const PrimingRequests({
    required this.requestNotifications,
    required this.requestSms,
    required this.requestLocation,
    required this.openUsageAccess,
    required this.openAccessibility,
  });

  /// Default wiring onto the app's existing permission plumbing:
  ///
  ///  • notifications — [NotificationService.requestPermissions] fires the OS
  ///    prompt (its own bool only reflects the plugin call), then
  ///    `Permission.notification.isGranted` is read back as the source of
  ///    truth for what the chip may claim;
  ///  • SMS / location — permission_handler requests, status read from the
  ///    returned [PermissionStatus];
  ///  • usage access / accessibility — [SpecialPermissionsManager] deep-links
  ///    into system Settings.
  factory PrimingRequests.production() {
    final specialPermissions = SpecialPermissionsManager();
    return PrimingRequests(
      requestNotifications: () async {
        try {
          await NotificationService.instance.requestPermissions();
        } catch (_) {
          // Service plugin unavailable — fall back so first run still asks.
          try {
            await Permission.notification.request();
          } catch (_) {}
        }
        // Honesty: report the real post-request state, not the call result.
        try {
          return await Permission.notification.isGranted;
        } catch (_) {
          return false;
        }
      },
      requestSms: () async => (await Permission.sms.request()).isGranted,
      requestLocation: () async =>
          (await Permission.location.request()).isGranted,
      openUsageAccess: specialPermissions.requestUsageStatsPermission,
      openAccessibility: specialPermissions.requestAccessibilityPermission,
    );
  }
}

/// Lifecycle of one step card.
enum _StepState {
  /// Not decided yet — Allow/Skip buttons showing.
  idle,

  /// Request in flight — button shows a spinner, taps ignored.
  requesting,

  /// The request function reported the permission really is on.
  granted,

  /// User skipped, or the OS denied — same calm state either way.
  skipped,

  /// Advanced step: Settings was opened; outcome unknowable from here.
  openedSettings,
}

/// Staged first-run permission priming. See the library doc above for the
/// flow contract; [onDone] is the ONLY exit and always fires after the
/// [kPermissionsPrimedPrefsKey] prefs flag is persisted.
class PermissionPrimingScreen extends StatefulWidget {
  /// Called when the user finishes ("Run my first check") or opts out
  /// ("Skip for now") — after the prefs flag is set.
  final VoidCallback onDone;

  /// Test hook: forces the step set for a platform. Defaults to
  /// [defaultTargetPlatform].
  final TargetPlatform? platformOverride;

  /// Test hook: injected request functions. Defaults to
  /// [PrimingRequests.production].
  final PrimingRequests? requests;

  const PermissionPrimingScreen({
    super.key,
    required this.onDone,
    this.platformOverride,
    this.requests,
  });

  @override
  State<PermissionPrimingScreen> createState() =>
      _PermissionPrimingScreenState();
}

class _PermissionPrimingScreenState extends State<PermissionPrimingScreen> {
  late final PrimingRequests _requests =
      widget.requests ?? PrimingRequests.production();
  late final List<PrimingStep> _steps =
      primingStepsFor(widget.platformOverride ?? defaultTargetPlatform);

  final Map<String, _StepState> _states = {};
  bool _finishing = false;

  _StepState _stateOf(PrimingStep step) => _states[step.id] ?? _StepState.idle;

  bool _isDecided(PrimingStep step) {
    final state = _stateOf(step);
    return state == _StepState.granted || state == _StepState.skipped;
  }

  List<PrimingStep> get _coreSteps =>
      _steps.where((s) => !s.opensSystemSettings).toList();

  List<PrimingStep> get _advancedSteps =>
      _steps.where((s) => s.opensSystemSettings).toList();

  /// The one-tap steps are all decided — the advanced Settings deep-links
  /// never gate the CTA (they're optional and unverifiable from here).
  bool get _allCoreDecided => _coreSteps.every(_isDecided);

  Future<void> _allow(PrimingStep step) async {
    if (_stateOf(step) == _StepState.requesting) return;
    setState(() => _states[step.id] = _StepState.requesting);

    var granted = false;
    try {
      granted = await _dispatch(step);
    } catch (_) {
      granted = false; // Never claim "On" if the request itself failed.
    }

    if (!mounted) return;
    setState(() {
      _states[step.id] = step.opensSystemSettings
          ? _StepState.openedSettings
          : (granted ? _StepState.granted : _StepState.skipped);
    });
  }

  Future<bool> _dispatch(PrimingStep step) async {
    switch (step.id) {
      case PrimingStepIds.notifications:
        return _requests.requestNotifications();
      case PrimingStepIds.sms:
        return _requests.requestSms();
      case PrimingStepIds.location:
        return _requests.requestLocation();
      case PrimingStepIds.usageAccess:
        await _requests.openUsageAccess();
        return false; // Unverifiable — card shows the "opened" state instead.
      case PrimingStepIds.accessibility:
        await _requests.openAccessibility();
        return false;
    }
    return false;
  }

  void _skip(PrimingStep step) {
    if (_stateOf(step) == _StepState.requesting) return;
    setState(() => _states[step.id] = _StepState.skipped);
  }

  /// The only exit: persist the priming flag, then hand off to the parent.
  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPermissionsPrimedPrefsKey, true);
    } catch (_) {
      // A prefs failure must never trap the user on this screen.
    }
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final advanced = _advancedSteps;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // Persistent opt-out — same idiom as the onboarding slides.
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: Text('Skip for now',
                      style: BrandText.label(color: cs.onSurfaceVariant)),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                children: [
                  _buildHeader(cs),
                  const SizedBox(height: 20),
                  for (final step in _coreSteps) _buildStep(step),
                  if (advanced.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    const GlassSectionHeader(title: 'Advanced — optional'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(
                        'These two open system Settings — you finish '
                        'turning them on there.',
                        style:
                            BrandText.body(color: cs.onSurfaceVariant, size: 13),
                      ),
                    ),
                    for (final step in advanced) _buildStep(step),
                  ],
                ],
              ),
            ),
            _buildFooter(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Turn on your protection.',
            style: BrandText.display(color: cs.onSurface, size: 30)),
        const SizedBox(height: 10),
        Text(
          'Each permission unlocks part of your first checkup. Allow what '
          "you're comfortable with — skip anything, and change your mind "
          'later in Settings.',
          style: BrandText.body(color: cs.onSurfaceVariant, size: 15),
        ),
      ],
    );
  }

  Widget _buildStep(PrimingStep step) {
    return _StepCard(
      key: ValueKey('priming_step_${step.id}'),
      step: step,
      state: _stateOf(step),
      onAllow: () => _allow(step),
      onSkip: () => _skip(step),
    );
  }

  Widget _buildFooter(ColorScheme cs) {
    final core = _coreSteps;
    final decided = core.where(_isDecided).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: _allCoreDecided
          // The single lime action on this screen: finish and go check.
          ? BrandButton(
              label: 'Run my first check',
              expand: true,
              onPressed: _finish,
            )
          : Text(
              '$decided of ${core.length} decided · change anytime in Settings',
              textAlign: TextAlign.center,
              style: BrandText.mono(color: cs.onSurfaceVariant, size: 12),
            ),
    );
  }
}

/// One permission step card: icon, title, the one-sentence WHY, then either
/// the Allow/Skip actions or the honest resolved state.
class _StepCard extends StatelessWidget {
  final PrimingStep step;
  final _StepState state;
  final VoidCallback onAllow;
  final VoidCallback onSkip;

  const _StepCard({
    super.key,
    required this.step,
    required this.state,
    required this.onAllow,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final granted = state == _StepState.granted;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassDuotoneIconBox(
                icon: step.icon,
                // Lime ink only once the permission really is on.
                color: granted ? AppColors.accentInk : cs.onSurfaceVariant,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title,
                        style: BrandText.title(color: cs.onSurface)),
                    const SizedBox(height: 3),
                    Text(step.value,
                        style: BrandText.body(
                            color: cs.onSurfaceVariant, size: 14)),
                    if (step.opensSystemSettings) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          DuotoneIcon(AppIcons.settings,
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 5),
                          Text('Opens system Settings',
                              style: BrandText.label(
                                  color: cs.onSurfaceVariant, size: 12)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAction(cs),
        ],
      ),
    );
  }

  Widget _buildAction(ColorScheme cs) {
    switch (state) {
      case _StepState.idle:
      case _StepState.requesting:
        final requesting = state == _StepState.requesting;
        return Row(
          children: [
            BrandButton.secondary(
              label: step.buttonLabel,
              onPressed: requesting ? null : onAllow,
              isLoading: requesting,
              expand: false,
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: requesting ? null : onSkip,
              child:
                  Text('Skip', style: BrandText.label(color: cs.onSurfaceVariant)),
            ),
          ],
        );
      case _StepState.granted:
        // Live "On" chip — lime is status ink here, per the kit's
        // only-the-active-item-takes-lime rule.
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentPill,
            borderRadius: BorderRadius.circular(GlassTheme.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DuotoneIcon(AppIcons.checkCircle,
                  size: 14, color: AppColors.accentInk),
              const SizedBox(width: 5),
              Text('On',
                  style: BrandText.label(
                      color: AppColors.accentInk, weight: FontWeight.w600)),
            ],
          ),
        );
      case _StepState.skipped:
        return Text('Skipped — you can enable later in Settings',
            style: BrandText.label(color: cs.onSurfaceVariant));
      case _StepState.openedSettings:
        // Honest: we cannot confirm these from here, so never claim "On".
        return Text('Opened system Settings — finish turning it on there.',
            style: BrandText.label(color: cs.onSurfaceVariant));
    }
  }
}
