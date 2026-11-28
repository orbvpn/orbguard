// Amazon Appstore build only. The part of the API that
// lib/services/telemetry/telemetry_service.dart calls, with the same
// signatures. Nothing is collected or sent.
library;

import 'package:flutter/foundation.dart';

class FirebaseCrashlytics {
  FirebaseCrashlytics._();

  static final FirebaseCrashlytics instance = FirebaseCrashlytics._();

  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {}

  Future<void> recordFlutterFatalError(
      FlutterErrorDetails flutterErrorDetails) async {}

  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    bool fatal = false,
  }) async {}
}
