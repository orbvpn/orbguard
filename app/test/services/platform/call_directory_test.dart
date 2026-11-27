import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/platform/call_directory_platform_service.dart';
import 'package:orbguard/widgets/scam/iphone_scam_guards_card.dart';

const _channel = MethodChannel('com.orb.guard/call_directory');
final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

void main() {
  group('parseInternationalNumber', () {
    int? parse(String s) =>
        CallDirectoryPlatformService.parseInternationalNumber(s);

    test('takes + or 00 with the country code, in CallKit form', () {
      expect(parse('+1 (408) 555-0123'), 14085550123);
      expect(parse('0044 20 7946 0000'), 442079460000);
      expect(parse(' +49.30.1234567 '), 49301234567);
    });

    test('refuses a number without a country code', () {
      expect(parse('408 555 0123'), isNull);
      expect(parse('0912 345 6789'), isNull);
    });

    test('refuses junk, too short and too long', () {
      expect(parse('+1 555 CALL NOW'), isNull);
      expect(parse('+12345'), isNull);
      expect(parse('+1234567890123456'), isNull);
      expect(parse('+0 408 555 0123'), isNull);
    });
  });

  group('IphoneScamGuardsCard', () {
    late List<int> stored;
    late bool enabled;
    final calls = <MethodCall>[];

    setUp(() {
      stored = [];
      enabled = false;
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'status':
            return {'containerAvailable': true, 'extensionEnabled': enabled};
          case 'list':
            return {'blocked': stored};
          case 'block':
            stored =
                ({...stored, (call.arguments as Map)['number'] as int}.toList()
                  ..sort());
            return {'blocked': stored, 'reloadRequested': true};
          case 'unblock':
            stored = stored
                .where((n) => n != (call.arguments as Map)['number'])
                .toList();
            return {'blocked': stored, 'reloadRequested': true};
          case 'openSettings':
            return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: IphoneScamGuardsCard())),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('off: says where to turn it on and offers Settings',
        (tester) async {
      await pump(tester);
      expect(find.textContaining('Off. Open Settings, tap Apps, then Phone'),
          findsOneWidget);
      expect(find.textContaining('Manage Filtering'), findsOneWidget);
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), contains('openSettings'));
    }, variant: _ios);

    testWidgets('on: blocks and unblocks a number', (tester) async {
      enabled = true;
      await pump(tester);
      expect(find.text('Open Settings'), findsNothing);
      expect(find.text('On. Add a number below to block it.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '+1 408 555 0123');
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(stored, [14085550123]);
      expect(find.text('+14085550123'), findsOneWidget);
      expect(find.text('On. Your iPhone stops calls from the numbers below.'),
          findsOneWidget);

      await tester.tap(find.text('Unblock'));
      await tester.pumpAndSettle();
      expect(stored, isEmpty);
      expect(find.text('+14085550123'), findsNothing);
    }, variant: _ios);

    testWidgets('a local number is refused, not saved', (tester) async {
      enabled = true;
      await pump(tester);
      await tester.enterText(find.byType(TextField), '408 555 0123');
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(
          find.text('Add the country code, starting with +.'), findsOneWidget);
      expect(calls.map((c) => c.method), isNot(contains('block')));
    }, variant: _ios);

    testWidgets('no App Group: says so and hides the list', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'status') return {'containerAvailable': false};
        return {'blocked': <int>[]};
      });
      await pump(tester);
      expect(find.text("This build can't keep a block list."), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    }, variant: _ios);
  });
}
