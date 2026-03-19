import SwiftUI

struct MovieListView: View {
    let movies: [Movie]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(movies.enumerated()), id: \.element.id) { index, movie in
                MovieRowView(rank: index + 1, movie: movie)
                if index < movies.count - 1 {
                    Divider().opacity(0.25)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
