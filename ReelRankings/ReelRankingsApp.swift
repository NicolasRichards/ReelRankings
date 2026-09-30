import SwiftUI
import SwiftData

@main
struct ReelRankingsApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let sharedModelContainer: ModelContainer
    /// The saved-films store couldn't be opened, so this session runs on a
    /// temporary in-memory store instead.
    @State private var showingTemporaryStoreAlert: Bool

    init() {
        let schema = Schema([UserMovie.self])
        do {
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            sharedModelContainer = try ModelContainer(for: schema, configurations: [configuration])
            _showingTemporaryStoreAlert = State(initialValue: false)
        } catch {
            // Crashing here would repeat on every launch (say, the device is
            // out of storage), so run on a store that lasts only this session.
            let temporary = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [temporary])
            } catch {
                fatalError("Could not create even an in-memory ModelContainer: \(error)")
            }
            _showingTemporaryStoreAlert = State(initialValue: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await TipJar.shared.listenForTransactions() }
                .task {
                    await Task.detached(priority: .background) { FilmDetailCache.pruneExpired() }.value
                }
                .alert("Your Films Can't Be Saved", isPresented: $showingTemporaryStoreAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("ReelRankings couldn't open its storage, so anything you mark or rate won't be kept after you close the app. Your device may be out of storage.")
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                UserMovie.deduplicate(in: sharedModelContainer.mainContext)
            }
        }
    }
}
