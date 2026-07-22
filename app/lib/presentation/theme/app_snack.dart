import 'package:flutter/material.dart';

import 'brand.dart';

/// Shows a SnackBar whose text color contrasts with [background].
///
/// The default SnackBar text is white, which is invisible on a light fill such
/// as Volt Lime (`AppColors.success`) — the reported "white on lime" bug. This
/// picks dark ink for light backgrounds (per the brand rule: lime is fill-only,
/// always dark `Brand.onLime` text on it) and white for dark/saturated fills.
void showResultSnackBar(
  BuildContext context,
  String message, {
  required Color background,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  final Color onColor =
      ThemeData.estimateBrightnessForColor(background) == Brightness.light
          ? Brand.onLime
          : Colors.white;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: TextStyle(color: onColor)),
      backgroundColor: background,
      action: action,
      duration: duration,
    ),
  );
}
