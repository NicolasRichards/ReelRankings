import Foundation

@MainActor
final class TMDBService {
    private let session = URLSession.shared

    // Cache TMDB ID → verified revenue (pre-1939 years only). 0 records "no
    // figure", so a reload or Retry doesn't request those films again.
    private var revenueCache: [Int: Int] = [:]

    // Before this year, TMDB's discover sort trusts revenue.desc but the list endpoint
    // never returns the actual revenue figure, and most catalog entries have none at all.
    // Below this cutoff we verify each candidate's real revenue via the detail endpoint
    // and only rank the ones we can confirm.
    private static let verifiedRevenueCutoffYear = 1939

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
        let data = try await fetchData(from: components.url!)
        let response = try JSONDecoder().decode(MovieDiscoverResponse.self, from: data)
        return Array(response.results.prefix(count)).map {
            Movie(id: $0.id, title: $0.title, revenue: $0.revenue ?? 0, voteCount: $0.vote_count ?? 0)
        }
    }

    // TMDB's revenue data gets sparse before 1939. Rather than rank movies with no known
    // revenue, this pulls candidates a page at a time (discover already sorts by
    // revenue.desc, so real numbers cluster up front), verifies each one's real figure via
    // the detail endpoint, and returns only the confirmed ones — shorter than `count` when
    // a year doesn't have enough reliable data. Because the sort puts every film with a real
    // figure first, a page containing any film without one means later pages have none, so
    // the next page is fetched only when every film on this page verified.
    private func fetchVerifiedBoxOfficeTop(year: Int, count: Int) async throws -> [Movie] {
        var verifiedByID: [Int: (MovieResult, Int)] = [:]
        for page in 1...2 {
            let candidates = try await fetchRevenueDiscoverPage(year: year, page: page)
            if candidates.isEmpty { break }

            // Every lookup runs to the end, even after one fails, so the ones that
            // succeeded are cached and a Retry only re-requests what failed.
            var pageHadUnverified = false
            var failure: Error?
            let pageVerified: [(MovieResult, Int)] = await withTaskGroup(of: (MovieResult, Result<Int?, Error>).self) { group in
                for candidate in candidates {
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
                        pageHadUnverified = true
                    case .failure(let error):
                        failure = failure ?? error
                    }
                }
                return results
            }
            if let failure { throw failure }
            for (candidate, revenue) in pageVerified {
                verifiedByID[candidate.id] = (candidate, revenue)
            }

            // Discover pages are 20 results; a short page means there's nothing more to fetch.
            if verifiedByID.count >= count || candidates.count < 20 || pageHadUnverified { break }
        }

        return verifiedByID.values
            .sorted { $0.1 > $1.1 }
            .prefix(count)
            .map { Movie(id: $0.0.id, title: $0.0.title, revenue: $0.1, voteCount: $0.0.vote_count ?? 0) }
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
        let data = try await fetchData(from: components.url!)
        return try JSONDecoder().decode(MovieDiscoverResponse.self, from: data).results
    }

    /// The film's revenue, or nil when TMDB has no figure for it (including a
    /// film whose detail page is gone). Any other failed request throws, so it
    /// fails the Box Office list rather than silently dropping the film.
    private func fetchRevenue(for movieID: Int) async throws -> Int? {
        if let cached = revenueCache[movieID] {
            return cached > 0 ? cached : nil
        }
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/movie/\(movieID)")!
        components.queryItems = [URLQueryItem(name: "api_key", value: Config.tmdbAPIKey)]
        let revenue: Int
        do {
            let data = try await fetchData(from: components.url!)
            revenue = try JSONDecoder().decode(MovieDetailResponse.self, from: data).revenue ?? 0
        } catch TMDBError.badStatus(404) {
            // Still listed by discover but deleted or merged on TMDB; retrying won't help
            revenue = 0
        }
        revenueCache[movieID] = revenue
        return revenue > 0 ? revenue : nil
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
        let data = try await fetchData(from: components.url!)
        let response = try JSONDecoder().decode(MovieDiscoverResponse.self, from: data)
        return Array(response.results.prefix(count)).map {
            Movie(id: $0.id, title: $0.title, revenue: $0.revenue ?? 0, voteCount: $0.vote_count ?? 0)
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
