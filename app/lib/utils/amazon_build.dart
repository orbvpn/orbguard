/// The Amazon Appstore build, and how code asks whether it is one.
///
/// The Amazon build sells nothing. It has no plans, prices, ads or credits
/// to earn, names no store or site to pay at, and creates no accounts. The
/// first check is free; after that a check needs OrbGuard Premium, and an
/// account that already has Premium signs in and keeps it.
///
/// Only app/amazon/build_amazon_apk.sh passes
/// `--dart-define=ORB_AMAZON_BUILD=true`. Every other build reads false
/// and behaves exactly as it did before this flag existed.
library;

import 'package:flutter/widgets.dart';

/// True only in the Amazon Appstore build.
///
/// Code that must not be in the Amazon binary at all, such as the ad
/// networks and the plans and credits sheets, tests this constant, so the
/// compiler leaves the other branch out.
const bool kAmazonBuild = bool.fromEnvironment('ORB_AMAZON_BUILD');

/// Draws everything below it as the Amazon build. Tests put one above the
/// app, so they need no dart-define.
class AmazonBuildScope extends InheritedWidget {
  const AmazonBuildScope({super.key, this.amazon = true, required super.child});

  final bool amazon;

  @override
  bool updateShouldNotify(AmazonBuildScope oldWidget) =>
      amazon != oldWidget.amazon;
}

/// Whether [context] is drawn as the Amazon build: always in that build,
/// and anywhere else only below an [AmazonBuildScope].
bool isAmazonBuild(BuildContext context) =>
    kAmazonBuild ||
    (context.getInheritedWidgetOfExactType<AmazonBuildScope>()?.amazon ??
        false);
