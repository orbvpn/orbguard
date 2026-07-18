// Tests for ScanCreditApi against a fake Dio adapter — proving the REAL wire
// mapping (not a provider-level fake): the balance endpoint parses, and a
// backend HTTP 402 on /scan/consume surfaces as the typed
// InsufficientScanCreditsException ("out of credits, watch an ad").

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/orbnet/orbnet_api_client.dart';
import 'package:orbguard/services/orbnet/scan_credit_api.dart';

/// Returns a scan-credit balance, and a 402 for any consume attempt.
class _FakeScanCreditAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    Map<String, dynamic> body;
    int status;

    if (path.endsWith('/scan-credits/balance')) {
      body = {'scan_credits': 4};
      status = 200;
    } else if (path.endsWith('/scan/consume')) {
      // Balance can't cover the spend — the "go watch an ad" signal.
      body = {'detail': 'insufficient scan credits'};
      status = 402;
    } else {
      body = {'message': 'unexpected path: $path'};
      status = 404;
    }

    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    OrbNetApiClient.instance.debugReset();
    await OrbNetApiClient.instance.initialize();
    OrbNetApiClient.instance.httpClientAdapter = _FakeScanCreditAdapter();
  });

  test('getBalance parses scan_credits', () async {
    final api = ScanCreditApi();
    expect(await api.getBalance(), 4);
  });

  test('consume maps HTTP 402 → InsufficientScanCreditsException', () async {
    final api = ScanCreditApi();
    await expectLater(
      api.consume(),
      throwsA(isA<InsufficientScanCreditsException>()),
    );
  });
}
