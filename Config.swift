// Config.swift
// ⚠️ Replace YOUR_TMDB_API_KEY_HERE with your actual TMDB v3 API key before building.
// Get a free key at https://www.themoviedb.org/settings/api

struct Config {
    nonisolated(unsafe) static let tmdbAPIKey = "YOUR_TMDB_API_KEY_HERE"
    nonisolated(unsafe) static let tmdbBaseURL = "https://api.themoviedb.org/3"
}
