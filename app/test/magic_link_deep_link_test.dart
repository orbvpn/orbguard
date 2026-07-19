import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/orbnet/magic_link_deep_link.dart';

void main() {
  group('magicCodeFromUri', () {
    test('extracts code from orbguard://login?code=…', () {
      expect(magicCodeFromUri(Uri.parse('orbguard://login?code=ABC123')), 'ABC123');
    });

    test('trims surrounding whitespace', () {
      expect(magicCodeFromUri(Uri.parse('orbguard://login?code=%20ABC%20')), 'ABC');
    });

    test('ignores the OrbVPN scheme (not ours)', () {
      expect(magicCodeFromUri(Uri.parse('orbvpn://login?code=ABC123')), isNull);
    });

    test('ignores a different host/path', () {
      expect(magicCodeFromUri(Uri.parse('orbguard://settings?code=ABC')), isNull);
    });

    test('null when code missing or empty', () {
      expect(magicCodeFromUri(Uri.parse('orbguard://login')), isNull);
      expect(magicCodeFromUri(Uri.parse('orbguard://login?code=')), isNull);
    });
  });
}
