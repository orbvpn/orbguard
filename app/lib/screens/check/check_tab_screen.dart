/// The **Check** tab on a phone: "Not sure about something? Ask."
///
/// The paste card on top asks the scam shield's analyser about one thing.
/// Under it, every on-demand tool this device can run is one tap away, each
/// opening its real screen as a sheet. Last comes the full check, which the
/// shell owns.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_rows.dart';
import '../../presentation/widgets/page_head.dart';
import '../../presentation/widgets/pressable.dart';
import '../../providers/network_provider.dart';
import '../../utils/host_platform.dart';
import '../../widgets/check/paste_card.dart';
import 'check_tools.dart';

class CheckTabScreen extends StatelessWidget {
  const CheckTabScreen({
    super.key,
    required this.onRunFullCheck,
    required this.fullCheckCount,
    this.platform,
    this.analyse,
  });

  /// Starts the full check of this phone (the shell owns it).
  final VoidCallback onRunFullCheck;

  /// How many checks the full check can run on this phone.
  final int fullCheckCount;

  /// The platform whose tools are shown. Null is the one this runs on; tests
  /// name one.
  final TargetPlatform? platform;

  /// Stands in for the scam shield's analyser in the paste card, for tests.
  final PasteAnalyser? analyse;

  /// One readable column, centred on a wide screen, as Home is.
  static const double _maxColumn = 480;

  /// Tiles sit two to a row.
  static const int _perRow = 2;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Brand tokens flip with the theme
    final TargetPlatform? on = platform ?? hostPlatform();
    final String noun = deviceNounFor(on);
    final List<CheckTool> tools = CheckTool.availableOn(on);
    // Tiles fill whole rows only. A tool left over joins the list below, so
    // no tile ever sits alone.
    final int over = tools.length % _perRow;
    final List<CheckTool> tiles = tools.sublist(0, tools.length - over);
    final List<CheckTool> rest = tools.sublist(tools.length - over);

    return LayoutBuilder(builder: (context, constraints) {
      final double column = math.min(constraints.maxWidth - 40, _maxColumn);
      final double side = (constraints.maxWidth - column) / 2;

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          side,
          8,
          side,
          16 +
              GlassTheme.bottomNavClearance +
              MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const PageHead(
              title: 'Check', subtitle: 'Not sure about something? Ask.'),
          PasteCard(analyse: analyse),
          const SectionLabel('Quick checks'),
          for (int i = 0; i < tiles.length; i += _perRow)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int j = 0; j < _perRow; j++) ...[
                      if (j > 0) const SizedBox(width: 12),
                      Expanded(
                        child: _ToolTile(
                          key: ValueKey('tile-${tiles[i + j].name}'),
                          tool: tiles[i + j],
                          onTap: () => _open(context, tiles[i + j]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: tiles.isEmpty ? 0 : 12),
            child: GlassRows(rows: [
              for (final CheckTool t in rest)
                GlassRow(
                  key: ValueKey('row-${t.name}'),
                  icon: t.icon,
                  title: t.title,
                  line: t.line,
                  onTap: () => _open(context, t),
                ),
              GlassRow(
                icon: AppIcons.shieldCheck,
                title: 'Full privacy check',
                line: fullCheckCount == 1
                    ? 'The one check this $noun can run'
                    : 'All $fullCheckCount checks this $noun can run',
                onTap: onRunFullCheck,
              ),
            ]),
          ),
        ],
      );
    });
  }

  void _open(BuildContext context, CheckTool tool) {
    if (tool == CheckTool.wifi) {
      // The network screen shows the joined network only once it has been
      // read; until then it says "Not Connected". Read it on the way in.
      context.read<NetworkProvider>().refreshNetworkInfo();
    }
    showAppSheet<void>(context, heightFactor: 0.94, child: tool.screen());
  }
}

/// A tool as a glass tile: the kit's `.tool`.
class _ToolTile extends StatelessWidget {
  const _ToolTile({super.key, required this.tool, required this.onTap});

  final CheckTool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: '${tool.title}. ${tool.line}',
      radius: BorderRadius.circular(20),
      child: BrandGlass(
        radius: 20,
        elevated: false,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon: tool.icon, color: Brand.limeInk),
            const SizedBox(height: 12),
            Text(tool.title,
                style: BrandText.title(size: 16)
                    .copyWith(height: Brand.displayHeight(1.3))),
            const SizedBox(height: 2),
            Text(tool.line,
                style: BrandText.body(size: 13.5)
                    .copyWith(height: Brand.bodyHeight(1.45))),
          ],
        ),
      ),
    );
  }
}
