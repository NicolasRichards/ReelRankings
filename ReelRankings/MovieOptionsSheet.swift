import SwiftUI
import SwiftData

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct MovieOptionsSheet: View {
    let movie: Movie
    let year: Int
    let existingRecord: UserMovie?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Local state mirrors the persisted record so toggles feel instant
    @State private var isOnWatchlist: Bool = false
    @State private var isSeen: Bool = false
    @State private var userRating: Int = 0

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()

            VStack(spacing: 0) {
                // Handle bar
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                Text(movie.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                VStack(spacing: 1) {
                    // Watchlist row
                    optionRow(
                        icon: isOnWatchlist ? "bookmark.fill" : "bookmark",
                        iconColor: isOnWatchlist ? gold : .secondary,
                        label: isOnWatchlist ? "On Watchlist" : "Add to Watchlist"
                    ) {
                        isOnWatchlist.toggle()
                        if isOnWatchlist { isSeen = false; userRating = 0 }
                        save()
                    }

                    Divider().opacity(0.2)

                    // Seen row
                    optionRow(
                        icon: isSeen ? "checkmark.circle.fill" : "checkmark.circle",
                        iconColor: isSeen ? .green : .secondary,
                        label: isSeen ? "Seen It" : "Mark as Seen"
                    ) {
                        isSeen.toggle()
                        if isSeen { isOnWatchlist = false }
                        if !isSeen { userRating = 0 }
                        save()
                    }

                    // Star rating — only shown after marking seen
                    if isSeen {
                        Divider().opacity(0.2)
                        HStack {
                            Text("My Rating")
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StarRatingView(rating: $userRating)
                                .onChange(of: userRating) { save() }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color(white: 0.13))
                    }
                }
                .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                // Remove entirely
                if existingRecord != nil {
                    Button(role: .destructive) {
                        if let record = existingRecord {
                            modelContext.delete(record)
                            try? modelContext.save()
                        }
                        dismiss()
                    } label: {
                        Label("Remove from My Films", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(.top, 24)
                    }
                }

                Spacer()

                Button("Done") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(gold)
                    .padding(.bottom, 28)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            isOnWatchlist = existingRecord?.isOnWatchlist ?? false
            isSeen = existingRecord?.isSeen ?? false
            userRating = existingRecord?.userRating ?? 0
        }
    }

    // MARK: - Helpers

    private func optionRow(icon: String, iconColor: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 22)
                Text(label)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        // Re-fetch by tmdbID instead of trusting existingRecord: that value is
        // captured at presentation time, so after the first save here it can
        // still be nil and a second toggle would insert a duplicate record.
        let record: UserMovie
        if let existing = existingRecord ?? fetchRecord() {
            record = existing
        } else {
            record = UserMovie(tmdbID: movie.id, title: movie.title, year: year)
            modelContext.insert(record)
        }
        record.isOnWatchlist = isOnWatchlist
        record.isSeen = isSeen
        record.userRating = userRating
        try? modelContext.save()
    }

    private func fetchRecord() -> UserMovie? {
        let id = movie.id
        var descriptor = FetchDescriptor<UserMovie>(predicate: #Predicate { $0.tmdbID == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
