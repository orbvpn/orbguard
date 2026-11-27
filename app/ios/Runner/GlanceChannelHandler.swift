// GlanceChannelHandler.swift - OrbGuard iOS
// Hosts the com.orb.guard/glance method channel.
//
// Purpose: the Dart side works out the glance (what the widgets show of Home)
// and sends it with `update(map)` whenever something shown changes. This
// handler stores the map as JSON in the shared App Group
// (UserDefaults suite group.com.orb.guard.shared, key glance.v1), where the
// OrbGuardWidget extension reads it, and asks WidgetKit to redraw every widget.
//
// The map is stored as given. The widget draws it and adds only the check
// time; it never invents a state.

import Flutter
import Foundation
import WidgetKit
import os.log

final class GlanceChannelHandler {

    static let channelName = "com.orb.guard/glance"
    // Must match GlanceStore in OrbGuardWidget/GlanceLogic.swift.
    static let suiteName = "group.com.orb.guard.shared"
    static let key = "glance.v1"

    private let logger = Logger(subsystem: "com.orb.guard", category: "Glance")

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "update":
            update(call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func update(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let map = arguments as? [String: Any],
              JSONSerialization.isValidJSONObject(map),
              let data = try? JSONSerialization.data(withJSONObject: map) else {
            result(FlutterError(code: "BAD_ARGS",
                                message: "update expects the glance map",
                                details: nil))
            return
        }
        guard let defaults = UserDefaults(suiteName: Self.suiteName) else {
            result(FlutterError(code: "APP_GROUP_UNAVAILABLE",
                                message: "The shared App Group \(Self.suiteName) is not available to this build.",
                                details: nil))
            return
        }
        defaults.set(data, forKey: Self.key)
        WidgetCenter.shared.reloadAllTimelines()
        logger.debug("glance stored (\(data.count) bytes), widgets reloading")
        result(nil)
    }
}
