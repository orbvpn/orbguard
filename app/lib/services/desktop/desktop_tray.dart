// The tray icon on a Windows or Linux computer, and the window it keeps.
//
// The Mac has its own menu bar ring, drawn natively from the same glance
// (macos/Runner/OrbGuardGlanceChannel.swift). On Windows and Linux the tray
// icon does that job: the ring in the state Home's ring is in, and a menu
// with Home's status line, Check now, Open OrbGuard and Quit OrbGuard. It is
// fed the same Glance the menu bar and the widgets are, so it can never say
// more than Home does.
//
// Closing the window keeps OrbGuard running, as on the Mac: the window hides
// and the tray icon stays, and Quit OrbGuard in its menu really quits. The
// window only hides once the icon is up. A computer whose tray cannot show it
// is never left with a hidden window and no way back: there, closing the
// window quits as it always did.
library;

import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../home/glance.dart';
import '../home/home_brief.dart';
import 'desktop_tray_plugins.dart';

/// What a row of the tray menu does.
enum TrayCommand { checkNow, open, quit }

/// One row of the tray menu: a line that only says something, a command, or
/// a separator.
@immutable
class TrayItem {
  const TrayItem._(this.label, this.command);

  /// A line that says something and does nothing when pressed.
  const TrayItem.line(String label) : this._(label, null);

  const TrayItem.command(TrayCommand command, String label)
      : this._(label, command);

  static const TrayItem separator = TrayItem._(null, null);

  /// The words on the row. Null for a separator.
  final String? label;

  /// What pressing it does. Null for a line or a separator.
  final TrayCommand? command;

  bool get isSeparator => label == null;
  bool get enabled => command != null;

  @override
  bool operator ==(Object other) =>
      other is TrayItem && other.label == label && other.command == command;

  @override
  int get hashCode => Object.hash(label, command);

  @override
  String toString() => isSeparator
      ? 'TrayItem.separator'
      : 'TrayItem(${command?.name ?? 'line'}, $label)';
}

/// The tray menu, worked out from the glance.
abstract final class TrayMenu {
  static const String checkNow = 'Check now';
  static const String open = 'Open OrbGuard';
  static const String quit = 'Quit OrbGuard';

  /// The rows for [glance] at [now]. Before there is any glance there is
  /// nothing to say and no check to start from here, as on the Mac: only
  /// Open OrbGuard and Quit OrbGuard.
  static List<TrayItem> of(
    Glance? glance, {
    required DateTime now,
    required bool use24h,
  }) {
    final String? status = statusLine(glance, now: now, use24h: use24h);
    return [
      if (status != null) ...[
        TrayItem.line(status),
        TrayItem.separator,
        const TrayItem.command(TrayCommand.checkNow, checkNow),
      ],
      const TrayItem.command(TrayCommand.open, open),
      TrayItem.separator,
      const TrayItem.command(TrayCommand.quit, quit),
    ];
  }

  /// Home's words for now, the way the Mac's menu bar ring says them: the
  /// glance's title (its stale title once the reading has gone stale), then
  /// when the check ran.
  static String? statusLine(
    Glance? glance, {
    required DateTime now,
    required bool use24h,
  }) {
    if (glance == null) return null;
    final DateTime? staleAt = glance.staleAt;
    final bool stale = staleAt != null && !now.isBefore(staleAt);
    final String? staleTitle = glance.staleTitle;
    final String title =
        stale && staleTitle != null ? staleTitle : glance.title;
    final DateTime? at = glance.checkedAt;
    if (at == null) return title;
    return '$title. Checked ${checkedWhen(at, now: now, use24h: use24h)}';
  }

