import SwiftUI

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var showingAbout = false
    @State private var showingMyFilms = false

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
                    HStack(alignment: .top, spacing: 0) {
                        MovieListView(movies: viewModel.boxOfficeMovies, year: viewModel.selectedYear)
                        Divider()
                        MovieListView(movies: viewModel.audienceMovies, year: viewModel.selectedYear)
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
            await viewModel.loadMovies()
        }
        .onChange(of: viewModel.selectedYear) {
            Task { await viewModel.loadMovies() }
        }
    }
}

// MARK: - About

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Text("ReelRankings")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Box office vs. audience favorites,\nyear by year.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

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

                Spacer()

                Button("Done") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(gold)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
        }
        .preferredColorScheme(.dark)
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
