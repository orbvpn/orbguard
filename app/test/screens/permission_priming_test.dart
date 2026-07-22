// test/screens/permission_priming_test.dart
//
// First-run permission priming (P4.3): the screen must show every platform-
// appropriate step with its value copy, fire ONLY the injected request
// functions, render the honest post-request state (lime "On" only when the
// request really granted), reveal the single lime CTA once every one-tap
// step is decided, and persist `permissions_primed` before onDone — for
// both the finish and the opt-out paths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/screens/onboarding/permission_priming_screen.dart';

/// Injected fakes — no platform channels, every call logged.
PrimingRequests fakeRequests({
  bool notifications = true,
  bool sms = true,
  bool location = true,
  List<String>? log,
}) {
  return PrimingRequests(
    requestNotifications: () async {
      log?.add('notifications');
      return notifications;
    },
    requestSms: () async {
      log?.add('sms');
      return sms;
    },
    requestLocation: () async {
      log?.add('location');
      return location;
    },
    openUsageAccess: () async {
      log?.add('usage_access');
    },
    openAccessibility: () async {
      log?.add('accessibility');
    },
  );
}

/// Finder scoped to one step card (cards are keyed `priming_step_<id>`).
Finder inStep(String stepId, Finder matching) => find.descendant(
      of: find.byKey(ValueKey('priming_step_$stepId')),
      matching: matching,
    );

const String kSkippedCopy = 'Skipped — you can enable later in Settings';

