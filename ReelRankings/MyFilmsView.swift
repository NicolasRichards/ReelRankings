import SwiftUI
import SwiftData

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct MyFilmsView: View {
    @Query(sort: \UserMovie.dateAdded, order: .reverse) private var userMovies: [UserMovie]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var editingMovie: UserMovie?
    @State private var seenSort: SeenSort = .year

    enum SeenSort { case year, rating }

    // uniquingKeysWith: a duplicate tmdbID must never render twice, even before
    // the activation-time merge pass has healed it — keep the oldest record,
    // matching what UserMovie.deduplicate keeps
    private var uniqueMovies: [UserMovie] {
        Dictionary(grouping: userMovies, by: \.tmdbID).values.compactMap { records in
            records.min { $0.dateAdded < $1.dateAdded }
        }
    }

    private var watchlist: [UserMovie] {
        uniqueMovies.filter { $0.isOnWatchlist }.sorted { $0.dateAdded > $1.dateAdded }
    }

    // Groups for the Seen section, label + sorted movies
    private var seenGroups: [(label: String, movies: [UserMovie])] {
        let seen = uniqueMovies.filter { $0.isSeen }
        switch seenSort {
        case .year:
            let grouped = Dictionary(grouping: seen, by: { $0.year })
            return grouped.keys.sorted(by: >).map { year in
                let sorted = grouped[year]!.sorted { a, b in
                    // rated above unrated, then higher rating first
                    if a.userRating == b.userRating { return false }
                    if a.userRating == 0 { return false }
                    if b.userRating == 0 { return true }
                    return a.userRating > b.userRating
                }
                return (label: String(year), movies: sorted)
            }
        case .rating:
            let grouped = Dictionary(grouping: seen, by: { $0.userRating })
            return grouped.keys.sorted(by: >).map { rating in
                let sorted = grouped[rating]!.sorted { $0.year > $1.year }
                let label = rating == 0 ? "Unrated" : String(repeating: "★", count: rating)
                return (label: label, movies: sorted)
            }
        }
    }

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("My Films")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(gold)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                if userMovies.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.white.opacity(0.2))
                        Text("No films yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Tap ⊙ on any movie to add it\nto your watchlist or mark it seen.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if !watchlist.isEmpty {
                                filmSection(title: "Watchlist", icon: "bookmark.fill", movies: watchlist)
                            }
                            if !seenGroups.isEmpty {
                                // Sort picker
                                Picker("Sort seen by", selection: $seenSort) {
                                    Text("By Year").tag(SeenSort.year)
                                    Text("By Rating").tag(SeenSort.rating)
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 20)

                                ForEach(seenGroups, id: \.label) { group in
                                    filmSection(title: group.label, icon: "checkmark.circle.fill", movies: group.movies)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editingMovie) { record in
            // Re-use options sheet via a thin adapter
            MyFilmsEditSheet(record: record)
        }
    }

    private func filmSection(title: String, icon: String, movies: [UserMovie]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(gold)
                .tracking(1)
                .textCase(.uppercase)

            VStack(spacing: 1) {
                ForEach(movies) { record in
                    Button {
                        editingMovie = record
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                if record.isSeen && record.userRating > 0 {
                                    HStack(spacing: 2) {
                                        ForEach(1...5, id: \.self) { star in
                                            Image(systemName: star <= record.userRating ? "star.fill" : "star")
                                                .font(.caption2)
                                                .foregroundStyle(star <= record.userRating ? gold : Color.white.opacity(0.2))
                                        }
                                    }
                                } else if record.isSeen {
                                    Text("Unrated")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(white: 0.13))
                    }
                    .buttonStyle(.plain)

                    if record.id != movies.last?.id {
                        Divider().opacity(0.2)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Thin wrapper so MyFilmsView can present a sheet using a UserMovie directly
private struct MyFilmsEditSheet: View {
    let record: UserMovie
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isOnWatchlist: Bool = false
    @State private var isSeen: Bool = false
    @State private var userRating: Int = 0

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                Text(record.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                VStack(spacing: 1) {
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

                Button(role: .destructive) {
                    modelContext.delete(record)
                    try? modelContext.save()
                    dismiss()
                } label: {
                    Label("Remove from My Films", systemImage: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.top, 24)
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
            isOnWatchlist = record.isOnWatchlist
            isSeen = record.isSeen
            userRating = record.userRating
        }
    }

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
        record.isOnWatchlist = isOnWatchlist
        record.isSeen = isSeen
        record.userRating = userRating
        try? modelContext.save()
    }
}
