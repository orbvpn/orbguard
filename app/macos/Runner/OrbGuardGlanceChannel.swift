// OrbGuardGlanceChannel.swift - com.orb.guard/glance for macOS
//
// The menu bar side of the glance: an NSStatusItem whose image is the ring
// (whole when all clear, cut with an amber spark at each gap, dots when never
// checked, greyed when nothing is on watch, the logo mark before any glance)
// and a transient popover with the headline, the proof, two Today rows, one
// lime "Check now" and a quiet "Open OrbGuard". A right click (or a control
// click) opens a menu instead: the status line, Check now, Open OrbGuard and
// Quit OrbGuard, the same menu the Windows and Linux tray icon has
// (lib/services/desktop/desktop_tray.dart). Closing the window only hides it,
// so this is how OrbGuard is brought back or quit.
//
// Contract (standard method codec):
//   Dart -> native  update(map)  store the map, redraw. Replies nil.
//   native -> Dart  refresh      the current map, or nil when there is no reading yet.
//                                Called each time the popover opens.
//   native -> Dart  checkNow     the person pressed Check now in the popover.
//
// Honesty: the native side draws what it was given. Before the first update ever
// it shows only the mark and "Open OrbGuard". After staleAt the score is not shown.

import AppKit
import FlutterMacOS
import SwiftUI

enum OrbGuardGlanceChannel {

  static let name = "com.orb.guard/glance"

  static func register(messenger: FlutterBinaryMessenger, window: NSWindow) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    let glance = OrbGuardGlance.shared
    glance.attach(channel: channel, window: window)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "update":
        guard let map = call.arguments as? [String: Any], let parsed = Glance(map: map) else {
          result(FlutterError(
            code: "BAD_ARGS",
            message: "update expects the glance map (moment, title and ring are required).",
            details: ["platform": "macos"]))
          return
        }
        glance.apply(parsed)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Owns the status item, the popover and the last glance. One per app.
final class OrbGuardGlance: NSObject, NSPopoverDelegate {

  static let shared = OrbGuardGlance()

  private static let storeKey = "orbguard.glance.v1"

  private var channel: FlutterMethodChannel?
  private weak var window: NSWindow?
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private let model = GlancePopoverModel()
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []

  /// The last glance Dart sent (kept across launches), or nil before the first ever.
  private(set) var glance: Glance?

  private override init() {
    super.init()
    glance = Self.load()
  }

