/// Text whose lines come out near the same length, like CSS
/// `text-wrap: balance`. A two-line headline stops ending in one orphan word.
///
/// It lays the text out at the width it is given, then narrows the box to the
/// smallest width that still takes the same number of lines.
library;

import 'package:flutter/widgets.dart';

class BalancedText extends StatelessWidget {
  const BalancedText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.center,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final TextStyle effective = DefaultTextStyle.of(context).style.merge(style);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double available = constraints.maxWidth;
        double? width;

        if (available.isFinite) {
          final TextPainter painter = TextPainter(
            text: TextSpan(text: text, style: effective),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: maxLines,
          )..layout(maxWidth: available);
          final int lines = painter.computeLineMetrics().length;

          if (lines > 1) {
            double low = 0, high = available;
            while (high - low > 1) {
              final double mid = (low + high) / 2;
              painter.layout(maxWidth: mid);
              final bool fits = !painter.didExceedMaxLines &&
                  painter.computeLineMetrics().length <= lines;
              if (fits) {
                high = mid;
              } else {
                low = mid;
              }
            }
            width = high.ceilToDouble();
          }
          painter.dispose();
        }

        return SizedBox(
          width: width,
          child: Text(
            text,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
