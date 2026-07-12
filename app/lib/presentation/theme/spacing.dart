/// Unified Spacing System - iOS 26 Glass UI
///
/// Standard spacing values used across all screens for consistent layout.
/// All vertical gaps between widgets should use these values.
library;

import 'package:flutter/material.dart';

/// App-wide spacing constants
abstract class AppSpacing {
  // Horizontal padding
  static const double screenHorizontal = 20.0;

  // Vertical spacing between elements
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;

  // Standard gap between cards/widgets on screens
  static const double cardGap = 16.0;

  // Bottom navigation safe area
  static const double bottomNavHeight = 120.0;

  // Header heights and offsets
  static const double headerTopOffset = 12.0; // Gap from safe area to floating header
  static const double connectionHeaderHeight = 122.0; // Header height + buffer

  /// Calculate scroll content top padding based on header
  /// This ensures consistent 16px gap below any floating header
  static double scrollTopPadding(double topSafeArea) {
    return topSafeArea + headerTopOffset + connectionHeaderHeight + cardGap;
  }
}

/// Standard vertical spacing widget - use between cards and sections
class VerticalGap extends StatelessWidget {
  final double size;

  const VerticalGap(this.size, {super.key});

  /// Extra small gap (4px)
  const VerticalGap.xs({super.key}) : size = AppSpacing.xs;

  /// Small gap (8px)
  const VerticalGap.sm({super.key}) : size = AppSpacing.sm;

  /// Medium gap (12px)
  const VerticalGap.md({super.key}) : size = AppSpacing.md;

  /// Large gap (16px) - Standard gap between cards
  const VerticalGap.lg({super.key}) : size = AppSpacing.lg;

  /// Extra large gap (20px)
  const VerticalGap.xl({super.key}) : size = AppSpacing.xl;

  /// Double extra large gap (24px)
  const VerticalGap.xxl({super.key}) : size = AppSpacing.xxl;

  /// Triple extra large gap (32px)
  const VerticalGap.xxxl({super.key}) : size = AppSpacing.xxxl;

  /// Standard card gap (16px) - Use between all cards on screens
  const VerticalGap.card({super.key}) : size = AppSpacing.cardGap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: size);
  }
}

/// Standard horizontal spacing widget
class HorizontalGap extends StatelessWidget {
  final double size;

  const HorizontalGap(this.size, {super.key});

  /// Extra small gap (4px)
  const HorizontalGap.xs({super.key}) : size = AppSpacing.xs;

  /// Small gap (8px)
  const HorizontalGap.sm({super.key}) : size = AppSpacing.sm;

  /// Medium gap (12px)
  const HorizontalGap.md({super.key}) : size = AppSpacing.md;

  /// Large gap (16px)
  const HorizontalGap.lg({super.key}) : size = AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size);
  }
}

/// Screen padding helper - provides consistent horizontal padding
class ScreenPadding extends StatelessWidget {
  final Widget child;
  final double? top;
  final double? bottom;

  const ScreenPadding({
    super.key,
    required this.child,
    this.top,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: top ?? 0,
        bottom: bottom ?? 0,
      ),
      child: child,
    );
  }
}
