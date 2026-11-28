/// The sale line under a check's results: the scan credits left, then
/// "Go unlimited". The whole row is one press, to the credits sheet.
///
/// A subscriber sees nothing here: there is nothing to count. Nor does the
/// Amazon build, where no credit can be earned and no plan taken.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/pressable.dart';
import '../../providers/account_provider.dart';
import '../../providers/scan_credit_provider.dart';
import '../../utils/amazon_build.dart';
import '../scan_credits/credits_sheet.dart';
import 'credit_balance.dart';

class CreditLine extends StatelessWidget {
  const CreditLine({super.key});

  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();
    if (account.hasPremium || isAmazonBuild(context)) {
      return const SizedBox.shrink();
    }
    final ScanCreditProvider credits = context.watch<ScanCreditProvider>();

    // Signed out there is no balance, and until the server has said it the
    // number is not known: both read as the plain rule instead.
    final String text = account.isLoggedIn && credits.balanceKnown
        ? '${scanCredits(credits.balance)} left'
        : 'Later checks use scan credits';

    final BorderRadius radius = BorderRadius.circular(Brand.rMd);
    return FetchCreditBalance(
      child: Pressable(
        onTap: () => showCreditsSheet(context),
        radius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration:
              BoxDecoration(color: Brand.hairline, borderRadius: radius),
          child: Row(
            children: [
              DuotoneIcon(AppIcons.ticket, size: 18, color: Brand.text2),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: BrandText.body(
                            size: 14,
                            weight: FontWeight.w500,
                            color: Brand.text)
                        .copyWith(height: Brand.bodyHeight(1.2))),
              ),
              const SizedBox(width: 10),
              Text('Go unlimited',
                  style: BrandText.title(size: 14, color: Brand.text)),
              const SizedBox(width: 2),
              DuotoneIcon(AppIcons.chevronRight, size: 17, color: Brand.text2),
            ],
          ),
        ),
      ),
    );
  }
}
