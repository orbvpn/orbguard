/// The checks of a check that is running, one row each, as Home shows them
/// under the ring on a phone and the side pane shows them on a wide screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../services/home/check_plan.dart';
import '../../services/home/check_run.dart';

/// The checks of the check that is running, one row each.
///
/// The list is as tall as the screen allows and no taller. When it cannot
/// show every check at once it follows the one running now, so nobody has to
/// scroll to see where the check is.
class CheckList extends StatefulWidget {
  const CheckList({
    super.key,
    required this.steps,
    required this.states,
    required this.focus,
    required this.rows,
  });

  static const double rowHeight = 38;

  final List<CheckStep> steps;
  final List<CheckStepState> states;

  /// Index of the step to keep in view.
  final int focus;

  /// How many rows show at once.
  final int rows;

  @override
  State<CheckList> createState() => _CheckListState();
}

class _CheckListState extends State<CheckList> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the running step one row above the foot of the list.
  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final double height = widget.rows * CheckList.rowHeight;
      final double want = ((widget.focus + 2) * CheckList.rowHeight - height)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      if ((want - _scroll.offset).abs() < 0.5) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(want);
      } else {
        _scroll.animateTo(want,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _follow();
    final bool all = widget.rows >= widget.steps.length;
    final Widget list = SingleChildScrollView(
      controller: _scroll,
      // The list moves itself. A drag here would only fight it.
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          for (int i = 0; i < widget.steps.length; i++)
            _CheckRow(step: widget.steps[i], state: widget.states[i]),
        ],
      ),
    );

    return SizedBox(
      key: const ValueKey('check-list'),
      height: widget.rows * CheckList.rowHeight,
      child: all
          ? list
          : ListenableBuilder(
              listenable: _scroll,
              builder: (context, child) {
                // Rows fade out at an edge that has more behind it.
                final bool has =
                    _scroll.hasClients && _scroll.position.hasContentDimensions;
                final bool above = has && _scroll.offset > 0.5;
                final bool below = !has ||
                    _scroll.offset < _scroll.position.maxScrollExtent - 0.5;
                return ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.16, 0.84, 1],
                    colors: [
                      above ? Colors.transparent : Brand.bg,
                      Brand.bg,
                      Brand.bg,
                      below ? Colors.transparent : Brand.bg,
                    ],
                  ).createShader(bounds),
                  child: child,
                );
              },
              child: list,
            ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.step, required this.state});

  final CheckStep step;
  final CheckStepState state;

  @override
  Widget build(BuildContext context) {
    final bool waiting = state == CheckStepState.pending;
    final bool failed = state == CheckStepState.unavailable;
    return Semantics(
      label: '${step.name}, ${switch (state) {
        CheckStepState.pending => 'waiting',
        CheckStepState.running => 'checking now',
        CheckStepState.done => 'done',
        CheckStepState.unavailable => 'could not run',
      }}',
      excludeSemantics: true,
      child: SizedBox(
        height: CheckList.rowHeight,
        child: Row(
          children: [
            _CheckMark(state: state),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                step.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrandText.body(
                  size: 14.5,
                  color: waiting ? Brand.text2 : Brand.text,
                ).copyWith(height: 1.2),
              ),
            ),
            if (failed)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 10),
                child: Text(
                  'Could not run',
                  maxLines: 1,
                  style: BrandText.body(size: 12.5, color: Brand.amberInk)
                      .copyWith(height: 1.2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The 18 mark at the head of a row: an empty circle while the step waits, a
/// turning lime arc while it runs, a lime disc with a tick once it is done,
/// and an amber circle when it could not run.
class _CheckMark extends StatefulWidget {
  const _CheckMark({required this.state});

  final CheckStepState state;

  @override
  State<_CheckMark> createState() => _CheckMarkState();
}

class _CheckMarkState extends State<_CheckMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_CheckMark old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// The arc turns only while this step runs, and not at all for someone who
  /// asked for less motion.
  void _sync() {
    final bool turn = widget.state == CheckStepState.running &&
        !MediaQuery.disableAnimationsOf(context);
    if (turn && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!turn && _turn.isAnimating) {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget mark = switch (widget.state) {
      CheckStepState.pending => _circle(Brand.border),
      CheckStepState.unavailable => _circle(Brand.amberInk),
      CheckStepState.running => RotationTransition(
          turns: _turn,
          child: CustomPaint(painter: _ArcPainter(Brand.limeInk)),
        ),
      CheckStepState.done => DecoratedBox(
          decoration:
              const BoxDecoration(shape: BoxShape.circle, color: Brand.lime),
          child: CustomPaint(painter: _TickPainter(Brand.onLime)),
        ),
    };
    return SizedBox.square(dimension: 18, child: mark);
  }

  static Widget _circle(Color color) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
      );
}

/// Three quarters of a circle, so its turning shows.
class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      (Offset.zero & size).deflate(0.75),
      0,
      math.pi * 1.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}

class _TickPainter extends CustomPainter {
  const _TickPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.29, h * 0.52)
        ..lineTo(w * 0.44, h * 0.67)
        ..lineTo(w * 0.72, h * 0.36),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}
