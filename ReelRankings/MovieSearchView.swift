import SwiftUI

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct MovieSearchView: View {
    /// The years the app ranks; results outside it can't be jumped to.
    let yearRange: ClosedRange<Int>
    /// Called with the release year of the tapped result; the caller handles navigation/dismissal.
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MovieSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    private let service = TMDBService()

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("Search")
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

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search movies", text: $query)
                        .foregroundStyle(.white)
                        .tint(gold)
                        .autocorrectionDisabled()
                        .focused($fieldFocused)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

                if isSearching {
                    Spacer()
                    ProgressView().tint(gold)
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                } else if query.isEmpty {
                    Spacer()
                    Text("Search for a movie to jump\nto its year.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text("No results for \u{201C}\(query)\u{201D}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(results) { result in
                                resultRow(result)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { fieldFocused = true }
        .task(id: query) {
            await search(for: query)
        }
    }

    @ViewBuilder
    private func resultRow(_ result: MovieSearchResult) -> some View {
        let selectable = result.year.map(yearRange.contains) ?? false
        Button {
            guard let year = result.year, selectable else { return }
            onSelect(year)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.subheadline)
                        .foregroundStyle(selectable ? .white : Color.white.opacity(0.4))
                        .multilineTextAlignment(.leading)
                    Text(yearLabel(for: result.year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectable {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.13))
        }
        .buttonStyle(.plain)
        .disabled(!selectable)

        if result.id != results.last?.id {
            Divider().opacity(0.2)
        }
    }

    private func yearLabel(for year: Int?) -> String {
        guard let year else { return "Unknown year" }
        if year > yearRange.upperBound { return "\(year) · not ranked yet" }
        if year < yearRange.lowerBound { return "\(year) · before \(yearRange.lowerBound)" }
        return String(year)
    }

    private func search(for query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        // Spinner from the first keystroke: during the debounce the view
        // would otherwise say "No results" or show the previous query's results
        isSearching = true
        errorMessage = nil
        // Returning here leaves the spinner up on purpose: a cancelled task means
        // the query changed, and .task(id:) has already started its replacement.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let found = try await service.searchMovies(query: trimmed)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            isSearching = false
            errorMessage = "Couldn't search — check your connection."
        }
    }
}
