import Foundation
import Combine

@MainActor
class ContentViewModel: ObservableObject {
    @Published var selectedYear: Int
    @Published var boxOfficeMovies: [Movie] = []
    @Published var audienceMovies: [Movie] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    let availableYears: [Int]

    private let service = TMDBService()
    private var dismissTask: Task<Void, Never>?
    // Incremented on every load so stale responses (older year OR older depth) are discarded
    private var loadGeneration = 0

    init() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let defaultYear = currentYear - 1
        self.selectedYear = defaultYear
        self.availableYears = Array(stride(from: defaultYear, through: 1929, by: -1))
    }

    func loadMovies(depth: Int) async {
        loadGeneration += 1
        let generation = loadGeneration
        let year = selectedYear
        isLoading = true
        errorMessage = nil
        boxOfficeMovies = []
        audienceMovies = []

        do {
            // Fetch both lists concurrently
            async let boxOffice = service.fetchBoxOfficeTop(year: year, count: depth)
            async let audience = service.fetchAudienceTop(year: year, count: depth)
            let (bo, aud) = try await (boxOffice, audience)

            guard generation == loadGeneration else { return }
            boxOfficeMovies = bo
            audienceMovies = aud
            isLoading = false
        } catch {
            guard generation == loadGeneration else { return }
            isLoading = false
            showError("Couldn't load \(year) — check your connection.")
        }
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

    func dismissError() {
        dismissTask?.cancel()
        errorMessage = nil
    }

    // MARK: - Private

    private func showError(_ message: String) {
        errorMessage = message
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                errorMessage = nil
            }
        }
    }
}
