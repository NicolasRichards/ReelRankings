import SwiftData
import Foundation

@Model
final class UserMovie {
    var tmdbID: Int
    var title: String
    var year: Int
    var isOnWatchlist: Bool
    var isSeen: Bool
    var userRating: Int  // 0 = unrated, 1–5
    var dateAdded: Date

    init(tmdbID: Int, title: String, year: Int) {
        self.tmdbID = tmdbID
        self.title = title
        self.year = year
        self.isOnWatchlist = false
        self.isSeen = false
        self.userRating = 0
        self.dateAdded = Date()
    }
}
