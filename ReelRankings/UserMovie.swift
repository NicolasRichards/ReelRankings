import SwiftData
import Foundation

@Model
final class UserMovie {
    // CloudKit-backed SwiftData requires a default value on every property
    var tmdbID: Int = 0
    var title: String = ""
    var year: Int = 0
    var isOnWatchlist: Bool = false
    var isSeen: Bool = false
    var userRating: Int = 0  // 0 = unrated, 1–5
    var dateAdded: Date = Date()

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
