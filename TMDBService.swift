import Foundation

actor TMDBService {
    // Cache TMDB ID → IMDB ID so switching years doesn't re-fetch known IDs
    private var imdbIDCache: [Int: String] = [:]

    // MARK: - Box Office Top 10

    func fetchBoxOfficeTop10(year: Int) async throws -> [Movie] {
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/discover/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Config.tmdbAPIKey),
            URLQueryItem(name: "primary_release_year", value: "\(year)"),
            URLQueryItem(name: "sort_by", value: "revenue.desc"),
            URLQueryItem(name: "vote_count.gte", value: "50"),
            URLQueryItem(name: "page", value: "1")
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(MovieDiscoverResponse.self, from: data)
        return Array(response.results.prefix(10)).map {
            Movie(id: $0.id, title: $0.title, revenue: $0.revenue ?? 0, voteCount: $0.vote_count ?? 0, imdbID: nil)
        }
    }

    // MARK: - Audience Favorites Top 10

    func fetchAudienceTop10(year: Int) async throws -> [Movie] {
        var components = URLComponents(string: "\(Config.tmdbBaseURL)/discover/movie")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: Config.tmdbAPIKey),
            URLQueryItem(name: "primary_release_year", value: "\(year)"),
            URLQueryItem(name: "sort_by", value: "vote_count.desc"),
            URLQueryItem(name: "vote_count.gte", value: "50"),
            URLQueryItem(name: "page", value: "1")
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(MovieDiscoverResponse.self, from: data)
        return Array(response.results.prefix(10)).map {
            Movie(id: $0.id, title: $0.title, revenue: $0.revenue ?? 0, voteCount: $0.vote_count ?? 0, imdbID: nil)
        }
    }

    // MARK: - IMDB ID Lookup (single, with cache)

    func fetchIMDBID(for movieID: Int) async -> (Int, String?) {
        if let cached = imdbIDCache[movieID] {
            return (movieID, cached)
        }
        let urlString = "\(Config.tmdbBaseURL)/movie/\(movieID)/external_ids?api_key=\(Config.tmdbAPIKey)"
        guard let url = URL(string: urlString) else { return (movieID, nil) }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
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

private struct MovieDiscoverResponse: Decodable, Sendable {
    let results: [MovieResult]
}

private struct MovieResult: Decodable, Sendable {
    let id: Int
    let title: String
    let revenue: Int?
    let vote_count: Int?
}

private struct ExternalIDsResponse: Decodable, Sendable {
    let imdb_id: String?
}
