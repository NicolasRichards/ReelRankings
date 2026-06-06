import SwiftUI
import SwiftData

struct MovieListView: View {
    let movies: [Movie]

    @Query private var userMovies: [UserMovie]
    @State private var selectedMovie: Movie?

    private var userMovieByID: [Int: UserMovie] {
        Dictionary(uniqueKeysWithValues: userMovies.map { ($0.tmdbID, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                MovieRowView(rank: index + 1, movie: movie, userMovie: userMovieByID[movie.id]) {
                    selectedMovie = movie
                }
                if index < movies.count - 1 {
                    Divider().opacity(0.25)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $selectedMovie) { movie in
            MovieOptionsSheet(movie: movie, existingRecord: userMovieByID[movie.id])
        }
    }
}
