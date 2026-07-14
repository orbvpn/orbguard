import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:orbguard/services/vpn/orbvpn_handoff_controller.dart';
import 'package:orbguard/services/vpn/vpn_controller.dart';

void main() {
  group('OrbVpnHandoffController', () {
    test('launches the OrbVPN deep link when it can be handled', () async {
      Uri? launched;
      final controller = OrbVpnHandoffController(
        canLaunch: (uri) async => uri.scheme == 'orbvpn',
        launcher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          launched = uri;
          return true;
        },
      );

      await controller.connect();

      expect(launched, isNotNull);
      expect(launched!.scheme, 'orbvpn');
      controller.dispose();
    });

    test('falls back to a store URL when the deep link is unavailable',
        () async {
      final launched = <Uri>[];
      final controller = OrbVpnHandoffController(
        canLaunch: (uri) async => false, // deep link not installed
        launcher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          launched.add(uri);
          return true;
        },
      );

      await controller.connect();

      expect(launched, hasLength(1));
      expect(launched.single.scheme, anyOf('https', 'market'));
      controller.dispose();
    });

    test('reports error status when the launcher throws', () async {
      final controller = OrbVpnHandoffController(
        canLaunch: (uri) async => true,
        launcher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          throw Exception('no launcher');
        },
      );

      await controller.connect();

      expect(controller.status, VpnStatus.error);
      controller.dispose();
    });
  });
}
