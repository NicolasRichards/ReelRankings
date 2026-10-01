import Foundation
import Combine

@MainActor
class ContentViewModel: ObservableObject {
    @Published var selectedYear: Int
    @Published var boxOfficeMovies: [Movie] = []
    @Published var audienceMovies: [Movie] = []
    @Published var isLoading = false
    /// Set when the latest load failed; stays up until a retry or a new year.
    @Published var errorMessage: String? = nil
    /// Only the Box Office list failed: Audience Favorites loaded and stays up.
    @Published var boxOfficeFailed = false

    /// 1929 (when sound overtook silent film) through last year.
    let yearRange: ClosedRange<Int>
    let availableYears: [Int]

    private let service = TMDBService()
    private var loadTask: Task<Void, Never>?
    // Incremented on every load so stale responses (older year OR older depth) are discarded
    private var loadGeneration = 0

    init() {
        // Gregorian explicitly: Calendar.current follows the user's calendar
        // setting (Buddhist, Japanese), but TMDB release years are Gregorian.
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let defaultYear = currentYear - 1
        self.selectedYear = defaultYear
        let range = 1929...max(defaultYear, 1929)
        self.yearRange = range
        self.availableYears = Array(range.reversed())
    }

    /// Starts loading the selected year, cancelling any load still in flight
    /// so a fast scroll through the years doesn't leave requests piling up.
    func reload(depth: Int) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task { await loadMovies(depth: depth, generation: generation) }
    }

    /// Retries only the Box Office column, leaving Audience Favorites (which
    /// loaded fine) on screen.
    func retryBoxOffice(depth: Int) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let year = selectedYear
        boxOfficeFailed = false
        isLoading = true
        loadTask = Task {
            let bo = try? await service.fetchBoxOfficeTop(year: year, count: depth)
            guard generation == loadGeneration else { return }
            boxOfficeMovies = bo ?? []
            boxOfficeFailed = bo == nil
            isLoading = false
        }
    }

    private func loadMovies(depth: Int, generation: Int) async {
        let year = selectedYear
        isLoading = true
        errorMessage = nil
        boxOfficeFailed = false
        boxOfficeMovies = []
        audienceMovies = []

        // Fetch both lists concurrently, but let them fail separately: the
        // pre-1939 Box Office check makes dozens of requests, and one failing
        // shouldn't take down an Audience list that loaded fine.
        async let boxOffice = service.fetchBoxOfficeTop(year: year, count: depth)
        async let audience = service.fetchAudienceTop(year: year, count: depth)

        let aud: [Movie]
        do {
            aud = try await audience
        } catch {
            guard generation == loadGeneration else { return }
            isLoading = false
            errorMessage = "Couldn't load \(year). Check your connection and try again."
            return
        }

        let bo = try? await boxOffice

        guard generation == loadGeneration else { return }
        boxOfficeMovies = bo ?? []
        boxOfficeFailed = bo == nil
        audienceMovies = aud
        isLoading = false
    }

    /// A film's places in the currently displayed lists, e.g. #3 Box Office.
    func rankings(for movie: Movie) -> [FilmRanking] {
        var result: [FilmRanking] = []
        if let index = boxOfficeMovies.firstIndex(where: { $0.id == movie.id }) {
            result.append(FilmRanking(list: "Box Office", rank: index + 1, year: selectedYear))
        }
        if let index = audienceMovies.firstIndex(where: { $0.id == movie.id }) {
            result.append(FilmRanking(list: "Audience Favorite", rank: index + 1, year: selectedYear))
        }
        return result
    }

    /// Films shown for the year across both columns, counting a film in both once.
    var displayedFilmIDs: Set<Int> {
        Set(boxOfficeMovies.map(\.id) + audienceMovies.map(\.id))
    }
}