Future<void> pumpPriming(
  WidgetTester tester, {
  required TargetPlatform platform,
  PrimingRequests? requests,
  VoidCallback? onDone,
}) async {
  // The Android checklist (header + 6 cards + footer) runs far taller than
  // the default 800×600 surface, and ListView only builds children near the
  // viewport — a tall virtual viewport builds every card without scrolling.
  tester.view.physicalSize = const Size(900, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: PermissionPrimingScreen(
        onDone: onDone ?? () {},
        platformOverride: platform,
        requests: requests ?? fakeRequests(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Android priming flow', () {
    testWidgets('renders all step groups with their value copy',
        (tester) async {
      await pumpPriming(tester, platform: TargetPlatform.android);

      // 1. Notifications
      expect(find.text('Notifications'), findsOneWidget);
      expect(
          find.text('Get alerted the moment we spot a threat.'), findsOneWidget);
      // (No Storage step: file scanning is SAF-picker based — nothing to ask.)
      expect(find.text('Storage'), findsNothing);
      // 2. SMS
      expect(find.text('SMS'), findsOneWidget);
      expect(find.text('Catch scam texts before you tap them.'), findsOneWidget);
      // 4. Location
      expect(find.text('Location'), findsOneWidget);
      expect(
          find.text(
              'Spot apps secretly tracking where you go, and test Wi-Fi safety.'),
          findsOneWidget);
      // 5. Advanced (visually separated, labeled as Settings deep-links)
      expect(find.text('Usage access'), findsOneWidget);
      expect(find.text('See which apps watch you in the background.'),
          findsOneWidget);
      expect(find.text('Accessibility'), findsOneWidget);
      expect(find.text('Detect stalkerware screen-readers.'), findsOneWidget);
      expect(find.text('Opens system Settings'), findsNWidgets(2));
      expect(find.textContaining('ADVANCED'), findsOneWidget);

      // Skippable from the start; CTA only appears once steps are decided.
      expect(find.text('Skip for now'), findsOneWidget);
      expect(find.text('Run my first check'), findsNothing);
    });

    testWidgets('Allow flips the chip to On when the request grants',
        (tester) async {
      final log = <String>[];
      await pumpPriming(tester,
          platform: TargetPlatform.android,
          requests: fakeRequests(notifications: true, log: log));

      await tester.tap(inStep('notifications', find.text('Allow')));
      await tester.pumpAndSettle();

      expect(log, contains('notifications'));
      expect(inStep('notifications', find.text('On')), findsOneWidget);
      expect(inStep('notifications', find.text('Allow')), findsNothing);
      expect(inStep('notifications', find.text(kSkippedCopy)), findsNothing);
    });

    testWidgets('Allow shows the honest Skipped state when the OS denies',
        (tester) async {
      await pumpPriming(tester,
          platform: TargetPlatform.android, requests: fakeRequests(sms: false));

      await tester.tap(inStep('sms', find.text('Allow')));
      await tester.pumpAndSettle();

      // Never claims On when the permission is not actually granted.
      expect(inStep('sms', find.text('On')), findsNothing);
      expect(inStep('sms', find.text(kSkippedCopy)), findsOneWidget);
    });

    testWidgets('per-step Skip resolves the step without firing any request',
        (tester) async {
      final log = <String>[];
      await pumpPriming(tester,
          platform: TargetPlatform.android, requests: fakeRequests(log: log));

      await tester.tap(inStep('sms', find.text('Skip')));
      await tester.pumpAndSettle();

      expect(inStep('sms', find.text(kSkippedCopy)), findsOneWidget);
      expect(log, isEmpty);
    });

    testWidgets('advanced steps deep-link to Settings and never claim On',
        (tester) async {
      final log = <String>[];
      await pumpPriming(tester,
          platform: TargetPlatform.android, requests: fakeRequests(log: log));

      await tester.tap(inStep('usage_access', find.text('Turn on')));
      await tester.pumpAndSettle();

      expect(log, ['usage_access']);
      expect(
          inStep('usage_access',
              find.text('Opened system Settings — finish turning it on there.')),
          findsOneWidget);
      expect(inStep('usage_access', find.text('On')), findsNothing);
    });

    testWidgets(
        'deciding every core step reveals the CTA, which fires onDone and '
        'persists permissions_primed', (tester) async {
      var done = false;
      await pumpPriming(tester,
          platform: TargetPlatform.android,
          requests: fakeRequests(location: false),
          onDone: () => done = true);

      // Decide all three one-tap steps (mix of grant / deny / skip).
      await tester.tap(inStep('notifications', find.text('Allow')));
      await tester.pumpAndSettle();
      await tester.tap(inStep('sms', find.text('Skip')));
      await tester.pumpAndSettle();
      expect(find.text('Run my first check'), findsNothing);
      await tester.tap(inStep('location', find.text('Allow')));
      await tester.pumpAndSettle();

      // Advanced steps stay undecided — they must not gate the CTA.
      final cta = find.text('Run my first check');
      expect(cta, findsOneWidget);

      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(done, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('permissions_primed'), isTrue);
    });

    testWidgets(
        'Skip for now opts out entirely: onDone + prefs flag, zero requests',
        (tester) async {
      var done = false;
      final log = <String>[];
      await pumpPriming(tester,
          platform: TargetPlatform.android,
          requests: fakeRequests(log: log),
          onDone: () => done = true);

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(log, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('permissions_primed'), isTrue);
    });
  });

  group('iOS priming flow', () {
    testWidgets('renders ONLY notifications and location, with honest iOS copy',
        (tester) async {
      await pumpPriming(tester, platform: TargetPlatform.iOS);

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text("Check that the Wi-Fi network you're on is safe."),
          findsOneWidget);

      // No Android-isms: these permissions don't exist on iOS.
      expect(find.text('Storage'), findsNothing);
      expect(find.text('SMS'), findsNothing);
      expect(find.text('Usage access'), findsNothing);
      expect(find.text('Accessibility'), findsNothing);
      expect(find.text('Opens system Settings'), findsNothing);
      expect(find.textContaining('ADVANCED'), findsNothing);
      expect(
          find.text(
              'Spot apps secretly tracking where you go, and test Wi-Fi safety.'),
          findsNothing);
    });

    testWidgets('deciding both iOS steps reveals the CTA and completes',
        (tester) async {
      var done = false;
      await pumpPriming(tester,
          platform: TargetPlatform.iOS, onDone: () => done = true);

      expect(find.text('Run my first check'), findsNothing);

      await tester.tap(inStep('notifications', find.text('Allow')));
      await tester.pumpAndSettle();
      await tester.tap(inStep('location', find.text('Skip')));
      await tester.pumpAndSettle();

      final cta = find.text('Run my first check');
      expect(cta, findsOneWidget);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(done, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('permissions_primed'), isTrue);
    });
  });
}
