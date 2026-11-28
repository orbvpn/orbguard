// Amazon Appstore build only. The part of the API that
// lib/services/telemetry/telemetry_service.dart calls, with the same
// signatures. Nothing is collected or sent.
library;

import 'package:flutter/widgets.dart';

class FirebaseAnalytics {
  FirebaseAnalytics._();

  static final FirebaseAnalytics instance = FirebaseAnalytics._();

  Future<void> setAnalyticsCollectionEnabled(bool enabled) async {}
}

/// Watches nothing: it is only a navigator observer the app can hold.
class FirebaseAnalyticsObserver extends NavigatorObserver {
  FirebaseAnalyticsObserver({required this.analytics});

  final FirebaseAnalytics analytics;
}
