import Foundation

struct Movie: Identifiable {
    let id: Int          // TMDB movie ID
    let title: String
    let revenue: Int     // worldwide gross in USD (0 if unknown)
    let voteCount: Int   // TMDB vote count
}

/// Where a film places in this app's lists for the selected year.
struct FilmRanking: Hashable {
    let list: String
    let rank: Int
    let year: Int
}
