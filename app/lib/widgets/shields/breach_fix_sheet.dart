/// The fix for the Identity & breach gap: which watched address was in a
/// breach, three plain steps, and one way to say it is dealt with. Every
/// word about the breach comes from [DarkWebProvider]: the address in its own
/// masked form, and the breach's real name and year when a check or alert
/// gave them, or else only the real count.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/api/sms_analysis.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/darkweb_provider.dart';
import '../../screens/shields/shields_screen.dart';
import '../../services/home/home_brief.dart';

/// Opens the fix sheet for the first open breach. "See what leaked" closes
/// it and opens the Identity & breach screen as a sheet from [context], with
/// that address's breach details made the Email tab's result first (from
/// memory, or a fresh check of the address). When neither is possible (the
/// address is only known masked), the link says "Open Identity & breach".
Future<void> showBreachFixSheet(BuildContext context) => showAppSheet<void>(
      context,
      child: BreachFixSheet(
        onSeeWhatLeaked: () => showAppSheet<void>(
          context,
          heightFactor: 0.94,
          child: shieldScreen(Shield.identity),
        ),
      ),
    );

class BreachFixSheet extends StatelessWidget {
  const BreachFixSheet({super.key, this.onSeeWhatLeaked});

  /// Called after the sheet has closed.
  final VoidCallback? onSeeWhatLeaked;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final DarkWebProvider provider = context.watch<DarkWebProvider>();
    final List<MonitoredAsset> open = provider.openBreaches;

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      child: SingleChildScrollView(
        child: open.isEmpty
            ? _Empty(provider: provider)
            : _Open(
                provider: provider,
                asset: open.first,
                remaining: open.length - 1,
                onSeeWhatLeaked: onSeeWhatLeaked,
              ),
      ),
    );
  }
}

class _Open extends StatelessWidget {
  const _Open({
    required this.provider,
    required this.asset,
    required this.remaining,
    required this.onSeeWhatLeaked,
  });

  final DarkWebProvider provider;
  final MonitoredAsset asset;
  final int remaining;
  final VoidCallback? onSeeWhatLeaked;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int count = provider.breachCountFor(asset.id);
    final BreachInfo? named = provider.newestNamedBreachFor(asset.id);
    final String? name = named == null
        ? null
        : (named.title.trim().isNotEmpty
            ? named.title.trim()
            : named.name.trim());
    final int? year = named?.breachDate?.year;
    final bool canSee = provider.canShowLeakDetailsFor(asset.id);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _IconTile(
            icon: AppIcons.userId,
            fill: Brand.amberPill,
            ink: Brand.amberInk,
          ),
        ),
        const SizedBox(height: 14),
        Text('Your email was in a data breach',
            style: BrandText.h2(color: cs.onSurface, size: 21)
                .copyWith(height: Brand.displayHeight(1.25))),
        const SizedBox(height: 8),
        Text(
          breachSentence(
              address: asset.displayValue,
              count: count,
              name: name,
              year: year),
          style: BrandText.body(size: 15, color: cs.onSurfaceVariant)
              .copyWith(height: Brand.bodyHeight(1.45)),
        ),
        const SizedBox(height: 20),
        _Step(
          number: 1,
          title: name != null
              ? 'Change your $name password'
              : count > 1
                  ? 'Change the password of each breached account'
                  : 'Change the password of the breached account',
          detail: count > 1
              ? 'Start there. Those are the ones that leaked.'
              : 'Start there. That is the one that leaked.',
        ),
        const SizedBox(height: 14),
        const _Step(
          number: 2,
          title: 'Change it anywhere you reused it',
          detail: 'A leaked password gets tried on other sites.',
        ),
        const SizedBox(height: 14),
        const _Step(
          number: 3,
          title: 'Turn on two-step sign-in',
          detail: 'Wherever the site offers it.',
        ),
        const SizedBox(height: 22),
        if (remaining > 0) ...[
          Text(
            remaining == 1
                ? '1 more address is waiting after this one.'
                : '$remaining more addresses are waiting after this one.',
            textAlign: TextAlign.center,
            style: BrandText.body(size: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
        ],
        BrandButton(
          label: 'I changed it. Close the gap',
          onPressed: () async {
            Navigator.of(context).pop();
            await provider.markBreachHandled(asset.id);
          },
        ),
        const SizedBox(height: 4),
        _QuietButton(
          label: canSee ? 'See what leaked' : 'Open Identity & breach',
          onPressed: () {
            Navigator.of(context).pop();
            if (canSee) unawaited(provider.showLeakDetailsFor(asset.id));
            onSeeWhatLeaked?.call();
          },
        ),
        _QuietButton(
          label: 'Not now',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// The one sentence about the breach, from real values only. [name] and
/// [year] are left out when the source did not give them.
@visibleForTesting
String breachSentence({
  required String address,
  required int count,
  String? name,
  int? year,
}) {
  final String when = year == null ? '' : ' in $year';
  if (name != null && count <= 1) {
    return '$address was in the $name breach$when.';
  }
  if (name != null) {
    return '$address was found in $count known breaches, including $name$when.';
  }
  return count == 1
      ? '$address was found in 1 known breach.'
      : '$address was found in $count known breaches.';
}

class _Empty extends StatelessWidget {
  const _Empty({required this.provider});

  final DarkWebProvider provider;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool watching = provider.assets.any((a) => a.type == AssetType.email);
    final String body = !watching
        ? 'No email address is being watched yet.'
        : provider.openBreachedAccounts == null
            ? 'Your watched addresses have not been checked yet.'
            : 'No watched address has a breach you have not dealt with.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _IconTile(
            icon: AppIcons.shieldCheck,
            fill: AppColors.accentPill,
            ink: Brand.limeInk,
          ),
        ),
        const SizedBox(height: 14),
        Text('No open breaches',
            style: BrandText.h2(color: cs.onSurface, size: 21)
                .copyWith(height: Brand.displayHeight(1.25))),
        const SizedBox(height: 8),
        Text(body,
            style: BrandText.body(size: 15, color: cs.onSurfaceVariant)
                .copyWith(height: Brand.bodyHeight(1.45))),
        const SizedBox(height: 22),
        BrandButton.secondary(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.fill, required this.ink});

  final String icon;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
      ),
      child: Center(child: DuotoneIcon(icon, size: 26, color: ink)),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(
      {required this.number, required this.title, required this.detail});

  final int number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: Brand.hairline, shape: BoxShape.circle),
          child: Text('$number',
              style: BrandText.title(size: 13, color: cs.onSurface)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              Text(title,
                  style: BrandText.title(size: 15.5, color: cs.onSurface)
                      .copyWith(height: Brand.displayHeight(1.3))),
              const SizedBox(height: 2),
              Text(detail,
                  style: BrandText.body(size: 13.5, color: cs.onSurfaceVariant)
                      .copyWith(height: Brand.bodyHeight(1.4))),
            ],
          ),
        ),
      ],
    );
  }
}

/// A quiet way out: muted text, no fill, full tap height.
class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
      child: Text(label,
          textAlign: TextAlign.center,
          style: BrandText.title(
              size: 15, weight: FontWeight.w500, color: cs.onSurfaceVariant)),
    );
  }
}
