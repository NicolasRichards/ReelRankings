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

    init() {
        let currentYear = Calendar.current.component(.year, from: Date())
        let defaultYear = currentYear - 1
        self.selectedYear = defaultYear
        self.availableYears = Array(stride(from: defaultYear, through: 1939, by: -1))
    }

    func loadMovies() async {
        let year = selectedYear
        isLoading = true
        errorMessage = nil
        boxOfficeMovies = []
        audienceMovies = []

        do {
            // Fetch both lists concurrently
            async let boxOffice = service.fetchBoxOfficeTop10(year: year)
            async let audience = service.fetchAudienceTop10(year: year)
            let (bo, aud) = try await (boxOffice, audience)

            guard year == selectedYear else { return }
            boxOfficeMovies = bo
            audienceMovies = aud
            isLoading = false

            // Fetch IMDB IDs in parallel, updating lists progressively as each resolves
            let allIDs = Array(Set(bo.map(\.id) + aud.map(\.id)))
            await withTaskGroup(of: (Int, String?).self) { group in
                for id in allIDs {
                    group.addTask { [service] in
                        await service.fetchIMDBID(for: id)
                    }
                }
                for await (id, imdbID) in group {
                    guard let imdbID, year == self.selectedYear else { continue }
                    self.applyIMDBID(id: id, imdbID: imdbID)
                }
            }
        } catch {
            guard year == selectedYear else { return }
            isLoading = false
            showError("Couldn't load \(year) — check your connection.")
        }
    }

    func dismissError() {
        dismissTask?.cancel()
        errorMessage = nil
    }

    // MARK: - Private

    private func applyIMDBID(id: Int, imdbID: String) {
        boxOfficeMovies = boxOfficeMovies.map { movie in
            guard movie.id == id else { return movie }
            return Movie(id: movie.id, title: movie.title, revenue: movie.revenue, voteCount: movie.voteCount, imdbID: imdbID)
        }
        audienceMovies = audienceMovies.map { movie in
            guard movie.id == id else { return movie }
            return Movie(id: movie.id, title: movie.title, revenue: movie.revenue, voteCount: movie.voteCount, imdbID: imdbID)
        }
    }

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
