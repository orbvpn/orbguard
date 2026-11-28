// Amazon Appstore build only. The part of the API that the telemetry and
// push services call, with the same signatures. There is never a Firebase
// app: initializeApp throws a FirebaseException, which both services
// already treat as "carry on without it" (push falls back to polling).
library;

class FirebaseException implements Exception {
  FirebaseException(
      {required this.plugin, this.code = 'unknown', this.message});

  final String plugin;
  final String code;
  final String? message;

  @override
  String toString() => '[$plugin/$code] ${message ?? ''}';
}

class FirebaseApp {
  const FirebaseApp._();
}

class Firebase {
  Firebase._();

  static List<FirebaseApp> get apps => const <FirebaseApp>[];

  static Future<FirebaseApp> initializeApp({String? name}) async {
    throw FirebaseException(
      plugin: 'core',
      code: 'not-included',
      message: 'Firebase is not part of this build.',
    );
  }
}
