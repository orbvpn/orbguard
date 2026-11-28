import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/api/api_config.dart';

void main() {
  test('an archive upload has minutes, as the server gives it', () {
    // The server answers an archive upload within 220 s plus 4 s, and its
    // host ends every request at 240 s.
    expect(ApiConfig.forensicUploadTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 224)));
    expect(ApiConfig.forensicUploadTimeout,
        greaterThan(Duration(milliseconds: ApiConfig.sendTimeout)));
  });
}
