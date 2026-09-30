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
    // Unmarking Seen keeps the rating stored (every view hides it unless the
    // film is seen), so an accidental tap on a list checkmark is undone by
    // tapping again rather than silently losing the rating.
    func setSeen(_ seen: Bool) {
        isSeen = seen
        if seen { isOnWatchlist = false }
    }

    func setRating(_ rating: Int) {
        userRating = rating
        if rating > 0 { setSeen(true) }
    }

    func setOnWatchlist(_ onWatchlist: Bool) {
        isOnWatchlist = onWatchlist
        if onWatchlist { isSeen = false }
    }

    /// Applies `change` to the film's record, creating it first if needed, and
    /// deletes the record instead if the change left nothing worth keeping.
    /// Every synced duplicate gets the same change: editing only one would let
    /// `deduplicate` merge a stale value (say, Seen) back in on next launch.
    /// Returns false if the change couldn't be saved; it has been rolled back.
    @MainActor @discardableResult
    static func update(_ movie: Movie, year: Int, in context: ModelContext, _ change: (UserMovie) -> Void) -> Bool {
        update(tmdbID: movie.id, title: movie.title, year: year, in: context, change)
    }

    /// `deletingIfEmpty: false` is for a screen that still shows the record
    /// after the change, and would otherwise be left holding a deleted model.
    @MainActor @discardableResult
    static func update(tmdbID: Int, title: String, year: Int, in context: ModelContext,
                       deletingIfEmpty: Bool = true, _ change: (UserMovie) -> Void) -> Bool {
        var records = allRecords(for: tmdbID, in: context)
        if records.isEmpty {
            let record = UserMovie(tmdbID: tmdbID, title: title, year: year)
            context.insert(record)
            records = [record]
        }
        for record in records {
            change(record)
            if deletingIfEmpty && !record.isSeen && !record.isOnWatchlist && record.userRating == 0 {
                context.delete(record)
            }
        }
        return save(context)
    }

    /// Removes the film and every synced duplicate of it, so it can't
    /// reappear from a copy the user never saw.
    @MainActor @discardableResult
    static func removeAll(tmdbID: Int, in context: ModelContext) -> Bool {
        for record in allRecords(for: tmdbID, in: context) {
            context.delete(record)
        }
        return save(context)
    }

    /// A failed save (say, the device is out of storage) is rolled back, so
    /// the screen shows what is actually stored instead of a change that
    /// would vanish on the next launch.
    @MainActor
    private static func save(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    @MainActor
    private static func allRecords(for tmdbID: Int, in context: ModelContext) -> [UserMovie] {
        (try? context.fetch(FetchDescriptor<UserMovie>(predicate: #Predicate { $0.tmdbID == tmdbID }))) ?? []
    }

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
        if didMerge { _ = save(context) }
    }
}

extension Sequence where Element == UserMovie {
    /// One record per film even before `deduplicate` has healed a synced
    /// duplicate — the oldest, the same one `deduplicate` keeps.
    var canonicalByTMDBID: [Int: UserMovie] {
        Dictionary(grouping: self, by: \.tmdbID).compactMapValues { records in
            records.min { $0.dateAdded < $1.dateAdded }
        }
    }
}