  /// When a check ran, as the Today card says it: a time from today as a
  /// clock time in the reader's own format, an older one as how many days
  /// ago, in Home's words. Both stay true until midnight, when the tray is
  /// drawn again.
  static String checkedWhen(
    DateTime at, {
    required DateTime now,
    required bool use24h,
  }) {
    final int days =
        DateUtils.dateOnly(now).difference(DateUtils.dateOnly(at)).inDays;
    if (days <= 0) {
      return const DefaultMaterialLocalizations().formatTimeOfDay(
        TimeOfDay.fromDateTime(at),
        alwaysUse24HourFormat: use24h,
      );
    }
    return days == 1 ? 'yesterday' : '$days days ago';
  }

  /// What hovering the icon says.
  static String toolTip(
    Glance? glance, {
    required DateTime now,
    required bool use24h,
  }) {
    final String? status = statusLine(glance, now: now, use24h: use24h);
    return status == null ? 'OrbGuard' : 'OrbGuard. $status';
  }
}

/// Which picture of the ring the tray shows, and where it is kept.
///
/// The pictures are drawn ahead of time by
/// test/visual/tray_icons_render_test.dart, one for every state the ring can
/// be in: the logo mark before any glance, dots when never checked, and the
/// band (in colour, or still) open at every set of stations where something
/// can be found.
abstract final class TrayIcon {
  /// Where the ring can open: the stations of the shields that can find
  /// something, in degrees clockwise from twelve, in order.
  static final List<int> stations = [
    for (final Shield s in Shield.values)
      if (s.finding != null) s.angle.round(),
  ]..sort();

  static const List<int> windowsSizes = [16, 20, 24, 32];
  static const List<int> linuxSizes = [22, 24, 32];

  /// The name of the picture for [glance].
  static String keyFor(Glance? glance) {
    if (glance == null) return 'logo';
    if (glance.ring == GlanceRing.fresh) return 'fresh';
    final List<int> open = {
      for (final double g in glance.gaps) _station(g),
    }.toList()
      ..sort();
    final String band = glance.ring == GlanceRing.still ? 'still' : 'open';
    return [band, ...open].join('-');
  }

  /// Every picture the tray can ask for.
  static List<String> get keys {
    final List<String> all = ['logo', 'fresh'];
    for (final String band in const ['open', 'still']) {
      for (int set = 0; set < 1 << stations.length; set++) {
        all.add([
          band,
          for (int i = 0; i < stations.length; i++)
            if (set & (1 << i) != 0) stations[i],
        ].join('-'));
      }
    }
    return all;
  }

  /// The asset that holds picture [key] on [platform], for a taskbar of
  /// [shade], at a display [scale].
  static String asset(
    String key, {
    required TargetPlatform platform,
    required Brightness shade,
    double scale = 1,
  }) {
    final String theme = shade == Brightness.dark ? 'dark' : 'light';
    if (platform == TargetPlatform.windows) {
      // One .ico holds every size; Windows picks the one its tray wants.
      return 'assets/tray/windows/$theme/$key.ico';
    }
    return 'assets/tray/linux/$theme/$key-${linuxSize(scale)}.png';
  }

  /// A Linux tray takes one picture and scales it to its panel, so the one
  /// given is the size nearest above what a 22 point panel needs at [scale].
  static int linuxSize(double scale) {
    final double need = 22 * scale;
    return linuxSizes.firstWhere((int s) => s >= need - 0.5,
        orElse: () => linuxSizes.last);
  }

  /// A gap is drawn at its shield's station. One that is not at a station
  /// (there is none today) is drawn at the nearest, so the ring still opens.
  static int _station(double degrees) {
    final double at = (degrees % 360 + 360) % 360;
    double apart(int s) {
      final double d = (at - s).abs() % 360;
      return d > 180 ? 360 - d : d;
    }

    return stations.reduce((int a, int b) => apart(b) < apart(a) ? b : a);
  }
}

/// The operating system's tray, as OrbGuard uses it. Tests give a stand-in.
abstract class TrayHost {
  /// Whether an icon put in the tray would be seen.
  Future<bool> canShow();

  /// Shows the picture at [asset] (a path among the app's assets).
  Future<void> setIcon(String asset);
  Future<void> setToolTip(String text);
  Future<void> setMenu(List<TrayItem> items);

