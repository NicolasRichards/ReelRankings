import SwiftUI

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct MovieRowView: View {
    let rank: Int
    let movie: Movie
    var userMovie: UserMovie?
    let onToggleSeen: () -> Void
    let onSelect: () -> Void

    private var isSeen: Bool { userMovie?.isSeen == true }
    private var isOnWatchlist: Bool { userMovie?.isOnWatchlist == true }
    private var rating: Int { isSeen ? userMovie?.userRating ?? 0 : 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(rank).")
                .font(.caption.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(gold)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 9)

            Button(action: onToggleSeen) {
                seenIcon
                    .font(.title3)
                    .frame(width: 32, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSeen ? "Seen" : "Mark as seen")
            .accessibilityValue(movie.title)

            Button(action: onSelect) {
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(movie.title)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        if rating > 0 {
                            InlineStarsView(rating: rating)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint("Shows film details")
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private var seenIcon: some View {
        if isSeen {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(gold)
        } else if isOnWatchlist {
            Image(systemName: "bookmark.circle")
                .foregroundStyle(gold.opacity(0.75))
        } else {
            Image(systemName: "circle")
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }
}

struct InlineStarsView: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: 9))
                    .foregroundStyle(star <= rating ? gold : Color.white.opacity(0.25))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating) of 5 stars")
    }
}

/// Native list-row feedback: the row dims while pressed instead of looking like a link.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0))
            )
    }
}
