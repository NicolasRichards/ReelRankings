import SwiftUI
import SwiftData

@main
struct ReelRankingsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: UserMovie.self)
    }
}
