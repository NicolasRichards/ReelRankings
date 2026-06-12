import SwiftUI
import SwiftData

@main
struct ReelRankingsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([UserMovie.self])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
