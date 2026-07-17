/// On-device trust badge — a small reusable glass pill that reminds the user,
/// wherever it appears, that OrbGuard runs locally and stays private.
///
/// Purely informational (no tap target): safe to drop into any screen's
/// header, hero, or card without competing with that screen's one primary
/// (lime) action. See `screens/trust/privacy_explainer_screen.dart` for the
/// full explanation this badge is a shorthand for.
library;

import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../theme/colors.dart';
import 'duotone_icon.dart';

/// A small glass pill: keyhole-shield icon + "On-device · Private" label.
class OnDeviceTrustBadge extends StatelessWidget {
  /// Override only if a screen needs slightly different wording; defaults to
  /// the app-wide trust phrase so the promise reads identically everywhere.
  final String label;

  const OnDeviceTrustBadge({super.key, this.label = 'On-device · Private'});

  @override
  Widget build(BuildContext context) {
    // Lime-family ink — the kit's "protected / good" signal — for a purely
    // informational chip (not a CTA, so it never competes with the screen's
    // one primary lime action).
    final Color ink = AppColors.accentInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: Brand.glassSm(radius: Brand.rPill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon('shield_keyhole', size: 15, color: ink),
          const SizedBox(width: 6),
          Text(label, style: BrandText.label(color: ink, size: 11.5)),
        ],
      ),
    );
  }
}
