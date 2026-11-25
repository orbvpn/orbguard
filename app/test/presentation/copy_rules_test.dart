// The copy rule the brand asks for: no em dash and no en dash in anything a
// person reads.
//
// This reads the source rather than pumping screens, because most sentences
// only appear in a state a widget test would have to stage one by one (a
// failed check, a premium account, a refused permission).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The dash rule covers everything the app is built from. The legal texts
/// are the one exception: they are kept word for word as the lawyers wrote
/// them.
const String _lib = 'lib';
const List<String> _exempt = ['lib/legal/'];

/// The sale surface is held to the rest of the rule too: no arrows and no
/// middle-dot joins.
const List<String> _saleSurface = [
  'lib/widgets/sale',
  'lib/widgets/scan_credits',
];

final RegExp _arrowOrDot = RegExp('[→←↑↓⇒⇐]| · ');

final RegExp _dash = RegExp('[—–]');

/// The part of a source line that is code, with a trailing `//` comment cut
/// off. A `//` right after a colon is a URL inside a string, not a comment.
String _code(String line) {
  for (int i = line.indexOf('//'); i >= 0; i = line.indexOf('//', i + 2)) {
    if (i == 0 || line[i - 1] != ':') return line.substring(0, i);
  }
  return line;
}

/// The Dart files a path stands for: every one under a folder. A path that
/// no longer exists throws, so a renamed screen cannot drop out unnoticed.
List<File> _files(String path) {
  if (FileSystemEntity.isDirectorySync(path)) {
    return Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();
  }
  return [File(path)];
}

void main() {
  test('nothing in the app is written with an em or en dash', () {
    final List<String> found = [];
    for (final File file in _files(_lib)) {
      final String path = file.path.replaceAll(r'\\', '/');
      if (_exempt.any(path.startsWith)) continue;
      final List<String> lines = file.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (_dash.hasMatch(_code(lines[i]))) {
          found.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    // A sweep that finds no files proves nothing.
    expect(_files(_lib).length, greaterThan(100));
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('nothing the sale surface shows uses an arrow or a middle-dot join', () {
    final List<String> found = [];
    for (final String path in _saleSurface) {
      for (final File file in _files(path)) {
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          if (_arrowOrDot.hasMatch(_code(lines[i]))) {
            found.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });
}
