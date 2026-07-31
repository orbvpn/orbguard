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

  // The sign-in email renders the token only as a BUTTON — it never shows a
  // readable code — so the in-app fallback has to accept the LINK the user can
  // actually copy. This is the path a Store reviewer falls back to when link
  // activation does not work on their machine.
  group('magicCodeFromPastedText', () {
    test('accepts a bare code', () {
      expect(magicCodeFromPastedText('ABC123'), 'ABC123');
    });

    test('accepts the full magic link the user copied from the email', () {
      expect(magicCodeFromPastedText('orbguard://login?code=ABC123'), 'ABC123');
    });

    test('tolerates whitespace and newlines around a pasted link', () {
      expect(
        magicCodeFromPastedText('  orbguard://login?code=ABC123\n'),
        'ABC123',
      );
    });

    test('pulls the code out of an https magic link too', () {
      expect(
        magicCodeFromPastedText('https://orbai.world/login?code=ABC123'),
        'ABC123',
      );
    });

    test('accepts the ACTUAL emailed url, which carries ?token= not ?code=', () {
      // OrbNet emails the https redirector and builds orbguard://login?code=T
      // from it with code == token, so the token in the emailed link is exactly
      // what /auth/magic-link/verify expects.
      expect(
        magicCodeFromPastedText(
            'https://api.orbai.world/api/v1/auth/magic-link/mobile?token=ABC123&client=orbguard'),
        'ABC123',
      );
    });

    test('prefers code over token when a url somehow carries both', () {
      expect(
        magicCodeFromPastedText('https://x.test/l?token=OLD&code=NEW'),
        'NEW',
      );
    });

    test('empty or whitespace-only input yields null', () {
      expect(magicCodeFromPastedText(''), isNull);
      expect(magicCodeFromPastedText('   '), isNull);
    });

    test('a link carrying no code yields null, never the raw URL', () {
      expect(magicCodeFromPastedText('https://orbvpn.com/'), isNull);
      expect(magicCodeFromPastedText('orbguard://login'), isNull);
    });
  });
}
