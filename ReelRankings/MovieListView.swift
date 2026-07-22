import SwiftUI
import SwiftData

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct MovieListView: View {
    let movies: [Movie]
    let year: Int
    // Rows always render up to this count; entries beyond `movies` render blank
    // (used for pre-1939 years where verified box office data runs out early).
    let targetCount: Int

    @Query private var userMovies: [UserMovie]
    @State private var selectedMovie: Movie?

    private var userMovieByID: [Int: UserMovie] {
        // uniquingKeysWith: a duplicate tmdbID must never crash the list
        Dictionary(userMovies.map { ($0.tmdbID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<targetCount, id: \.self) { index in
                if index < movies.count {
                    let movie = movies[index]
                    MovieRowView(rank: index + 1, movie: movie, userMovie: userMovieByID[movie.id]) {
                        selectedMovie = movie
                    }
                } else {
                    BlankMovieRowView(rank: index + 1)
                }
                if index < targetCount - 1 {
                    Divider().opacity(0.25)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $selectedMovie) { movie in
            MovieOptionsSheet(movie: movie, year: year, existingRecord: userMovieByID[movie.id])
        }
    }
}

private struct BlankMovieRowView: View {
    let rank: Int

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(rank).")
                .font(.caption.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(gold.opacity(0.35))
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 1)

            Text("—")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.2))
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "ellipsis.circle")
                .font(.caption)
                .foregroundStyle(.clear)
                .padding(.top, 3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}
