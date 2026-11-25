/// Sign-in, as a sheet.
///
/// The sign-in screen closes its own route with true once the person is
/// signed in (from any of its paths, or from a link handled above it). In a
/// sheet that route is the sheet, so the sheet's result is the sign-in's.
library;

import 'package:flutter/material.dart';

import '../../presentation/widgets/app_sheet.dart';
import '../../screens/account/login_screen.dart';

/// Presents sign-in. Completes with true when the person signed in; with
/// false or null when they closed it first.
Future<bool?> showLoginSheet(BuildContext context) => showAppSheet<bool>(
      context,
      heightFactor: 0.94,
      child: const LoginScreen(),
    );
