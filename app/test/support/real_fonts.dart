// The bundled fonts, loaded into a test.
//
// Widget tests draw every glyph with Ahem, a square as wide as the font size,
// so text wraps far sooner than it does on a device. A test that measures how
// much a screen really holds, or that renders frames to look at, loads the
// real fonts first.

import 'dart:io';

import 'package:flutter/services.dart';

/// Call once, from `setUpAll`. Paths are relative to `app/`, where
/// `flutter test` runs.
Future<void> loadRealFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Archivo', ['Archivo-Variable.ttf']);
  await family('IBM Plex Sans', ['IBMPlexSans-Variable.ttf']);
  await family(
      'IBM Plex Mono', ['IBMPlexMono-Regular.ttf', 'IBMPlexMono-Medium.ttf']);
}
