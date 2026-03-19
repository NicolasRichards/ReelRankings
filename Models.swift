import Foundation

struct Movie: Identifiable {
    let id: Int          // TMDB movie ID
    let title: String
    let revenue: Int     // worldwide gross in USD (0 if unknown)
    let voteCount: Int   // TMDB vote count
    var imdbID: String?  // used to build IMDB URL; arrives async after initial load
}
