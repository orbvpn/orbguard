// Stand-ins for the tray and the window on a Windows or Linux computer, so a
// test can watch what the tray is told and press what a person would press,
// without a platform channel.

import 'package:flutter/foundation.dart';

import 'package:orbguard/services/desktop/desktop_tray.dart';

class FakeTray implements TrayHost {
  FakeTray({this.shows = true, this.failsIcon = false});

  /// Whether the computer has a tray that shows icons.
  bool shows;

  /// Putting the icon in fails.
  bool failsIcon;

  /// Every call, in order, by name.
  final List<String> calls = [];

  String? icon;
  String? tip;
  List<TrayItem> menu = const [];
  bool removed = false;

  VoidCallback? _click;
  VoidCallback? _rightClick;
  void Function(TrayCommand command)? _command;

  /// The menu's status line, or null when it has none.
  String? get status {
    final List<TrayItem> lines = [
      for (final TrayItem i in menu)
        if (!i.isSeparator && !i.enabled) i,
    ];
    return lines.isEmpty ? null : lines.first.label;
  }

  /// The labels of the rows that can be pressed, in order.
  List<String> get commands => [
        for (final TrayItem i in menu)
          if (i.enabled) i.label!,
      ];

  void click() => _click?.call();
  void rightClick() => _rightClick?.call();
  void press(TrayCommand command) => _command?.call(command);

  @override
  Future<bool> canShow() async {
    calls.add('canShow');
    return shows;
  }

  @override
  Future<void> setIcon(String asset) async {
    calls.add('setIcon');
    if (failsIcon) throw StateError('no icon');
    icon = asset;
    removed = false;
  }

  @override
  Future<void> setToolTip(String text) async {
    calls.add('setToolTip');
    tip = text;
  }

  @override
  Future<void> setMenu(List<TrayItem> items) async {
    calls.add('setMenu');
    menu = items;
  }

  @override
  Future<void> popUpMenu() async => calls.add('popUpMenu');

  @override
  Future<void> remove() async {
    calls.add('remove');
    removed = true;
  }

  @override
  void listen({
    required VoidCallback onClick,
    required VoidCallback onRightClick,
    required void Function(TrayCommand command) onCommand,
  }) {
    _click = onClick;
    _rightClick = onRightClick;
    _command = onCommand;
  }

  @override
  void stopListening() {
    _click = null;
    _rightClick = null;
    _command = null;
  }
}

class FakeWindow implements WindowHost {
  /// Every call, in order, by name.
  final List<String> calls = [];

  bool kept = false;
  bool hidden = false;
  bool ended = false;
  int broughtForward = 0;

  VoidCallback? _close;

  /// The person presses the window's close button. Returns whether the
  /// window closed (it closes unless it is kept).
  bool close() {
    _close?.call();
    return !kept;
  }

  @override
  Future<void> attach() async => calls.add('attach');

  @override
  Future<void> keepOnClose(bool keep) async {
    calls.add('keepOnClose($keep)');
    kept = keep;
  }

  @override
  Future<void> bringForward() async {
    calls.add('bringForward');
    broughtForward++;
    hidden = false;
  }

  @override
  Future<void> hide() async {
    calls.add('hide');
    hidden = true;
  }

  @override
  Future<void> quit() async {
    calls.add('quit');
    ended = true;
  }

  @override
  void listen({required VoidCallback onClose}) => _close = onClose;

  @override
  void stopListening() => _close = null;
}
