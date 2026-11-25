/// A glass card of rows, each a press target with an icon tile, a title, one
/// line under it and a chevron, and the label that heads a section of a page.
///
/// The kit's `.glass.rows` and `.sect-label`, as the Check and Protect tabs
/// draw them.
library;

import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'duotone_icon.dart';
import 'pressable.dart';

/// The small caps label over a section of a page.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.top = 26});

  final String text;

  /// Space above the label. The kit keeps 26 between sections.
  final double top;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Brand tokens flip with the theme
    return Padding(
      padding: EdgeInsets.fromLTRB(2, top, 2, 10),
      child: Semantics(
        header: true,
        child: Text(text.toUpperCase(), style: BrandText.label(size: 11.5)),
      ),
    );
  }
}

/// One glass card holding [rows], with a hairline between each.
class GlassRows extends StatelessWidget {
  const GlassRows({super.key, required this.rows});

  final List<GlassRow> rows;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return BrandGlass(
      radius: 24,
      elevated: false,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < rows.length; i++)
            _Divided(divided: i > 0, child: rows[i]),
        ],
      ),
    );
  }
}

class _Divided extends StatelessWidget {
  const _Divided({required this.divided, required this.child});

  final bool divided;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!divided) return child;
    return Stack(
      children: [
        child,
        // From the text's start edge to the card's padding: the tile keeps
        // a clear column.
        PositionedDirectional(
          start: GlassRow.textStart,
          end: 16,
          top: 0,
          child: Container(height: 1, color: Brand.hairline),
        ),
      ],
    );
  }
}

/// A row in a [GlassRows] card.
class GlassRow extends StatelessWidget {
  const GlassRow({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
    required this.onTap,
    this.iconColor,
  });

  /// An [AppIcons] name.
  final String icon;
  final String title;
  final String line;
  final VoidCallback? onTap;

  /// The icon's colour. Lime ink unless the row carries no state to show.
  final Color? iconColor;

  /// Where the title starts: the side padding, the tile and the gap.
  static const double textStart = 16 + 40 + 13;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title. $line',
      radius: BorderRadius.circular(Brand.rMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconTile(icon: icon, color: iconColor ?? Brand.limeInk),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: BrandText.title(size: 16)
                            .copyWith(height: Brand.displayHeight(1.3))),
                    const SizedBox(height: 1),
                    Text(line,
                        style: BrandText.body(size: 13.5)
                            .copyWith(height: Brand.bodyHeight(1.35))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DuotoneIcon(AppIcons.chevronRight, size: 17, color: Brand.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The kit's `.tile`: a 40 rounded square of hairline holding one icon.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    this.fill,
  });

  final String icon;
  final Color color;

  /// The tile's fill. Hairline unless the tile carries a tone.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: fill ?? Brand.hairline,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: DuotoneIcon(icon, size: 20, color: color)),
    );
  }
}
