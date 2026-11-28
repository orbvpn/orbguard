/// The account card at the top of Me: who is signed in, and that one OrbVPN
/// account covers OrbGuard, OrbVPN and OrbBrowser.
///
/// Signed in, pressing it opens account security (passkeys, sign-in options,
/// deleting the account). Signed out, the whole card is the way to sign in.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/pressable.dart';
import '../../providers/account_provider.dart';
import '../../screens/account/security_screen.dart';
import '../../utils/amazon_build.dart';
import 'login_sheet.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();
    final bool signedIn = account.isLoggedIn;

    final String? email = account.email;
    final String? named = account.displayName;
    final String name = signedIn
        ? ((named != null && named.trim().isNotEmpty)
            ? named.trim()
            : (email ?? 'Signed in'))
        // The Amazon build creates no accounts.
        : (isAmazonBuild(context)
            ? 'Sign in'
            : 'Sign in or create an account');
    // The email goes under the name, unless the name already is the email.
    final String? under =
        signedIn && email != null && email != name ? email : null;
    final String initial =
        name.isEmpty ? '' : name.characters.first.toUpperCase();

    final BorderRadius radius = BorderRadius.circular(GlassTheme.radiusLarge);
    return Pressable(
      radius: radius,
      onTap: () {
        if (signedIn) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SecurityScreen()),
          );
        } else {
          showLoginSheet(context);
        }
      },
      child: BrandGlass(
        radius: GlassTheme.radiusLarge,
        elevated: false,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                BrandGlassCircle(
                  size: 52,
                  child: signedIn
                      ? Text(initial,
                          style: BrandText.heading(size: 20, color: Brand.text)
                              .copyWith(height: 1))
                      : DuotoneIcon(AppIcons.user, size: 24, color: Brand.text),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: BrandText.title(size: 16, color: Brand.text)
                              .copyWith(height: Brand.displayHeight(1.3))),
                      if (under != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(under,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: BrandText.body(
                                      size: 13.5, color: Brand.text2)
                                  .copyWith(height: Brand.bodyHeight(1.45))),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.only(top: 13),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Brand.hairline)),
              ),
              child: Row(
                children: [
                  DuotoneIcon(AppIcons.verifiedCheck,
                      size: 17, color: Brand.limeInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'One OrbVPN account for OrbGuard, OrbVPN and OrbBrowser',
                        style: BrandText.body(size: 13.5, color: Brand.text2)
                            .copyWith(height: Brand.bodyHeight(1.45))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
