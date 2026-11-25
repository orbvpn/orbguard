/// The card for one thing found: what it is, the one action that closes the
/// gap, and what closing it earns. It owns Home's lime action while it shows.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../services/home/home_brief.dart';
import '../shields/shield_look.dart';

class CareCard extends StatelessWidget {
  const CareCard({super.key, required this.gap, required this.onClose});

  final HomeGap gap;

  /// Starts the fix. Null draws the button disabled.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // repaint with the theme
    return BrandGlass(
      radius: 24,
      elevated: false,
      tint: Brand.amberPill,
      borderColor: Brand.amberLine,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Brand.amberPill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: DuotoneIcon(gap.shield.icon,
                      size: 20, color: Brand.amberInk),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gap.title,
                        style: BrandText.title(size: 16)
                            .copyWith(height: Brand.displayHeight(1.3))),
                    const SizedBox(height: 3),
                    Text(gap.detail,
                        style: BrandText.body(size: 13.5)
                            .copyWith(height: Brand.bodyHeight(1.45))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          BrandButton(
            label: 'Close the gap',
            onPressed: onClose,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          ),
          const SizedBox(height: 12),
          Text(gap.gain,
              textAlign: TextAlign.center,
              style: BrandText.body(size: 13.5, color: Brand.amberInk)
                  .copyWith(height: Brand.bodyHeight(1.45))),
        ],
      ),
    );
  }
}