  /// Opens the menu where the pointer is, for a tray that does not open it
  /// by itself.
  Future<void> popUpMenu();

  /// Takes the icon out of the tray.
  Future<void> remove();

  void listen({
    required VoidCallback onClick,
    required VoidCallback onRightClick,
    required void Function(TrayCommand command) onCommand,
  });
  void stopListening();
}

/// The app's one window, as the tray uses it. Tests give a stand-in.
abstract class WindowHost {
  /// Readies the window to be hidden and brought back.
  Future<void> attach();

  /// While [keep] is true, the close button asks instead of closing.
  Future<void> keepOnClose(bool keep);

  /// Shows the window in front, restored if it was minimised.
  Future<void> bringForward();
  Future<void> hide();

  /// Closes the window for good, which ends the app.
  Future<void> quit();

  void listen({required VoidCallback onClose});
  void stopListening();
}

/// The tray icon and the window, kept saying what Home says.
class DesktopTray with WidgetsBindingObserver {
  DesktopTray({
    required this.platform,
    required TrayHost tray,
    required WindowHost window,
    DateTime Function()? clock,
    bool Function()? use24h,
    Brightness Function()? shade,
    double Function()? scale,
  })  : _tray = tray,
        _window = window,
        _clock = clock ?? DateTime.now,
        _use24h = use24h ?? _platformUse24h,
        _shade = shade ?? _platformShade,
        _scale = scale ?? _platformScale;

  /// The real tray and window, through the plugins.
  factory DesktopTray.forComputer(TargetPlatform platform) => DesktopTray(
        platform: platform,
        tray: PluginTrayHost(platform),
        window: PluginWindowHost(),
      );

  /// Where OrbGuard puts an icon in the tray. The Mac has its own menu bar
  /// ring instead.
  static bool runsOn(TargetPlatform? platform) =>
      platform == TargetPlatform.windows || platform == TargetPlatform.linux;

  /// Whether the window's close button hides the window instead of quitting:
  /// on a computer whose tray shows OrbGuard's icon, which brings it back.
  static bool closeHides({
    required TargetPlatform platform,
    required bool iconShown,
  }) =>
      runsOn(platform) && iconShown;

  final TargetPlatform platform;
  final TrayHost _tray;
  final WindowHost _window;
  final DateTime Function() _clock;
  final bool Function() _use24h;
  final Brightness Function() _shade;
  final double Function() _scale;

  /// Runs Home's check. Set by the shell.
  VoidCallback? onCheckNow;

  Glance? _glance;
  bool _started = false;

  /// The tray can show an icon, so it is drawn.
  bool _live = false;
  bool _iconShown = false;
  bool _quitting = false;
  bool _disposed = false;
  Timer? _redraw;

  /// What the tray was last given, so nothing is sent twice.
  String? _iconSent;
  String? _tipSent;
  List<TrayItem>? _menuSent;

  /// Draws run one after another, in the order they were asked for.
  Future<void> _drawing = Future<void>.value();

  /// The icon is in the tray, and the close button hides the window.
  bool get iconShown => _iconShown;

