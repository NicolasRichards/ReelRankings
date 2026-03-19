import SwiftUI

private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

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
                        MovieListView(movies: viewModel.boxOfficeMovies)
                        Divider()
                        MovieListView(movies: viewModel.audienceMovies)
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
