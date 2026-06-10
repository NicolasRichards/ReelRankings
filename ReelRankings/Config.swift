// Config.swift
// The TMDB API key lives in Secrets.swift (gitignored). For a fresh clone,
// copy Secrets.swift.example from the repo root to ReelRankings/Secrets.swift
// and paste in your own key from https://www.themoviedb.org/settings/api

enum Config {
    static let tmdbAPIKey = Secrets.tmdbAPIKey
    static let tmdbBaseURL = "https://api.themoviedb.org/3"
}
