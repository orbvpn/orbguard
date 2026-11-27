// The parts of a desktop window that a phone does not have: the sidebar,
// the command palette, and the keys that reach both.
//
// A desktop app should answer the keyboard. The palette opens with Cmd K on
// a Mac and Ctrl K elsewhere, and the four tabs answer Cmd or Ctrl and 1 to
// 4, as they do in the system's own apps.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../providers/account_provider.dart';
import '../../providers/scan_credit_provider.dart';
import '../../widgets/sale/credit_balance.dart';
import '../../widgets/sale/login_sheet.dart';
import '../../widgets/sale/plans_sheet.dart';
import '../theme/brand.dart';
import '../widgets/duotone_icon.dart';
import '../widgets/glass_bottom_nav.dart';
import '../widgets/pressable.dart';

/// A Mac window's title bar, drawn by the app under the system's clear one:
/// the window's name in the middle, with the traffic lights over its left
/// end. It takes no clicks. The system's strip that drags the window lies
/// over exactly these 40 points (MainFlutterWindow.swift).
class DeskTitleBar extends StatelessWidget {
  const DeskTitleBar({super.key});

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Brand tokens flip with the theme
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Brand.surface,
        border: Border(bottom: BorderSide(color: Brand.hairline)),
      ),
      // The system already gives the window its name.
      child: ExcludeSemantics(
        child: Text('OrbGuard',
            maxLines: 1,
            style: BrandText.body(
                    size: 13, weight: FontWeight.w500, color: Brand.text2)
                .copyWith(height: 1)),
      ),
    );
  }
}

/// The modifier key the platform's own shortcuts use, as its keys show it.
String deskModifier(TargetPlatform platform) =>
    platform == TargetPlatform.macOS ? '⌘' : 'Ctrl ';

/// The sidebar of a desktop window: the brand, the way into the palette,
/// the four tabs, the plan and the account.
class DeskSidebar extends StatelessWidget {
  const DeskSidebar({
    super.key,
    required this.platform,
    required this.items,
    required this.selected,
    required this.onTab,
    required this.onSearch,
    required this.onAccount,
  });

  final TargetPlatform platform;
  final List<NavItem> items;

  /// Position of the tab that is showing.
  final int selected;
  final ValueChanged<int> onTab;
  final VoidCallback onSearch;
  final VoidCallback onAccount;

  static const double width = 224;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Brand tokens flip with the theme
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Brand.glassFill,
        border: Border(right: BorderSide(color: Brand.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
            child: Row(
              children: [
                SvgPicture.asset('assets/branding/orbguard_icon.svg',
                    width: 26, height: 26),
                const SizedBox(width: 10),
                Text('OrbGuard',
                    style: BrandText.heading(size: 18).copyWith(height: 1)),
              ],
            ),
          ),
          _SearchButton(
            shortcut: '${deskModifier(platform)}K',
            onTap: onSearch,
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _TabButton(
                item: items[i],
                selected: i == selected,
                onTap: () => onTab(i),
              ),
            ),
          const Spacer(),
          _PlanMini(sells: platform == TargetPlatform.macOS),
          const SizedBox(height: 6),
          _AccountRow(onTap: onAccount),
        ],
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.shortcut, required this.onTap});

  final String shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(10);
    return Pressable(
      onTap: onTap,
      radius: radius,
      semanticLabel: 'Search or run a command, $shortcut',
      child: Container(
        height: 36,
        padding: const EdgeInsetsDirectional.only(start: 10, end: 9),
        decoration: BoxDecoration(
          color: Brand.hairline,
          borderRadius: radius,
          border: Border.all(color: Brand.border),
        ),
        child: Row(
          children: [
            DuotoneIcon(AppIcons.search, size: 16, color: Brand.text2),
            const SizedBox(width: 9),
            Expanded(
              child: Text('Search or run',
                  maxLines: 1,
                  style: BrandText.body(size: 13.5, color: Brand.text2)
                      .copyWith(height: 1)),
            ),
            Keycap(shortcut),
          ],
        ),
      ),
    );
  }
}