  func attach(channel: FlutterMethodChannel, window: NSWindow) {
    self.channel = channel
    self.window = window
    installStatusItem()
    redraw()

    // Keep "today" and staleAt true after sleep or a clock change.
    let nc = NSWorkspace.shared.notificationCenter
    observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.redraw() })
    observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in self?.redraw() })
    observers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in self?.redraw() })
  }

  // MARK: Updates

  func apply(_ new: Glance) {
    glance = new
    Self.save(new)
    redraw()
  }

  private func redraw() {
    let now = Date()
    if let button = statusItem?.button {
      button.image = GlanceRingPainter.statusImage(mode: glance?.ringMode ?? .logo)
      let words = statusLine(at: now) ?? "Open OrbGuard"
      button.toolTip = words
      button.setAccessibilityLabel("OrbGuard. " + words)
    }
    model.glance = glance
    model.now = now
    schedule(after: now)
  }

  /// Home's words for now: the title (its stale title once stale) and when the
  /// check ran. Nil before the first glance ever.
  private func statusLine(at now: Date) -> String? {
    guard let g = glance else { return nil }
    let title = g.shownTitle(at: now)
    return g.checkedAt.map { title + ". " + GlanceTime.checked($0, now: now) } ?? title
  }

  /// Redraw at staleAt (the score goes) and at the next local midnight (today's times
  /// become dates).
  private func schedule(after now: Date) {
    timer?.invalidate()
    var next = GlanceTime.nextMidnight(after: now)
    if let stale = glance?.staleAt, stale > now, stale < next { next = stale }
    let t = Timer(fire: next.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in self?.redraw() }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  // MARK: Status item and popover

  private func installStatusItem() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.imagePosition = .imageOnly
    item.button?.target = self
    item.button?.action = #selector(clicked(_:))
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusItem = item

    let view = GlancePopoverView(
      model: model,
      onCheckNow: { [weak self] in self?.checkNow() },
      onOpen: { [weak self] in self?.openApp() })
    let host = NSHostingController(rootView: view)
    host.sizingOptions = .preferredContentSize
    popover.contentViewController = host
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
    if #available(macOS 14.0, *) {
      // Let the bed colour reach under the popover's arrow too.
      popover.hasFullSizeContent = true
    }
  }

  /// A left click opens the popover; a right or control click, the menu.
  @objc private func clicked(_ sender: Any?) {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
      showMenu()
    } else {
      togglePopover(sender)
    }
  }

  /// The status line, Check now, Open OrbGuard and Quit OrbGuard. Before the
  /// first glance ever there is nothing to say and no check to start here.
  private func showMenu() {
    if popover.isShown { popover.performClose(nil) }
    guard let item = statusItem else { return }
    let menu = NSMenu()
    menu.autoenablesItems = false
    func command(_ title: String, _ action: Selector) -> NSMenuItem {
      let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
      row.target = self
      return row
    }
    if let words = statusLine(at: Date()) {
      let line = NSMenuItem(title: words, action: nil, keyEquivalent: "")
      line.isEnabled = false
      menu.addItem(line)
      menu.addItem(.separator())
      menu.addItem(command("Check now", #selector(menuCheckNow)))
    }
    menu.addItem(command("Open OrbGuard", #selector(menuOpen)))
    menu.addItem(.separator())
    menu.addItem(command("Quit OrbGuard", #selector(menuQuit)))
    // Hung on the item only while it is open, so a left click still opens
    // the popover.
    item.menu = menu
    item.button?.performClick(nil)
    item.menu = nil
  }

  @objc private func menuCheckNow() { checkNow() }
  @objc private func menuOpen() { openApp() }
  @objc private func menuQuit() { NSApp.terminate(nil) }

  @objc private func togglePopover(_ sender: Any?) {
    if popover.isShown {
      popover.performClose(sender)
      return
    }
    guard let button = statusItem?.button else { return }
    model.glance = glance
    model.now = Date()
    // Dark or light by the system appearance, not the menu bar's tint.
    popover.appearance = NSApp.effectiveAppearance
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    refresh()
  }

  /// Ask Dart for the current map so the popover's times are fresh. Falls back to
  /// the last update when Dart has no reading or does not answer.
  private func refresh() {
    channel?.invokeMethod("refresh", arguments: nil) { [weak self] reply in
      guard let self else { return }
      if let map = reply as? [String: Any], let fresh = Glance(map: map) {
        self.apply(fresh)
      } else {
        self.model.now = Date()
      }
    }
  }

  private func checkNow() {
    popover.performClose(nil)
    openApp()
    channel?.invokeMethod("checkNow", arguments: nil)
  }

  /// Brings the window back, whether it was hidden by closing it or
  /// minimised.
  private func openApp() {
    popover.performClose(nil)
    if let main = window as? MainFlutterWindow {
      main.bringBack()
      return
    }
    NSApp.activate(ignoringOtherApps: true)
    guard let window else { return }
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
  }

  // MARK: Store (the map as JSON)

  private static func load() -> Glance? {
    guard let data = UserDefaults.standard.data(forKey: storeKey),
      let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    return Glance(map: map)
  }

  private static func save(_ glance: Glance) {
    guard JSONSerialization.isValidJSONObject(glance.jsonMap),
      let data = try? JSONSerialization.data(withJSONObject: glance.jsonMap)
    else { return }
    UserDefaults.standard.set(data, forKey: storeKey)
  }
}
