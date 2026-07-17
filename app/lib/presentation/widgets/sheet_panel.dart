import 'package:flutter/material.dart';

import 'glass_widgets.dart';

/// Branded content for a confirm / info [showAppSheet]: an optional icon +
/// title, a (scrollable) body, and up to two actions. Each button dismisses
/// the sheet first, then runs its callback — so a pop-up that used to be a
/// centered [AlertDialog] becomes a bottom sheet with the same behaviour.
class SheetPanel extends StatelessWidget {
  final String title;
  final Widget? titleIcon;
  final Widget body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// When true the primary action is a destructive (red) button — for
  /// Remove/Delete/Reset confirms.
  final bool danger;

  const SheetPanel({
    super.key,
    required this.title,
    required this.body,
    required this.primaryLabel,
    this.titleIcon,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (titleIcon != null) ...[titleIcon!, const SizedBox(width: 10)],
              Expanded(
                child: Text(title,
                    style: BrandText.h2(color: cs.onSurface, size: 21)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Flexible(child: SingleChildScrollView(child: body)),
          const SizedBox(height: 22),
          Row(
            children: [
              if (secondaryLabel != null) ...[
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onSecondary?.call();
                    },
                    child: Text(secondaryLabel!),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: danger
                    ? ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onPrimary?.call();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Brand.danger,
                          foregroundColor: Brand.onDanger,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(primaryLabel),
                      )
                    : BrandButton(
                        label: primaryLabel,
                        onPressed: () {
                          Navigator.of(context).pop();
                          onPrimary?.call();
                        },
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
