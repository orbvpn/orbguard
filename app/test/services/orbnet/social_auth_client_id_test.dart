import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/orbnet/social_auth_service.dart';

/// Google sign-in on Apple platforms needs the app's own OAuth client. The
/// Mac app shares the iPhone app's bundle id (com.orb.guard), so it shares
/// its client too. Without one the Mac's Google button always failed.
void main() {
  const String apple =
      '568666805173-gj5jahjs2tpj3bvvi0i9304343q4082p.apps.googleusercontent.com';

  test('iPhone and Mac use the com.orb.guard client', () {
    expect(SocialAuthService.defaultClientIdFor(TargetPlatform.iOS), apple);
    expect(SocialAuthService.defaultClientIdFor(TargetPlatform.macOS), apple);
  });

  test('Android resolves its client by package and SHA-1, so none is set', () {
    expect(SocialAuthService.defaultClientIdFor(TargetPlatform.android), '');
  });
}
