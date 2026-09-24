import SwiftUI
import SwiftData

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct FilmDetailView: View {
    let movie: Movie
    let year: Int
    let rankings: [FilmRanking]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [UserMovie]

    @State private var detail: FilmDetail?
    @State private var isLoading = false
    @State private var loadFailed = false

    private let service = TMDBService()

    init(movie: Movie, year: Int, rankings: [FilmRanking]) {
        self.movie = movie
        self.year = year
        self.rankings = rankings
        let id = movie.id
        _records = Query(filter: #Predicate<UserMovie> { $0.tmdbID == id }, sort: \.dateAdded)
    }

    private var record: UserMovie? { records.first }
    private var isSeen: Bool { record?.isSeen == true }
    private var isOnWatchlist: Bool { record?.isOnWatchlist == true }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(white: 0.07).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    backdrop
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, detail?.backdropURL() == nil ? 56 : 0)
                    if !rankings.isEmpty {
                        rankingsView
                            .padding(.horizontal, 20)
                    }
                    myFilmsControls
                        .padding(.horizontal, 20)
                    filmInfo
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
            }

            Button("Done") { dismiss() }
                .font(.headline)
                .foregroundStyle(gold)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: - Header

    @ViewBuilder
    private var backdrop: some View {
        if let url = detail?.backdropURL() {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color(white: 0.12)
            }
            // Fixed height rather than 16:9 so the My Films controls stay
            // above the fold in the ~650pt-tall iPad form sheet, even for
            // films with a two-line title and a tagline
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Color(white: 0.07)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 80)
            }
            .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            poster

            VStack(alignment: .leading, spacing: 6) {
                Text(detail?.title ?? movie.title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                let metadata = [String(detail?.releaseYear ?? year), detail?.formattedRuntime].compactMap { $0 }
                Text(metadata.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let genres = detail?.genres, !genres.isEmpty {
                    Text(genres.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let tagline = detail?.tagline {
                    Text(tagline)
                        .font(.subheadline.italic())
                        .foregroundStyle(gold.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var poster: some View {
        AsyncImage(url: detail?.posterURL()) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Color(white: 0.14)
                Image(systemName: "film")
                    .font(.title)
                    .foregroundStyle(Color.white.opacity(0.25))
            }
        }
        .frame(width: 110, height: 165)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        .accessibilityHidden(true)
    }

    // MARK: - ReelRankings context

    private var rankingsView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { rankingChips }
            VStack(alignment: .leading, spacing: 8) { rankingChips }
        }
    }

    private var rankingChips: some View {
        ForEach(rankings, id: \.self) { ranking in
            Label("#\(ranking.rank) \(ranking.list), \(String(ranking.year))", systemImage: "trophy.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(gold)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(gold.opacity(0.14), in: Capsule())
        }
    }

    private var myFilmsControls: some View {
        VStack(spacing: 0) {
            controlRow(
                icon: isSeen ? "checkmark.circle.fill" : "circle",
                iconColor: isSeen ? gold : Color.white.opacity(0.45),
                label: isSeen ? "Seen" : "Mark as Seen"
            ) {
                UserMovie.update(movie, year: year, in: modelContext) { $0.setSeen(!isSeen) }
            }

            Divider().opacity(0.2)

            HStack {
                Text("My Rating")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StarRatingView(rating: Binding(
                    get: { isSeen ? record?.userRating ?? 0 : 0 },
                    set: { newRating in
                        UserMovie.update(movie, year: year, in: modelContext) { $0.setRating(newRating) }
                    }
                ))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.2)

            controlRow(
                icon: isOnWatchlist ? "bookmark.fill" : "bookmark",
                iconColor: isOnWatchlist ? gold : Color.white.opacity(0.45),
                label: isOnWatchlist ? "On Watchlist" : "Add to Watchlist"
            ) {
                UserMovie.update(movie, year: year, in: modelContext) { $0.setOnWatchlist(!isOnWatchlist) }
            }
        }
        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12))
    }

    private func controlRow(icon: String, iconColor: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 26)
                Text(label)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - TMDB details

    @ViewBuilder
    private var filmInfo: some View {
        if let detail {
            VStack(alignment: .leading, spacing: 20) {
                if let overview = detail.overview {
                    section("Overview") {
                        Text(overview)
                            .font(.body)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                let facts = facts(for: detail)
                if !facts.isEmpty {
                    section("Details") {
                        VStack(spacing: 0) {
                            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                                factRow(label: fact.label, value: fact.value)
                                if index < facts.count - 1 {
                                    Divider().opacity(0.2)
                                }
                            }
                        }
                        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                if !detail.cast.isEmpty {
                    section("Top Cast") {
                        VStack(spacing: 0) {
                            ForEach(Array(detail.cast.enumerated()), id: \.offset) { index, member in
                                factRow(label: member.name, value: member.character ?? "")
                                if index < detail.cast.count - 1 {
                                    Divider().opacity(0.2)
                                }
                            }
                        }
                        .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                Text("Film data from TMDB")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        } else if loadFailed {
            VStack(spacing: 12) {
                Text("Couldn't load film details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await load() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(gold.opacity(0.18), in: Capsule())
                }
                .foregroundStyle(gold)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        } else {
            ProgressView()
                .tint(gold)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }
    }

    private func facts(for detail: FilmDetail) -> [(label: String, value: String)] {
        var facts: [(label: String, value: String)] = []
        if !detail.directors.isEmpty {
            facts.append((detail.directors.count > 1 ? "Directors" : "Director", detail.directors.joined(separator: ", ")))
        }
        if let budget = detail.budget {
            facts.append(("Budget", FilmDetail.formattedDollars(budget)))
        }
        if let revenue = detail.revenue {
            facts.append(("Box Office", FilmDetail.formattedDollars(revenue)))
        }
        if let voteAverage = detail.voteAverage {
            facts.append(("TMDB Rating", "★ " + voteAverage.formatted(.number.precision(.fractionLength(1))) + " / 10"))
        }
        return facts
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(gold)
                .tracking(1)
                .textCase(.uppercase)
            content()
        }
    }

    private func factRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Loading

    private func load() async {
        if let cached = FilmDetailCache.load(id: movie.id) {
            detail = cached
            if FilmDetailCache.isFresh(cached) { return }
        }
        guard !isLoading else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let fresh = try await service.fetchFilmDetail(id: movie.id)
            FilmDetailCache.save(fresh)
            detail = fresh
        } catch {
            // An expired cache entry is still better than an error screen
            if detail == nil { loadFailed = true }
        }
    }
}
