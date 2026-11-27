// The tray and the window on a real Windows or Linux computer, through the
// tray_manager and window_manager plugins.
//
// Kept apart from desktop_tray.dart so tests never reach a platform channel:
// they give DesktopTray stand-ins for these two.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart' as tm;
import 'package:window_manager/window_manager.dart';

import 'desktop_tray.dart';

class PluginTrayHost with tm.TrayListener implements TrayHost {
  PluginTrayHost(this.platform);

  final TargetPlatform platform;

  VoidCallback? _onClick;
  VoidCallback? _onRightClick;
  void Function(TrayCommand command)? _onCommand;

  /// The command each menu row stands for, by the row's key.
  static String _key(TrayCommand command) => command.name;

  @override
  Future<bool> canShow() async {
    // Windows always has a notification area.
    if (platform != TargetPlatform.linux) return true;
    // A Linux desktop shows tray icons only where a StatusNotifier host runs
    // (KDE, most others, GNOME with the AppIndicator extension). Without
    // one the icon would never be seen, so it is not put in.
    try {
      final ProcessResult r = await Process.run('gdbus', const [
        'call',
        '--session',
        '--dest',
        'org.kde.StatusNotifierWatcher',
        '--object-path',
        '/StatusNotifierWatcher',
        '--method',
        'org.freedesktop.DBus.Properties.Get',
        'org.kde.StatusNotifierWatcher',
        'IsStatusNotifierHostRegistered',
      ]).timeout(const Duration(seconds: 3));
      return r.exitCode == 0 && '${r.stdout}'.contains('true');
    } on Object catch (e) {
      debugPrint('[OrbGuard] Could not ask for a tray: $e');
      return false;
    }
  }

  @override
  Future<void> setIcon(String asset) => tm.trayManager.setIcon(_onDisk(asset));

  @override
  Future<void> setToolTip(String text) async {
    // A Linux tray (AppIndicator) has no tooltip to set.
    if (platform != TargetPlatform.windows) return;
    // Windows keeps 127 characters of it.
    await tm.trayManager
        .setToolTip(text.length > 127 ? text.substring(0, 127) : text);
  }

  @override
  Future<void> setMenu(List<TrayItem> items) => tm.trayManager.setContextMenu(
        tm.Menu(items: [
          for (final TrayItem item in items)
            if (item.isSeparator)
              tm.MenuItem.separator()
            else
              tm.MenuItem(
                key: item.command == null ? null : _key(item.command!),
                label: item.label,
                disabled: !item.enabled,
              ),
        ]),
      );

  @override
  Future<void> popUpMenu() async {
    // A Linux tray opens its menu by itself, on any click.
    if (platform != TargetPlatform.windows) return;
    // Bringing the app forward is what lets a click elsewhere close the menu
    // on Windows. It does not show a hidden window.
    // ignore: deprecated_member_use
    await tm.trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  Future<void> remove() => tm.trayManager.destroy();

  @override
  void listen({
    required VoidCallback onClick,
    required VoidCallback onRightClick,
    required void Function(TrayCommand command) onCommand,
  }) {
    _onClick = onClick;
    _onRightClick = onRightClick;
    _onCommand = onCommand;
    tm.trayManager.addListener(this);
  }

  @override
  void stopListening() {
    tm.trayManager.removeListener(this);
    _onClick = null;
    _onRightClick = null;
    _onCommand = null;
  }

  @override
  void onTrayIconMouseDown() => _onClick?.call();

  @override
  void onTrayIconRightMouseDown() => _onRightClick?.call();

  @override
  void onTrayMenuItemClick(tm.MenuItem menuItem) {
    for (final TrayCommand command in TrayCommand.values) {
      if (menuItem.key == _key(command)) _onCommand?.call(command);
    }
  }

  /// The plugin is given a full path, so the same file is found inside a
  /// snap, where the plugin would otherwise ask the icon theme for a name.
  static String _onDisk(String asset) => File(Platform.resolvedExecutable)
      .parent
      .uri
      .resolve('data/flutter_assets/$asset')
      .toFilePath();
}

class PluginWindowHost with WindowListener implements WindowHost {
  VoidCallback? _onClose;

  @override
  Future<void> attach() => windowManager.ensureInitialized();

  @override
  Future<void> keepOnClose(bool keep) => windowManager.setPreventClose(keep);

  @override
  Future<void> bringForward() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> quit() => windowManager.destroy();

  @override
  void listen({required VoidCallback onClose}) {
    _onClose = onClose;
    windowManager.addListener(this);
  }

  @override
  void stopListening() {
    windowManager.removeListener(this);
    _onClose = null;
  }

  @override
  void onWindowClose() => _onClose?.call();
}