  /// Puts the icon in the tray and makes the close button hide the window.
  /// Does nothing where OrbGuard has no tray icon.
  Future<void> start() async {
    if (!runsOn(platform) || _started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _window.listen(onClose: _closeAsked);
    _tray.listen(
      onClick: _open,
      onRightClick: () => unawaited(_popUp()),
      onCommand: _run,
    );
    try {
      await _window.attach();
      if (!await _tray.canShow()) {
        debugPrint('[OrbGuard] No tray to show an icon in; closing the '
            'window quits.');
        return;
      }
      if (_disposed) return;
      _live = true;
      // The icon goes in before its menu: a Linux tray has nowhere to hang
      // a menu until there is an icon.
      await _draw();
      if (_disposed || _iconSent == null) return;
      await _window.keepOnClose(true);
      _iconShown = true;
    } on Object catch (e) {
      debugPrint('[OrbGuard] The tray icon did not go in: $e');
    }
  }

  /// Home says something new.
  void show(Glance glance) {
    if (_disposed || glance == _glance) return;
    _glance = glance;
    _schedule();
    if (_live) unawaited(_draw());
  }

  @override
  void didChangePlatformBrightness() {
    if (_live) unawaited(_draw());
  }

  /// Draws again at the moment the words would stop being true: when the
  /// reading goes stale, and at midnight, when today's time becomes a day.
  void _schedule() {
    _redraw?.cancel();
    final DateTime now = _clock();
    DateTime next = DateUtils.dateOnly(now).add(const Duration(days: 1));
    final DateTime? stale = _glance?.staleAt;
    if (stale != null && stale.isAfter(now) && stale.isBefore(next)) {
      next = stale;
    }
    _redraw = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (_disposed) return;
      _schedule();
      if (_live) unawaited(_draw());
    });
  }

  Future<void> _draw() => _drawing = _drawing.then((_) async {
        if (_disposed || _quitting) return;
        final DateTime now = _clock();
        final bool use24h = _use24h();
        final String icon = TrayIcon.asset(
          TrayIcon.keyFor(_glance),
          platform: platform,
          shade: _shade(),
          scale: _scale(),
        );
        if (icon != _iconSent) {
          await _tray.setIcon(icon);
          _iconSent = icon;
        }
        final String tip = TrayMenu.toolTip(_glance, now: now, use24h: use24h);
        if (tip != _tipSent) {
          await _tray.setToolTip(tip);
          _tipSent = tip;
        }
        final List<TrayItem> menu =
            TrayMenu.of(_glance, now: now, use24h: use24h);
        if (!listEquals(menu, _menuSent)) {
          await _tray.setMenu(menu);
          _menuSent = menu;
        }
      }).catchError((Object e) {
        debugPrint('[OrbGuard] The tray icon was not drawn: $e');
      });

  void _open() {
    if (_disposed || _quitting) return;
    unawaited(_window.bringForward());
  }

  /// A right click: the menu, with its words made true for this moment.
  Future<void> _popUp() async {
    if (!_live || _disposed || _quitting) return;
    await _draw();
    try {
      await _tray.popUpMenu();
    } on Object catch (e) {
      debugPrint('[OrbGuard] The tray menu did not open: $e');
    }
  }

  void _run(TrayCommand command) {
    if (_disposed || _quitting) return;
    switch (command) {
      case TrayCommand.checkNow:
        // The window comes forward first, so the person sees the check run.
        _open();
        onCheckNow?.call();
      case TrayCommand.open:
        _open();
      case TrayCommand.quit:
        unawaited(quit());
    }
  }

  void _closeAsked() {
    if (_quitting || _disposed) return;
    if (closeHides(platform: platform, iconShown: _iconShown)) {
      unawaited(_window.hide());
    }
  }

  /// Takes the icon out and closes the window for good.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    _redraw?.cancel();
    try {
      await _tray.remove();
    } on Object catch (e) {
      debugPrint('[OrbGuard] The tray icon did not come out: $e');
    }
    try {
      await _window.keepOnClose(false);
      await _window.quit();
    } on Object catch (e) {
      debugPrint('[OrbGuard] The window did not close: $e');
    }
  }

  /// The shell is going. The icon goes with it, and the close button closes
  /// again, so a window is never kept by an icon nobody answers.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _redraw?.cancel();
    onCheckNow = null;
    _tray.stopListening();
    _window.stopListening();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    if (_iconShown && !_quitting) {
      _iconShown = false;
      unawaited(_tray.remove().catchError((Object _) {}));
      unawaited(_window.keepOnClose(false).catchError((Object _) {}));
    }
  }

  static bool _platformUse24h() =>
      WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;

  static Brightness _platformShade() =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  static double _platformScale() {
    final Iterable<FlutterView> views =
        WidgetsBinding.instance.platformDispatcher.views;
    return views.isEmpty ? 1 : views.first.devicePixelRatio;
  }
}
