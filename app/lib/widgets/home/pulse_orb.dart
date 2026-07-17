/// PulseOrb + LiveDot — the home hero's honest "alive" indicators (P4.2).
///
/// HONESTY CONTRACT: both widgets animate ONLY while [live] is true — i.e.
/// the caller has verified something real is running (guard activeCount > 0).
/// When nothing runs they render statically; they never fake activity.
/// Both respect the OS reduce-motion setting via
/// [MediaQuery.disableAnimationsOf] and fall back to a static frame.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';

/// The verdict orb: a circular ring tinted with the verdict FILL color around
/// a shield [DuotoneIcon] in the verdict INK color. While [live], two slow
/// expanding pulse rings radiate outward on a repeating controller.
class PulseOrb extends StatefulWidget {
  /// Duotone icon name (must exist in assets/icons/).
  final String icon;

  /// Verdict FILL color (ring/tint/pulse) — e.g. `ProtectionVerdict.fill`.
  final Color fill;

  /// Verdict INK color (the glyph) — e.g. `ProtectionVerdict.ink`.
  final Color ink;

  /// True only when something real is running (guards active > 0).
  final bool live;

  /// Diameter of the core ring; the pulse rings expand ~1.55× beyond it.
  final double size;

  /// Tapping the orb runs a scan. When set, the orb reads as a button (press
  /// feedback + a soft glow) — the hero IS the primary scan control.
  final VoidCallback? onTap;

  const PulseOrb({
    super.key,
    required this.icon,
    required this.fill,
    required this.ink,
    required this.live,
    this.size = 116,
    this.onTap,
  });

  @override
  State<PulseOrb> createState() => _PulseOrbState();
}

class _PulseOrbState extends State<PulseOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  bool _reduceMotion = false;
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PulseOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final shouldRun = widget.live && !_reduceMotion;
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.size;
    final double outer = size * 1.6; // contains the fully-expanded pulse ring

    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Pulse rings — rendered only while something REAL runs.
          if (widget.live && !_reduceMotion)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  _pulseRing(phase: 0.0),
                  _pulseRing(phase: 0.5),
                ],
              ),
            ),
          // Core ring + glyph — a tappable scan button when [onTap] is set.
          _buildCore(size),
        ],
      ),
    );
  }

  Widget _buildCore(double size) {
    final core = AnimatedScale(
      scale: _pressed ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.fill.withAlpha(28),
          border: Border.all(color: widget.fill.withAlpha(90), width: 2),
          // Soft glow so the orb reads as a raised, tappable control.
          boxShadow: widget.onTap == null
              ? null
              : [
                  BoxShadow(
                    color: widget.fill.withAlpha(_pressed ? 40 : 70),
                    blurRadius: _pressed ? 14 : 26,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: Center(
          child: DuotoneIcon(
            widget.icon,
            size: size * 0.42,
            color: widget.ink,
          ),
        ),
      ),
    );

    if (widget.onTap == null) return core;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: core,
    );
  }

  /// One expanding ring: scales from the core size out to ~1.55× while its
  /// stroke fades to transparent. [phase] offsets the second ring half a cycle.
  Widget _pulseRing({required double phase}) {
    final double t = (_controller.value + phase) % 1.0;
    final double scale = 1.0 + 0.55 * t;
    final int alpha = ((1.0 - t) * 96).round();
    return Transform.scale(
      scale: scale,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: widget.fill.withAlpha(alpha), width: 1.5),
        ),
      ),
    );
  }
}

/// A small blinking status dot for the "Monitoring live" line. Render it ONLY
/// when at least one guard is verified active — its presence is the promise.
class LiveDot extends StatefulWidget {
  final double size;

  /// Defaults to the contrast-safe lime ink ([AppColors.accentInk]).
  final Color? color;

  const LiveDot({super.key, this.size = 7, this.color});

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.stop();
      _controller.value = 1.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.accentInk;
    return FadeTransition(
      opacity: _reduceMotion
          ? const AlwaysStoppedAnimation<double>(1.0)
          : Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
