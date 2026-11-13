import SwiftUI
import WidgetKit

@main
struct OdeSearchWidget: Widget {
    // MARK: - Types

    struct Entry: TimelineEntry {
        let date: Date
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: .distantPast)
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: .distantPast))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .distantPast)], policy: .never))
        }
    }

    // MARK: - Variables

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OdeSearch", provider: Provider()) { _ in
            OdeSearchWidgetView()
                .widgetURL(BrowserCommandLink.newQuery.url)
        }
        .configurationDisplayName("Ode Search")
        .description("Open a fresh search in Ode.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

#if DEBUG
    #Preview("Search", as: .systemSmall) {
        OdeSearchWidget()
    } timeline: {
        OdeSearchWidget.Entry(date: .distantPast)
    }

    #Preview("Lock Screen", as: .accessoryCircular) {
        OdeSearchWidget()
    } timeline: {
        OdeSearchWidget.Entry(date: .distantPast)
    }
#endif
