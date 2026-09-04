import SwiftData
import Foundation

@Model
final class UserMovie {
    // CloudKit-backed SwiftData requires a default value on every property
    var tmdbID: Int = 0
    var title: String = ""
    var year: Int = 0
    var isOnWatchlist: Bool = false
    var isSeen: Bool = false
    var userRating: Int = 0  // 0 = unrated, 1–5
    var dateAdded: Date = Date()

    init(tmdbID: Int, title: String, year: Int) {
        self.tmdbID = tmdbID
        self.title = title
        self.year = year
        self.isOnWatchlist = false
        self.isSeen = false
        self.userRating = 0
        self.dateAdded = Date()
    }
}

extension UserMovie {
    /// CloudKit-backed SwiftData can't enforce a unique constraint on tmdbID,
    /// so independent edits on two devices can sync into duplicate records.
    /// Merges each duplicate group into its oldest record and deletes the rest.
    @MainActor
    static func deduplicate(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<UserMovie>()) else { return }
        var didMerge = false
        for (_, records) in Dictionary(grouping: all, by: \.tmdbID) where records.count > 1 {
            let sorted = records.sorted { $0.dateAdded < $1.dateAdded }
            let keeper = sorted[0]
            keeper.isSeen = records.contains { $0.isSeen }
            // Seen and watchlist are mutually exclusive; rating only applies to seen films
            keeper.isOnWatchlist = keeper.isSeen ? false : records.contains { $0.isOnWatchlist }
            keeper.userRating = keeper.isSeen ? (records.map(\.userRating).max() ?? 0) : 0
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
            }
            didMerge = true
        }
        if didMerge { try? context.save() }
    }
}
