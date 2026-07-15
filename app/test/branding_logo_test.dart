import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The brand ring logo (assets/branding/orbguard_icon.svg) is rendered in-app
/// via flutter_svg (drawer header + About dialog). The SVG uses a radialGradient
/// + a mask (the ring hole) + an feDropShadow filter. flutter_svg supports the
/// gradient and mask and safely ignores the unsupported filter — this test pins
/// that it parses and renders without throwing so a future asset change can't
/// silently break the in-app branding.
void main() {
  testWidgets('brand ring SVG renders through flutter_svg without error',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SvgPicture.asset(
              'assets/branding/orbguard_icon.svg',
              width: 36,
              height: 36,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
