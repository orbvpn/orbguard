// Every icon the app names has a file behind it. A name with no SVG throws
// "Unable to load asset" the moment its screen draws, as `globe` did on the
// Mac's Desktop Security page.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

bool _drawn(String name) => File('assets/icons/$name.svg').existsSync();

void main() {
  test('every AppIcons name has its SVG', () {
    final String source =
        File('lib/presentation/widgets/duotone_icon.dart').readAsStringSync();
    final List<String> missing = [
      for (final RegExpMatch m
          in RegExp(r"static const String (\w+) = '([^']+)';")
              .allMatches(source))
        if (!_drawn(m.group(2)!)) '${m.group(1)} = ${m.group(2)}',
    ];
    expect(missing, isEmpty);
  });

  test('every icon a screen names by hand has its SVG', () {
    // The ways a screen hands an icon name over as a bare string.
    final RegExp named = RegExp(
        r"""(?:DuotoneIcon\(\s*|iconPath:\s*|icon:\s*|iconName:\s*|_buildBenefitItem\(\s*)'([a-z0-9_]+)'""");
    final RegExp threatCard =
        RegExp(r"_buildThreatTypeCard\([^,]+,[^,]+,[^,]+,\s*'([a-z0-9_]+)'");
    final List<String> missing = [];
    for (final FileSystemEntity f
        in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final String source = f.readAsStringSync();
      for (final RegExp pattern in [named, threatCard]) {
        for (final RegExpMatch m in pattern.allMatches(source)) {
          if (!_drawn(m.group(1)!)) missing.add('${f.path}: ${m.group(1)}');
        }
      }
    }
    expect(missing, isEmpty);
  });
}
