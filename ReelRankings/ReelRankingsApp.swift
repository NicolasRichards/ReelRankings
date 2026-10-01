import SwiftUI
import SwiftData
import os

@main
struct ReelRankingsApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var container: ModelContainer
    /// The saved-films store couldn't be opened, so the app is running on a
    /// temporary in-memory store until it can.
    @State private var usingTemporaryStore: Bool
    @State private var showingTemporaryStoreAlert = false
    /// Retry opening the store only on launch and after a real trip to the
    /// background: a Control Center pull is also inactive -> active, and
    /// retrying (and re-warning) on each of those helps nobody.
    @State private var shouldRetryStore = true

    private static let schema = Schema([UserMovie.self])
    private static let log = Logger(subsystem: "NickRichards.ReelRankings", category: "storage")

    init() {
        do {
            _container = State(initialValue: try Self.makePersistentContainer())
            _usingTemporaryStore = State(initialValue: false)
        } catch {
            // Crashing here would repeat on every launch (say, the device is out
            // of storage), so start on a temporary store; see the retry below.
            Self.log.error("Saved-films store failed to open: \(String(describing: error), privacy: .public)")
            _container = State(initialValue: Self.makeTemporaryContainer())
            _usingTemporaryStore = State(initialValue: true)
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
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { shouldRetryStore = true }
            guard phase == .active else { return }
            if usingTemporaryStore && shouldRetryStore {
                shouldRetryStore = false
                reopenPersistentStore()
            }
            UserMovie.deduplicate(in: container.mainContext)
            Task { await UserMovie.repairOutOfRangeYears(in: container.mainContext) }
        }
    }

    /// A launch in the background (an iCloud push before the device is first
    /// unlocked) can fail to open a store that's fine, so each time the app
    /// comes to the front it tries again, and only warns if it still can't.
    private func reopenPersistentStore() {
        do {
            let persistent = try Self.makePersistentContainer()
            // Carry over anything marked while on the temporary store; the
            // merge pass that follows folds in any copies that already exist
            UserMovie.copyAll(from: container.mainContext, to: persistent.mainContext)
            container = persistent
            usingTemporaryStore = false
        } catch {
            Self.log.error("Saved-films store still failed to open: \(String(describing: error), privacy: .public)")
            showingTemporaryStoreAlert = true
        }
    }

    private static func makePersistentContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makeTemporaryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create even an in-memory ModelContainer: \(error)")
        }
    }
}
