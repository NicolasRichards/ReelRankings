import SwiftUI

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct MovieRowView: View {
    let rank: Int
    let movie: Movie
    var userMovie: UserMovie?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(rank).")
                .font(.caption.monospaced())
                .foregroundStyle(gold)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 1)

            if let imdbID = movie.imdbID,
               let url = URL(string: "https://www.imdb.com/title/\(imdbID)/") {
                Button {
                    openURL(url)
                } label: {
                    Text(movie.title)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .underline(true, color: gold.opacity(0.6))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                Text(movie.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Personal status indicator
            if let record = userMovie {
                if record.isOnWatchlist {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(gold)
                        .padding(.top, 3)
                } else if record.isSeen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.top, 3)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}
