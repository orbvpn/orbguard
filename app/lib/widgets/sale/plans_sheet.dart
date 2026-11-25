/// The plans, as a sheet: the pricing screen slides up over whatever the
/// person was doing and closes back to it.
///
/// The pricing screen itself is untouched. Its prices come from the store,
/// and its billing, renewal and legal words are there for store review.
library;

import 'package:flutter/material.dart';

import '../../presentation/widgets/app_sheet.dart';
import '../../screens/pricing/pricing_screen.dart';

/// Presents the plans. Completes when the sheet closes.
Future<void> showPlansSheet(BuildContext context) => showAppSheet<void>(
      context,
      heightFactor: 0.94,
      child: const PricingScreen(),
    );
