// Amazon Appstore build only. The part of the API that main.dart and
// lib/services/device_agent/push_service.dart call, with the same
// signatures. No message, token or permission ever comes from here; push
// init already stops earlier, when Firebase itself fails to start.
library;

typedef BackgroundMessageHandler = Future<void> Function(RemoteMessage message);

class RemoteMessage {
  const RemoteMessage({this.data = const <String, dynamic>{}});

  final Map<String, dynamic> data;
}

class FirebaseMessaging {
  FirebaseMessaging._();

  static final FirebaseMessaging instance = FirebaseMessaging._();

  static void onBackgroundMessage(BackgroundMessageHandler handler) {}

  static Stream<RemoteMessage> get onMessage =>
      const Stream<RemoteMessage>.empty();

  static Stream<RemoteMessage> get onMessageOpenedApp =>
      const Stream<RemoteMessage>.empty();

  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  Future<void> requestPermission({
    bool alert = true,
    bool badge = true,
    bool sound = true,
  }) async {}

  Future<String?> getAPNSToken() async => null;

  Future<String?> getToken() async => null;
}
