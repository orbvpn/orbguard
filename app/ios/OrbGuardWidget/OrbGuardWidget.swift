// OrbGuardWidget.swift - OrbGuard widget extension entry point
//
// Home screen (small, medium) and, on iOS 16+, lock screen (rectangular,
// circular) widgets for the glance. The host app stores the glance in the App
// Group (Runner/GlanceChannelHandler.swift) and asks WidgetKit to reload; this
// provider reads it and plans one entry now, one at staleAt and one at the
// next local midnight. Tapping a widget opens the app (default widget URL).

import SwiftUI
import WidgetKit

struct GlanceEntry: TimelineEntry {
    let date: Date
    let glance: Glance?

    var face: GlanceFace { GlanceLogic.face(for: glance, at: date) }
}

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), glance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(GlanceEntry(date: Date(), glance: GlanceStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date()
        let glance = GlanceStore.load()
        let entries = GlanceLogic.timelineDates(for: glance, now: now).map {
            GlanceEntry(date: $0, glance: glance)
        }
        // With a reading, plan again after the last redraw (the next midnight
        // or staleAt). Without one, nothing changes until the app sends a
        // glance, which reloads every timeline itself.
        completion(Timeline(entries: entries, policy: glance == nil ? .never : .atEnd))
    }
}

struct GlanceWidgetEntryView: View {
    var entry: GlanceEntry
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme

    private var family: GlanceFamily {
        switch widgetFamily {
        case .systemMedium: return .medium
        default:
            if #available(iOS 16, *) {
                if widgetFamily == .accessoryRectangular { return .rectangular }
                if widgetFamily == .accessoryCircular { return .circular }
            }
            return .small
        }
    }

    var body: some View {
        let view = GlanceView(face: entry.face, family: family)
        let background = GlanceBackground(family: family, dark: colorScheme == .dark)
        if #available(iOS 17, *) {
            view.containerBackground(for: .widget) { background }
        } else {
            switch family {
            case .small, .medium: view.padding(16).background(background)
            case .rectangular: view
            case .circular: ZStack { background; view }
            }
        }
    }
}

struct OrbGuardGlanceWidget: Widget {
    let kind = "OrbGuardGlance"

    private var families: [WidgetFamily] {
        if #available(iOS 16, *) {
            return [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular]
        }
        return [.systemSmall, .systemMedium]
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlanceProvider()) { entry in
            GlanceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("OrbGuard")
        .description("Know if you’re being watched.")
        .supportedFamilies(families)
    }
}

@main
struct OrbGuardWidgetBundle: WidgetBundle {
    var body: some Widget {
        OrbGuardGlanceWidget()
    }
}
