import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Closing the window keeps OrbGuard running: the window hides
  /// (MainFlutterWindow.performClose) and the menu bar ring stays. Quit OrbGuard
  /// (the ring's menu, the app menu or the Dock) really quits.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// A click on the Dock icon brings the hidden window back.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag, let window = mainFlutterWindow as? MainFlutterWindow {
      window.bringBack()
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
