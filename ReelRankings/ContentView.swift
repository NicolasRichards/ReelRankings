import SwiftUI
import StoreKit

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @AppStorage("listDepth") private var listDepth = 10
    @State private var showingAbout = false
    @State private var showingMyFilms = false
    @State private var showingSearch = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.07).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Year picker
                    Picker("Year", selection: $viewModel.selectedYear) {
                        ForEach(viewModel.availableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)

                    // Column headers
                    HStack(spacing: 0) {
                        Text("BOX OFFICE GROSS")
                            .font(.caption)
                            .foregroundStyle(gold)
                            .tracking(1)
                            .frame(maxWidth: .infinity)
                        Divider().frame(height: 32)
                        Text("AUDIENCE FAVORITES")
                            .font(.caption)
                            .foregroundStyle(gold)
                            .tracking(1)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                    .background(Color(white: 0.07))

                    Divider()

                    // Two-column movie lists
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            MovieListView(movies: viewModel.boxOfficeMovies, year: viewModel.selectedYear, targetCount: listDepth)
                            Divider()
                            MovieListView(movies: viewModel.audienceMovies, year: viewModel.selectedYear, targetCount: listDepth)
                        }
                    }
                }

                // Loading overlay
                if viewModel.isLoading {
                    ProgressView()
                        .tint(gold)
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("ReelRankings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingMyFilms = true
                    } label: {
                        Image(systemName: "film.stack")
                            .foregroundStyle(gold)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(gold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("List Depth", selection: $listDepth) {
                            ForEach([5, 10, 15, 20], id: \.self) { depth in
                                Text("Top \(depth)").tag(depth)
                            }
                        }
                    } label: {
                        Image(systemName: "list.number")
                            .foregroundStyle(gold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(gold)
                    }
                }
            }
            .sheet(isPresented: $showingMyFilms) {
                MyFilmsView()
            }
            .sheet(isPresented: $showingSearch) {
                MovieSearchView { year in
                    let bounds = viewModel.availableYears
                    let minYear = bounds.last ?? year
                    let maxYear = bounds.first ?? year
                    viewModel.selectedYear = min(max(year, minYear), maxYear)
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .overlay(alignment: .bottom) {
                if let message = viewModel.errorMessage {
                    ErrorBannerView(message: message) {
                        viewModel.dismissError()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.errorMessage)
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.loadMovies(depth: listDepth)
        }
        .onChange(of: viewModel.selectedYear) {
            Task { await viewModel.loadMovies(depth: listDepth) }
        }
        .onChange(of: listDepth) {
            Task { await viewModel.loadMovies(depth: listDepth) }
        }
    }
}

// MARK: - About

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var tipJar = TipJar()

    private let appStoreURL = URL(string: "https://apps.apple.com/app/id6776025432")!

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("ReelRankings")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text("Box office vs. audience favorites,\nyear by year.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    Text("For years before 1939, reliable box office figures aren't available for every film, so the Box Office Gross list is sometimes shorter than the Audience Favorites list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    supportSection

                    Divider()

                    VStack(spacing: 12) {
                        Text("Data provided by")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            openURL(URL(string: "https://www.themoviedb.org")!)
                        } label: {
                            Text("The Movie Database (TMDB)")
                                .font(.headline)
                                .foregroundStyle(gold)
                        }

                        Text("This product uses the TMDB API but is not\nendorsed or certified by TMDB.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("Made with love by Nicolas Richards")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(gold)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 28)
            }
        }
        .preferredColorScheme(.dark)
        .task { await tipJar.load() }
        .task { await tipJar.listenForTransactions() }
    }

    // MARK: Support

    private var supportSection: some View {
        VStack(spacing: 16) {
            Text("Enjoying the app? 🎬")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text("This app is 100% free, ad-free and tracking free, a gift meant for every movie lover. Have a little extra and want to say thanks? Only do this if you really can afford to!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Text("☕ Buy us a coffee?")
                    .font(.headline)
                    .foregroundStyle(.white)

                if tipJar.didTip {
                    Text("Thank you so much. 💛")
                        .font(.subheadline)
                        .foregroundStyle(gold)
                        .padding(.vertical, 8)
                } else if tipJar.loadFailed {
                    Text("Tip options couldn't load right now.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else if tipJar.products.isEmpty {
                    ProgressView()
                        .tint(gold)
                        .padding(.vertical, 12)
                } else {
                    ForEach(tipJar.products, id: \.id) { product in
                        tipRow(reels: reelCount(for: product), product: product)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 12) {
                Button {
                    requestReview()
                } label: {
                    Label("Rate us", systemImage: "star.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(gold.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                }
                .foregroundStyle(gold)

                Button {
                    openURL(appStoreURL)
                } label: {
                    Label("App Store", systemImage: "arrow.up.forward")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.5)))
                }
                .foregroundStyle(gold)
            }
        }
    }

    private func tipRow(reels: Int, product: Product) -> some View {
        Button {
            Task { await tipJar.purchase(product) }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    ForEach(0..<reels, id: \.self) { _ in
                        Image(systemName: "movieclapper")
                    }
                }
                .foregroundStyle(gold)

                Text(tierName(for: reels))
                    .foregroundStyle(.white)

                Spacer()

                if tipJar.purchasing == product.id {
                    ProgressView().tint(gold)
                } else {
                    Text(product.displayPrice)
                        .font(.headline)
                        .foregroundStyle(gold)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(gold.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .disabled(tipJar.purchasing != nil)
    }

    private func tierName(for reels: Int) -> String {
        switch reels {
        case 1: "Small tip"
        case 2: "Medium tip"
        default: "Large tip"
        }
    }

    /// Reel count keyed off the product's own ID, not its position in a
    /// price-sorted list — that list can have fewer than 3 entries whenever
    /// not every tier is approved yet, which would otherwise mislabel tiers.
    private func reelCount(for product: Product) -> Int {
        if product.id.hasSuffix(".small") { return 1 }
        if product.id.hasSuffix(".medium") { return 2 }
        return 3
    }
}

// MARK: - Error Banner

private struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .font(.subheadline.bold())
                .foregroundStyle(gold)
        }
        .padding()
        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onDismiss() }
    }
}
