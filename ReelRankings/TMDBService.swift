import Foundation

@MainActor
final class TMDBService {
    private let session = URLSession.shared

    /// Films whose detail page is gone (deleted or merged on TMDB), shared by
    /// every instance so a reload or Retry doesn't request them again.
    private static var missingFilmIDs: Set<Int> = []

    /// From this year on TMDB has revenue for most well-known films.
    private static let mostlyFullRevenueYear = 1939

    // MARK: - Requests

    /// Every request goes through here. TMDB's error replies (rate limit, bad
    /// key, server error) are JSON bodies that can still decode into an
    /// all-optional model, so a non-2xx status has to be turned into a throw.
    private func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TMDBError.badStatus(http.statusCode)
        }
        return data
    }

    private func discover(year: Int, sort: String) async throws -> [MovieResult] {
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/discover/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Config.tmdbAPIKey),
            URLQueryItem(name: "primary_release_year", value: "\(year)"),
            URLQueryItem(name: "sort_by", value: sort),
            URLQueryItem(name: "vote_count.gte", value: "50"),
            URLQueryItem(name: "page", value: "1")
        ]
        let data = try await fetchData(from: components.url!)
        return try JSONDecoder().decode(MovieDiscoverResponse.self, from: data).results
    }

    // MARK: - Box Office

    // Discover sorts by revenue but never returns the figure, and in thin years
    // (most before 1939, some later) TMDB has none for many films. Films with no
    // figure sort last, so if the last film shown has one they all do: one
    // lookup settles most years. Otherwise every candidate is checked and only
    // confirmed figures are ranked, leaving the list shorter than `count`.
    // Lookups go through the persistent film-detail cache (FilmDetailCache.isFresh:
    // a day for this and last year's films, 30 days for older ones).
    func fetchBoxOfficeTop(year: Int, count: Int) async throws -> [Movie] {
        let candidates = Array(try await discover(year: year, sort: "revenue.desc").prefix(count))
        guard let last = candidates.last else { return [] }
        let lastRevenue: Int?
        do {
            lastRevenue = try await fetchRevenue(for: last.id)
        } catch where year >= Self.mostlyFullRevenueYear {
            // Discover's list is usually right from here on, so a failed check
            // shouldn't hide it (thin years still throw, since ranks would shift)
            return candidates.map { Movie($0) }
        }
        if lastRevenue != nil {
            return candidates.map { Movie($0) }
        }

        // Every lookup runs to the end, even after one fails, so the ones that
        // succeeded are cached and a Retry only re-requests what failed.
        var failure: Error?
        let verified: [(MovieResult, Int)] = await withTaskGroup(of: (MovieResult, Result<Int?, Error>).self) { group in
            for candidate in candidates.dropLast() {
                group.addTask { [self] in
                    do {
                        return (candidate, .success(try await fetchRevenue(for: candidate.id)))
                    } catch {
                        return (candidate, .failure(error))
                    }
                }
            }
            var results: [(MovieResult, Int)] = []
            for await (candidate, outcome) in group {
                switch outcome {
                case .success(let revenue?):
                    results.append((candidate, revenue))
                case .success(nil):
                    break
                case .failure(let error):
                    failure = failure ?? error
                }
            }
            return results
        }
        if let failure { throw failure }
        return verified
            .sorted { $0.1 > $1.1 }
            .map { Movie($0.0, revenue: $0.1) }
    }

    /// The film's revenue, or nil when TMDB has no figure for it (including a
    /// film whose detail page is gone). Any other failed request throws, so it
    /// fails the Box Office list rather than silently dropping the film.
    private func fetchRevenue(for movieID: Int) async throws -> Int? {
        try await cachedFilmDetail(id: movieID)?.revenue
    }

    // MARK: - Audience Favorites

    func fetchAudienceTop(year: Int, count: Int) async throws -> [Movie] {
        try await discover(year: year, sort: "vote_count.desc").prefix(count).map { Movie($0) }
    }

    // MARK: - Search

    func searchMovies(query: String) async throws -> [MovieSearchResult] {
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/search/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Config.tmdbAPIKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        let data = try await fetchData(from: components.url!)
        let response = try JSONDecoder().decode(MovieSearchResponse.self, from: data)
        return response.results
    }

    // MARK: - Film Detail

    /// One request per tapped film; `credits` rides along via append_to_response.
    func fetchFilmDetail(id: Int) async throws -> FilmDetail {
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/movie/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Config.tmdbAPIKey),
            URLQueryItem(name: "append_to_response", value: "credits")
        ]
        let data = try await fetchData(from: components.url!)
        let response = try JSONDecoder().decode(FilmDetailResponse.self, from: data)
        return FilmDetail(response: response)
    }

    /// The film's detail from `FilmDetailCache` while fresh, otherwise fetched
    /// and cached; nil when TMDB no longer has the film. If the fetch fails, an
    /// expired entry stands in: it still says whether a film has a revenue
    /// figure and when it was released.
    func cachedFilmDetail(id: Int) async throws -> FilmDetail? {
        let cached = FilmDetailCache.load(id: id)
        if let cached, FilmDetailCache.isFresh(cached) { return cached }
        guard !Self.missingFilmIDs.contains(id) else { return nil }
        do {
            let fresh = try await fetchFilmDetail(id: id)
            FilmDetailCache.save(fresh)
            return fresh
        } catch TMDBError.badStatus(404) {
            Self.missingFilmIDs.insert(id)
            return nil
        } catch {
            if let cached { return cached }
            throw error
        }
    }
}

enum TMDBError: Error {
    case badStatus(Int)
}

// MARK: - Private Decodable types

struct MovieDiscoverResponse: Decodable, Sendable {
    let results: [MovieResult]
}

struct MovieResult: Decodable, Sendable {
    let id: Int
    let title: String
    let revenue: Int?
    let vote_count: Int?
}

private extension Movie {
    init(_ result: MovieResult, revenue: Int? = nil) {
        self.init(id: result.id, title: result.title, revenue: revenue ?? result.revenue ?? 0,
                  voteCount: result.vote_count ?? 0)
    }
}

struct MovieSearchResponse: Decodable, Sendable {
    let results: [MovieSearchResult]
}

struct MovieSearchResult: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let release_date: String?

    // TMDB dates are "YYYY-MM-DD"; nil when a release date isn't known yet.
    var year: Int? {
        guard let release_date, release_date.count >= 4 else { return nil }
        return Int(release_date.prefix(4))
    }
}

struct FilmDetailResponse: Decodable, Sendable {
    struct Genre: Decodable, Sendable { let name: String }
    struct CastMember: Decodable, Sendable { let name: String; let character: String? }
    struct CrewMember: Decodable, Sendable { let name: String; let job: String? }
    struct Credits: Decodable, Sendable {
        let cast: [CastMember]?
        let crew: [CrewMember]?
    }

    let id: Int
    let title: String
    let release_date: String?
    let tagline: String?
    let poster_path: String?
    let backdrop_path: String?
    let runtime: Int?
    let genres: [Genre]?
    let overview: String?
    let budget: Int?
    let revenue: Int?
    let vote_average: Double?
    let vote_count: Int?
    let credits: Credits?
}
