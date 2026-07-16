// Host-side driver for `flutter drive` integration tests.
// Saves screenshots taken with binding.takeScreenshot() to build/screen_sweep/.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final dir = Directory('build/screen_sweep');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
