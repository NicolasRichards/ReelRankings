import SwiftUI

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct MovieListView: View {
    let movies: [Movie]
    // Rows always render up to this count; entries beyond `movies` render blank
    // (used for pre-1939 years where verified box office data runs out early).
    let targetCount: Int
    let userMovieByID: [Int: UserMovie]
    let onToggleSeen: (Movie) -> Void
    let onSelect: (Movie) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<targetCount, id: \.self) { index in
                if index < movies.count {
                    let movie = movies[index]
                    MovieRowView(
                        rank: index + 1,
                        movie: movie,
                        userMovie: userMovieByID[movie.id],
                        onToggleSeen: { onToggleSeen(movie) },
                        onSelect: { onSelect(movie) }
                    )
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
    }
}

private struct BlankMovieRowView: View {
    let rank: Int

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(rank).")
                .font(.caption.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(gold.opacity(0.35))
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 9)

            Color.clear.frame(width: 32, height: 34)

            Text("—")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
        .padding(.leading, 4)
    }
}
