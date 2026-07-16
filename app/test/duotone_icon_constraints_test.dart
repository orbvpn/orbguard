import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/presentation/widgets/duotone_icon.dart';

void main() {
  testWidgets('DuotoneIcon keeps its size under tight constraints', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
            // No Center — the old code let tight 64×64 constraints stretch the svg.
            child: const DuotoneIcon('check_circle', size: 36),
          ),
        ),
      ),
    );
    await tester.pump();

    // The painted svg must be 36×36, not 64×64.
    final svgSize = tester.getSize(find.byType(SvgPicture));
    expect(svgSize.width, 36);
    expect(svgSize.height, 36);
  });
}
