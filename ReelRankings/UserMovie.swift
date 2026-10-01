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
    /// Returns false if the change couldn't be made or saved; a failed save
    /// has been rolled back.
    @MainActor
    static func update(_ movie: Movie, year: Int, in context: ModelContext, _ change: (UserMovie) -> Void) -> Bool {
        update(tmdbID: movie.id, title: movie.title, year: year, in: context, change)
    }

    /// `creatingIfMissing: false` is for a screen editing a film that already
    /// exists: if it was deleted meanwhile, nothing is re-created from stale
    /// values. `deletingIfEmpty: false` keeps a record the screen is still
    /// showing, so the user can toggle a change straight back.
    @MainActor
    static func update(tmdbID: Int, title: String, year: Int, in context: ModelContext,
                       creatingIfMissing: Bool = true, deletingIfEmpty: Bool = true,
                       _ change: (UserMovie) -> Void) -> Bool {
        // A failed lookup must not look like "no records yet", which would
        // insert a duplicate instead of editing the existing one
        guard var records = try? allRecords(for: tmdbID, in: context) else { return false }
        if records.isEmpty {
            guard creatingIfMissing else { return true }
            let record = UserMovie(tmdbID: tmdbID, title: title, year: year)
            context.insert(record)
            records = [record]
        }
        for record in records {
            change(record)
            if deletingIfEmpty && record.isEmpty {
                context.delete(record)
            }
        }
        return save(context)
    }

    /// Removes the film and every synced duplicate of it, so it can't
    /// reappear from a copy the user never saw. Returns false if the records
    /// couldn't be looked up or the deletion couldn't be saved.
    @MainActor
    static func removeAll(tmdbID: Int, in context: ModelContext) -> Bool {
        guard let records = try? allRecords(for: tmdbID, in: context) else { return false }
        for record in records {
            context.delete(record)
        }
        return save(context)
    }

    /// Tries twice, since a save can briefly collide with an iCloud import.
    /// If both fail the change is rolled back, so the screen shows what is
    /// actually stored instead of a change that would vanish on relaunch.
    @MainActor
    private static func save(_ context: ModelContext) -> Bool {
        if (try? context.save()) != nil { return true }
        if (try? context.save()) != nil { return true }
        context.rollback()
        return false
    }

    @MainActor
    private static func allRecords(for tmdbID: Int, in context: ModelContext) throws -> [UserMovie] {
        try context.fetch(FetchDescriptor<UserMovie>(predicate: #Predicate { $0.tmdbID == tmdbID }))
    }

    /// CloudKit-backed SwiftData can't enforce a unique constraint on tmdbID,
    /// so independent edits on two devices can sync into duplicate records.
    /// Merges each duplicate group into its oldest record and deletes the rest,
    /// then deletes records with nothing left in them (the My Films sheet keeps
    /// an emptied record while it's open; older builds left them behind).
    @MainActor
    static func deduplicate(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<UserMovie>()) else { return }
        var changed = false
        for (_, records) in Dictionary(grouping: all, by: \.tmdbID) where records.count > 1 {
            let sorted = records.sorted { $0.dateAdded < $1.dateAdded }
            let keeper = sorted[0]
            keeper.isSeen = records.contains { $0.isSeen }
            // Seen and watchlist are mutually exclusive
            keeper.isOnWatchlist = keeper.isSeen ? false : records.contains { $0.isOnWatchlist }
            // A seen film takes its rating from the seen copies. An unseen one
            // keeps the hidden rating, so marking it seen again brings it back
            // (the same promise setSeen makes).
            let candidates = keeper.isSeen ? records.filter(\.isSeen) : records
            keeper.userRating = candidates.map(\.userRating).max() ?? 0
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
            }
            changed = true
        }
        for record in all where !record.isDeleted && record.isEmpty {
            context.delete(record)
            changed = true
        }
        if changed { _ = save(context) }
    }

    var isEmpty: Bool { !isSeen && !isOnWatchlist && userRating == 0 }

    /// For a screen that kept an emptied record while open: deletes the
    /// film's records if nothing is left in them.
    @MainActor
    static func removeIfEmpty(tmdbID: Int, in context: ModelContext) {
        guard let records = try? allRecords(for: tmdbID, in: context) else { return }
        let empty = records.filter(\.isEmpty)
        guard !empty.isEmpty else { return }
        empty.forEach(context.delete)
        _ = save(context)
    }

    /// Copies every record into another store, keeping their dates.
    @MainActor
    static func copyAll(from source: ModelContext, to destination: ModelContext) {
        guard let records = try? source.fetch(FetchDescriptor<UserMovie>()), !records.isEmpty else { return }
        for record in records {
            let copy = UserMovie(tmdbID: record.tmdbID, title: record.title, year: record.year)
            copy.isSeen = record.isSeen
            copy.isOnWatchlist = record.isOnWatchlist
            copy.userRating = record.userRating
            copy.dateAdded = record.dateAdded
            destination.insert(copy)
        }
        _ = save(destination)
    }
}

extension UserMovie {
    @MainActor private static var isRepairingYears = false

    /// Builds before 1.5 (10) took the year from the phone's calendar, so a
    /// Buddhist-calendar user browsing "2568" (which showed TMDB's all-time
    /// lists) saved films under that year. The saved year can't be converted,
    /// since it's the year that was browsed rather than the film's own, so
    /// each such film's release year is looked up. Anything left unfixed
    /// (offline, TMDB error) is retried the next time the app comes forward.
    @MainActor
    static func repairOutOfRangeYears(in context: ModelContext) async {
        guard !isRepairingYears else { return }
        isRepairingYears = true
        defer { isRepairingYears = false }

        // Only years no film can have: a real release year before 1929 (a film
        // marked from those all-time lists) is correct and mustn't be re-fetched
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let valid = 1870...currentYear
        guard let all = try? context.fetch(FetchDescriptor<UserMovie>()) else { return }
        let broken = all.filter { !valid.contains($0.year) }
        guard !broken.isEmpty else { return }

        let service = TMDBService()
        for tmdbID in Set(broken.map(\.tmdbID)) {
            guard let year = try? await service.fetchReleaseYear(id: tmdbID) else { continue }
            // Re-read after the await: sync or an edit may have changed the records
            for record in (try? context.fetch(FetchDescriptor<UserMovie>(predicate: #Predicate { $0.tmdbID == tmdbID }))) ?? []
            where !valid.contains(record.year) {
                record.year = year
            }
        }
        _ = save(context)
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