/// A key, as the palette and the sidebar show one. The Mac's command key is
/// drawn as its icon, since the bundled fonts have no glyph for it.
class Keycap extends StatelessWidget {
  const Keycap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final bool command = label.startsWith('⌘');
    final Text text = Text(command ? label.substring(1) : label,
        maxLines: 1,
        style:
            BrandText.mono(size: 11, color: Brand.text2).copyWith(height: 1));
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Brand.border),
        ),
        child: command
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DuotoneIcon(AppIcons.command, size: 11, color: Brand.text2),
                  const SizedBox(width: 2),
                  text,
                ],
              )
            : text,
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(11);
    final Color ink = selected ? Brand.navActive : Brand.text2;
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(
        onTap: onTap,
        radius: radius,
        semanticLabel: item.label,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? Brand.navActivePill : Colors.transparent,
            borderRadius: radius,
          ),
          child: Row(
            children: [
              DuotoneIcon(item.activeIconPath ?? item.iconPath,
                  size: 19, color: ink),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  style: BrandText.body(
                    size: 14.5,
                    weight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: ink,
                  ).copyWith(height: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The plan, small: what it is, and on a Mac the way to go unlimited. It
/// says what the Me tab's plan card says, from the same account and credits.
class _PlanMini extends StatelessWidget {
  const _PlanMini({required this.sells});

  /// Whether this build may lead to the plans. Windows and Linux builds
  /// never show plans or prices.
  final bool sells;

  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();
    final ScanCreditProvider credits = context.watch<ScanCreditProvider>();
    final String title;
    final String? line;
    if (account.hasPremium) {
      title = '${account.subscriptionLabel} plan';
      line = 'Unlimited checks';
    } else {
      title = 'Free plan';
      line = account.isLoggedIn && credits.balanceKnown
          ? scanCredits(credits.balance)
          : null;
    }
    final bool upsell = sells && !account.hasPremium;

    return FetchCreditBalance(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Brand.hairline,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: BrandText.title(size: 14.5, color: Brand.text)
                    .copyWith(height: 1.2)),
            if (line != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(line,
                    style: BrandText.body(size: 12.5, color: Brand.text2)
                        .copyWith(height: 1.3)),
              ),
            if (upsell)
              Pressable(
                onTap: () => showPlansSheet(context),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Go unlimited',
                          style: BrandText.title(size: 13, color: Brand.text)
                              .copyWith(height: 1.4)),
                      const SizedBox(width: 1),
                      DuotoneIcon(AppIcons.chevronRight,
                          size: 14, color: Brand.text2),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Who is signed in, or the way to sign in. It opens the Me tab.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AccountProvider account = context.watch<AccountProvider>();
    final bool signedIn = account.isLoggedIn;
    final String? email = account.email;
    final String? named = account.displayName?.trim();
    final String name = signedIn
        ? ((named != null && named.isNotEmpty) ? named : (email ?? 'Signed in'))
        : 'Sign in';
    final String? under =
        signedIn && email != null && email != name ? email : null;
    final BorderRadius radius = BorderRadius.circular(12);

    return Pressable(
      onTap: signedIn ? onTap : () => showLoginSheet(context),
      radius: radius,
      semanticLabel: signedIn ? 'Account, $name' : 'Sign in',
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.glassFill,
                border: Border.all(color: Brand.glassBorder),
              ),
              child: signedIn
                  ? Text(name.characters.first.toUpperCase(),
                      style: BrandText.heading(size: 14).copyWith(height: 1))
                  : DuotoneIcon(AppIcons.userRounded,
                      size: 17, color: Brand.text),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: BrandText.title(size: 14, color: Brand.text)
                          .copyWith(height: 1.2)),
                  if (under != null)
                    Text(under,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: BrandText.body(size: 12, color: Brand.text2)
                            .copyWith(height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One thing the palette can do.
@immutable
class PaletteCommand {
  const PaletteCommand(this.icon, this.label, this.run);

  final String icon;
  final String label;
  final VoidCallback run;
}

/// The command palette: type a few letters, pick with the arrows, press
/// Enter. Escape or a click outside closes it.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.commands,
    required this.onClose,
  });

  final List<PaletteCommand> commands;
  final VoidCallback onClose;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _field = FocusNode();
  int _selected = 0;

  /// A command runs once, however Enter reaches the palette.
  bool _ran = false;

  List<PaletteCommand> get _shown {
    final String q = _query.text.trim().toLowerCase();
    return [
      for (final PaletteCommand c in widget.commands)
        if (c.label.toLowerCase().contains(q)) c,
    ];
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() => _selected = 0));
  }

  @override
  void dispose() {
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  void _run(PaletteCommand c) {
    if (_ran) return;
    _ran = true;
    widget.onClose();
    c.run();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final List<PaletteCommand> shown = _shown;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      if (shown.isEmpty) return KeyEventResult.handled;
      final int step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _selected = (_selected + step) % shown.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_selected < shown.length) _run(shown[_selected]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final List<PaletteCommand> shown = _shown;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: ColoredBox(color: Brand.scrim),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 104),
            child: Focus(
              onKeyEvent: _onKey,
              child: Container(
                width: 520,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Brand.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Brand.glassBorder),
                  boxShadow: Brand.shadow,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 54,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border:
                              Border(bottom: BorderSide(color: Brand.hairline)),
                        ),
                        child: Row(
                          children: [
                            DuotoneIcon(AppIcons.search,
                                size: 18, color: Brand.text2),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _query,
                                focusNode: _field,
                                autofocus: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                cursorColor: Brand.limeInk,
                                style:
                                    BrandText.body(size: 16, color: Brand.text),
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  hintText: 'Type a command',
                                  hintStyle: BrandText.body(
                                      size: 16, color: Brand.text3),
                                ),
                                onSubmitted: (_) {
                                  if (_selected < shown.length) {
                                    _run(shown[_selected]);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: shown.isEmpty
                            ? Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                child: Text('Nothing matches. Try “check”.',
                                    style: BrandText.body(
                                        size: 13.5, color: Brand.text2)),
                              )
                            : Column(
                                children: [
                                  for (int i = 0; i < shown.length; i++)
                                    _CommandRow(
                                      command: shown[i],
                                      selected: i == _selected,
                                      onTap: () => _run(shown[i]),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.selected,
    required this.onTap,
  });

  final PaletteCommand command;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(10);
    final Color ink = selected ? Brand.limeInk : Brand.text;
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        radius: radius,
        semanticLabel: command.label,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? Brand.navActivePill : Colors.transparent,
            borderRadius: radius,
          ),
          child: Row(
            children: [
              DuotoneIcon(command.icon,
                  size: 18, color: selected ? Brand.limeInk : Brand.text2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(command.label,
                    maxLines: 1,
                    style: BrandText.body(
                      size: 15,
                      weight: FontWeight.w500,
                      color: ink,
                    ).copyWith(height: 1)),
              ),
              if (selected) const Keycap('Enter'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keys a desktop window answers: the palette, and a tab by its number.
class DeskKeys extends StatelessWidget {
  const DeskKeys({
    super.key,
    required this.platform,
    required this.onPalette,
    required this.onTab,
    required this.tabs,
    required this.child,
  });

  final TargetPlatform platform;
  final VoidCallback onPalette;
  final ValueChanged<int> onTab;

  /// How many tabs there are, so only their numbers are taken.
  final int tabs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool mac = platform == TargetPlatform.macOS;
    SingleActivator key(LogicalKeyboardKey k) =>
        SingleActivator(k, meta: mac, control: !mac);
    const List<LogicalKeyboardKey> digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ];
    return CallbackShortcuts(
      bindings: {
        key(LogicalKeyboardKey.keyK): onPalette,
        for (int i = 0; i < tabs && i < digits.length; i++)
          key(digits[i]): () => onTab(i),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
