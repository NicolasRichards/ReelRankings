import Foundation

/// The fields the detail screen shows, trimmed from TMDB's ~38 KB movie
/// response. Empty strings and zero values are normalized to nil here so the
/// view can hide a row by checking for nil alone.
struct FilmDetail: Codable, Sendable {
    struct CastMember: Codable, Sendable, Hashable {
        let name: String
        let character: String?
    }

    let id: Int
    let title: String
    let releaseYear: Int?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let runtimeMinutes: Int?
    let genres: [String]
    let overview: String?
    let directors: [String]
    let cast: [CastMember]
    let budget: Int?
    let revenue: Int?
    let voteAverage: Double?
    let fetchedAt: Date

    init(response r: FilmDetailResponse, fetchedAt: Date = Date()) {
        id = r.id
        title = r.title
        releaseYear = r.release_date.flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil }
        tagline = r.tagline.nonEmpty
        posterPath = r.poster_path.nonEmpty
        backdropPath = r.backdrop_path.nonEmpty
        runtimeMinutes = r.runtime.positive
        genres = (r.genres ?? []).map(\.name)
        overview = r.overview.nonEmpty
        var seenDirectors = Set<String>()
        directors = (r.credits?.crew ?? [])
            .filter { $0.job == "Director" }
            .map(\.name)
            .filter { seenDirectors.insert($0).inserted }
        cast = (r.credits?.cast ?? []).prefix(6).map {
            CastMember(name: $0.name, character: $0.character.nonEmpty)
        }
        budget = r.budget.positive
        revenue = r.revenue.positive
        // TMDB reports 0.0 for films nobody has rated yet
        voteAverage = (r.vote_count ?? 0) > 0 ? r.vote_average.flatMap { $0 > 0 ? $0 : nil } : nil
        self.fetchedAt = fetchedAt
    }

    func posterURL(width: String = "w342") -> URL? {
        posterPath.flatMap { URL(string: "\(Config.tmdbImageBaseURL)/\(width)\($0)") }
    }

    func backdropURL(width: String = "w780") -> URL? {
        backdropPath.flatMap { URL(string: "\(Config.tmdbImageBaseURL)/\(width)\($0)") }
    }

    /// "2h 14m", "45m", or "2h"
    var formattedRuntime: String? {
        guard let runtimeMinutes else { return nil }
        let hours = runtimeMinutes / 60
        let minutes = runtimeMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)m"
        }
    }

    /// Always US formatting: the "$… million" wording is English, and a
    /// device locale would otherwise give "$1,5 million" or "609.000 $".
    static func formattedDollars(_ amount: Int) -> String {
        let us = Locale(identifier: "en_US")
        let millions = Double(amount) / 1_000_000
        // Decided on the rounded figure, so $999.96M reads "$1 billion", not "$1,000 million"
        if (millions * 10).rounded() / 10 >= 1000 {
            return "$" + (millions / 1000).formatted(.number.precision(.fractionLength(0...2)).locale(us)) + " billion"
        }
        if amount >= 1_000_000 {
            return "$" + millions.formatted(.number.precision(.fractionLength(0...1)).locale(us)) + " million"
        }
        return amount.formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(us))
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private extension Optional where Wrapped == Int {
    var positive: Int? {
        guard let self, self > 0 else { return nil }
        return self
    }
}

/// One small JSON file per film in Caches/FilmDetails. Caches is the right
/// home: the OS may purge it under storage pressure, and every entry can be
/// refetched on the next tap.
enum FilmDetailCache {
    nonisolated static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    nonisolated private static var directory: URL {
        URL.cachesDirectory.appending(path: "FilmDetails", directoryHint: .isDirectory)
    }

    private static func fileURL(for id: Int) -> URL {
        directory.appending(path: "\(id).json")
    }

    /// Returns the entry whatever its age; callers check `isFresh` so an
    /// expired entry can still stand in while offline.
    static func load(id: Int) -> FilmDetail? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(FilmDetail.self, from: data)
    }

    static func save(_ detail: FilmDetail) {
        guard let data = try? JSONEncoder().encode(detail) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: detail.id), options: .atomic)
    }

    /// A film released this year or last may still be in theaters, so its box
    /// office figure goes stale within days; an older film's details don't.
    static func isFresh(_ detail: FilmDetail) -> Bool {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let isRecent = (detail.releaseYear ?? currentYear) >= currentYear - 1
        let limit: TimeInterval = isRecent ? 24 * 60 * 60 : maxAge
        return Date().timeIntervalSince(detail.fetchedAt) < limit
    }

    /// Deletes entries older than `maxAge`. An entry otherwise only gets
    /// replaced when its film is opened again, so files for films viewed once
    /// would stay forever.
    nonisolated static func pruneExpired() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, Date().timeIntervalSince(modified) > maxAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
