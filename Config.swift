// Config.swift
// ⚠️ Replace YOUR_TMDB_API_KEY_HERE with your actual TMDB v3 API key before building.
// Get a free key at https://www.themoviedb.org/settings/api

enum Config {
    static let tmdbAPIKey = "YOUR_TMDB_API_KEY_HERE"
    static let tmdbBaseURL = "https://api.themoviedb.org/3"
    // Must match the App Group ID you create in Xcode (Signing & Capabilities)
    static let appGroupID = "group.com.yourname.reelrankings"
}
