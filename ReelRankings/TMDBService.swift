import Foundation

@MainActor
final class TMDBService {
    // iOS's default URLSession caps concurrent connections per host low enough that
    // the verified-revenue lookups (up to ~20 in parallel) end up queuing in small
    // batches on a real network. Raise the cap so they actually run concurrently.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 16
        return URLSession(configuration: config)
    }()

    // Cache TMDB ID → IMDB ID so switching years doesn't re-fetch known IDs
    private var imdbIDCache: [Int: String] = [:]
    // Cache TMDB ID → verified revenue (pre-1939 years only)
    private var revenueCache: [Int: Int] = [:]

    // Before this year, TMDB's discover sort trusts revenue.desc but the list endpoint
    // never returns the actual revenue figure, and most catalog entries have none at all.
    // Below this cutoff we verify each candidate's real revenue via the detail endpoint
    // and only rank the ones we can confirm.
    private static let verifiedRevenueCutoffYear = 1939

    // MARK: - Box Office

    func fetchBoxOfficeTop(year: Int, count: Int) async throws -> [Movie] {
        if year < Self.verifiedRevenueCutoffYear {
            return try await fetchVerifiedBoxOfficeTop(year: year, count: count)
        }
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/discover/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Config.tmdbAPIKey),
            URLQueryItem(name: "primary_release_year", value: "\(year)"),
            URLQueryItem(name: "sort_by", value: "revenue.desc"),
            URLQueryItem(name: "vote_count.gte", value: "50"),
            URLQueryItem(name: "page", value: "1")
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(MovieDiscoverResponse.self, from: data)
        return Array(response.results.prefix(count)).map {
            Movie(id: $0.id, title: $0.title, revenue: $0.revenue ?? 0, voteCount: $0.vote_count ?? 0, imdbID: nil)
        }
    }

    // TMDB's revenue data gets sparse before 1939. Rather than rank movies with no known
    // revenue, this pulls candidates a page at a time (discover already sorts by
    // revenue.desc, so real numbers cluster up front), verifies each one's real figure via
    // the detail endpoint, and returns only the confirmed ones — shorter than `count` when
    // a year doesn't have enough reliable data. A second page is only fetched if the first
    // didn't turn up enough, since most years don't need it.
    private func fetchVerifiedBoxOfficeTop(year: Int, count: Int) async throws -> [Movie] {
        var verifiedByID: [Int: (MovieResult, Int)] = [:]
        for page in 1...2 {
            let candidates = try await fetchRevenueDiscoverPage(year: year, page: page)
            if candidates.isEmpty { break }

            let pageVerified: [(MovieResult, Int)] = await withTaskGroup(of: (MovieResult, Int?).self) { group in
                for candidate in candidates {
                    group.addTask { [self] in
                        (candidate, await fetchRevenue(for: candidate.id))
                    }
                }
                var results: [(MovieResult, Int)] = []
                for await (candidate, revenue) in group {
                    if let revenue, revenue > 0 {
                        results.append((candidate, revenue))
                    }
                }
                return results
            }
            for (candidate, revenue) in pageVerified {
                verifiedByID[candidate.id] = (candidate, revenue)
            }

            // Discover pages are 20 results; a short page means there's nothing more to fetch.
            if verifiedByID.count >= count || candidates.count < 20 { break }
        }

        return verifiedByID.values
            .sorted { $0.1 > $1.1 }
            .prefix(count)
            .map { Movie(id: $0.0.id, title: $0.0.title, revenue: $0.1, voteCount: $0.0.vote_count ?? 0, imdbID: nil) }
    }

    private func fetchRevenueDiscoverPage(year: Int, page: Int) async throws -> [MovieResult] {
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/discover/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Config.tmdbAPIKey),
            URLQueryItem(name: "primary_release_year", value: "\(year)"),
            URLQueryItem(name: "sort_by", value: "revenue.desc"),
            URLQueryItem(name: "vote_count.gte", value: "50"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        let (data, _) = try await session.data(from: components.url!)
        return try JSONDecoder().decode(MovieDiscoverResponse.self, from: data).results
    }

    private func fetchRevenue(for movieID: Int) async -> Int? {
        if let cached = revenueCache[movieID] {
            return cached
        }
        let urlString = "\(Config.tmdbBaseURL)/movie/\(movieID)?api_key=\(Config.tmdbAPIKey)"
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let detail = try JSONDecoder().decode(MovieDetailResponse.self, from: data)
            if let revenue = detail.revenue, revenue > 0 {
                revenueCache[movieID] = revenue
            }
            return detail.revenue
        } catch {
            return nil
        }
    }

    // MARK: - Audience Favorites

    func fetchAudienceTop(year: Int, count: Int) async throws -> [Movie] {
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/discover/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Config.tmdbAPIKey),
            URLQueryItem(name: "primary_release_year", value: "\(year)"),
            URLQueryItem(name: "sort_by", value: "vote_count.desc"),
            URLQueryItem(name: "vote_count.gte", value: "50"),
            URLQueryItem(name: "page", value: "1")
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(MovieDiscoverResponse.self, from: data)
        return Array(response.results.prefix(count)).map {
            Movie(id: $0.id, title: $0.title, revenue: $0.revenue ?? 0, voteCount: $0.vote_count ?? 0, imdbID: nil)
        }
    }

    // MARK: - Search

    func searchMovies(query: String) async throws -> [MovieSearchResult] {
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/search/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Config.tmdbAPIKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(MovieSearchResponse.self, from: data)
        return response.results
    }

    // MARK: - IMDB ID Lookup (single, with cache)

    func fetchIMDBID(for movieID: Int) async -> (Int, String?) {
        if let cached = imdbIDCache[movieID] {
            return (movieID, cached)
        }
        let urlString = "\(Config.tmdbBaseURL)/movie/\(movieID)/external_ids?api_key=\(Config.tmdbAPIKey)"
        guard let url = URL(string: urlString) else { return (movieID, nil) }
        do {
            let (data, _) = try await session.data(from: url)
            let ext = try JSONDecoder().decode(ExternalIDsResponse.self, from: data)
            if let imdbID = ext.imdb_id {
                imdbIDCache[movieID] = imdbID
            }
            return (movieID, ext.imdb_id)
        } catch {
            return (movieID, nil)
        }
    }
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

struct ExternalIDsResponse: Decodable, Sendable {
    let imdb_id: String?
}

struct MovieDetailResponse: Decodable, Sendable {
    let revenue: Int?
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
