// ReelRankingsWidget.swift
// Add this file to the Widget Extension target in Xcode (not the main app target).
// Also add Config.swift to the widget target so it can read appGroupID and tmdbAPIKey.

import WidgetKit
import SwiftUI

// MARK: - Entry

struct TopMovieEntry: TimelineEntry {
    let date: Date
    let title: String
    let year: Int
}

// MARK: - Provider

struct TopMovieProvider: TimelineProvider {
    func placeholder(in context: Context) -> TopMovieEntry {
        TopMovieEntry(date: Date(), title: "Loading…", year: 2024)
    }

    func getSnapshot(in context: Context, completion: @escaping (TopMovieEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopMovieEntry>) -> Void) {
        let current = entry()
        // Refresh once a day
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 24, to: Date())!
        completion(Timeline(entries: [current], policy: .after(nextUpdate)))
    }

    private func entry() -> TopMovieEntry {
        let defaults = UserDefaults(suiteName: Config.appGroupID)
        let title = defaults?.string(forKey: "widgetTopMovieTitle") ?? "Open ReelRankings"
        let year = defaults?.integer(forKey: "widgetTopMovieYear") ?? Calendar.current.component(.year, from: Date()) - 1
        return TopMovieEntry(date: Date(), title: title, year: year)
    }
}

// MARK: - Widget View

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct ReelRankingsWidgetView: View {
    let entry: TopMovieEntry

    var body: some View {
        ZStack {
            Color(white: 0.07)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.caption2)
                        .foregroundStyle(gold)
                    Text("NO. 1 BOX OFFICE")
                        .font(.caption2.bold())
                        .foregroundStyle(gold)
                        .tracking(0.5)
                }

                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)

                Spacer()

                Text(String(entry.year))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Widget Definition

struct ReelRankingsWidget: Widget {
    let kind = "ReelRankingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TopMovieProvider()) { entry in
            ReelRankingsWidgetView(entry: entry)
                .containerBackground(Color(white: 0.07), for: .widget)
        }
        .configurationDisplayName("Top Box Office")
        .description("Shows the #1 box office film for the selected year.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle
// NOTE: Move this file to the Widget Extension target when you create it in Xcode.
// The @main WidgetBundle below is commented out to avoid conflicting with ReelRankingsApp's @main.
// Uncomment it once this file is in its own widget target.

// @main
// struct ReelRankingsWidgetBundle: WidgetBundle {
//     var body: some Widget {
//         ReelRankingsWidget()
//     }
// }
