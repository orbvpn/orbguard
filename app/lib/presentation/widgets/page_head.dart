/// The head of a tab that is not Home: the tab's name and one line under it.
///
/// Protect, Check and Me each open with one. It scrolls away with the page;
/// nothing floats over the content.
library;

import 'package:flutter/material.dart';

import '../theme/brand.dart';

class PageHead extends StatelessWidget {
  const PageHead({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;

  /// One short line that says what the tab is for.
  final String? subtitle;

  /// A control at the far side, such as a round button.
  final Widget? trailing;

  /// Never shorter than a press target, so a head with no line under it
  /// still lines up with one that has a button.
  static const double minHeight = 44;

  /// Space the head keeps under itself before the page's first card.
  static const double gapBelow = 18;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Brand tokens flip with the theme
    final String? subtitle = this.subtitle;
    final Widget? trailing = this.trailing;

    return Padding(
      padding: const EdgeInsets.only(bottom: gapBelow),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: BrandText.h2(size: 23)),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        subtitle,
                        style: BrandText.body(size: 13.5, color: Brand.text2)
                            .copyWith(height: Brand.bodyHeight(1.45)),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing],
          ],
        ),
      ),
    );
  }
}
