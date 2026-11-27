// The shell keeps the home-screen widgets, the lock screen and the menu bar
// saying what Home says, and answers the menu bar's "Check now".
//
// The rules these tests hold:
//  - once Home has a reading, the native side is told it, in Home's words
//  - when the reading changes, it is told again; when nothing changed, not
//  - asked for the glance as it is now, the shell answers with it
//  - "Check now" from outside the app runs the check on Home

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/shell_harness.dart';

const MethodChannel _glance = MethodChannel('com.orb.guard/glance');

/// What the shell sent the native side, oldest first.
List<Map<Object?, Object?>> _listen(WidgetTester tester) {
  final List<Map<Object?, Object?>> sent = [];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_glance, (call) async {
    if (call.method == 'update') {
      sent.add(call.arguments as Map<Object?, Object?>);
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_glance, null));
  return sent;
}

/// The native side calls [method] on the shell, and gets its answer.
Future<Object?> _ask(WidgetTester tester, String method) async {
  const MethodCodec codec = StandardMethodCodec();
  Object? answer;
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _glance.name,
    codec.encodeMethodCall(MethodCall(method)),
    (ByteData? reply) {
      if (reply != null) answer = codec.decodeEnvelope(reply);
    },
  );
  return answer;
}

void main() {
  testWidgets('the native side is told what Home says', (tester) async {
    final List<Map<Object?, Object?>> sent = _listen(tester);
    await mountShell(tester, checked: true, autoCheckSpent: true);

    expect(sent, isNotEmpty);
    final Map<Object?, Object?> last = sent.last;
    expect(last['moment'], 'clear');
    expect(last['score'], isA<int>());
    expect(last['checkedAt'], isA<int>());
    expect(last['headline'], isA<String>());

    await unmountShell(tester);
  });

  testWidgets('told again when the reading changes, and only then',
      (tester) async {
    final List<Map<Object?, Object?>> sent = _listen(tester);
    final ShellUnderTest shell = await mountShell(tester, autoCheckSpent: true);
    expect(sent.last['moment'], 'fresh');
    final int before = sent.length;

    // Nothing changed: nothing is sent.
    await tester.pump(const Duration(seconds: 1));
    expect(sent.length, before);

    await shell.verdict.recordScan(
        threats: const [], coveragePercent: 90, now: DateTime.now());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent.length, greaterThan(before));
    expect(sent.last['moment'], 'clear');

    await unmountShell(tester);
  });

  testWidgets('asked for the glance as it is now, the shell answers',
      (tester) async {
    _listen(tester);
    await mountShell(tester, checked: true, autoCheckSpent: true);

    final Object? answer = await _ask(tester, 'refresh');
    expect(answer, isA<Map<Object?, Object?>>());
    expect((answer! as Map<Object?, Object?>)['moment'], 'clear');

    await unmountShell(tester);
  });

  testWidgets('Check now from outside the app runs the check on Home',
      (tester) async {
    _listen(tester);
    // Never checked, so the first check is free and starts at once.
    await mountShell(tester, autoCheckSpent: true);

    await _ask(tester, 'checkNow');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Checking your'), findsOneWidget);

    await finishCheck(tester);
    await unmountShell(tester);
  });
}
