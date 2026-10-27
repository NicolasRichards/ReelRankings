# ReelRankings

iOS and iPadOS app (SwiftUI, Swift 6, iOS 26.2+, dark mode only, gold #FFD700 accent) that shows two ranked film lists side by side for any year from 1929 to last year: box office gross and TMDB audience vote count. Users mark films Seen, rate them and keep a watchlist, synced across devices with iCloud. Live on the App Store. Data comes from TMDB API v3.

## Workflow

The owner runs Claude Code locally on a Mac, in this folder, and opens the project in Xcode to find the latest changes. The owner does not use Terminal, so do not ask them to run git or shell commands; do the git work yourself. This folder is the only source; `~/Documents/Claude App Notes/ReelRankings/` holds the owner's specs and assets (including the 1.5 spec) and is read-only reference, never code.

- Build from the command line with `xcodebuild -project ReelRankings.xcodeproj -scheme ReelRankings -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` (verified on the owner's Mac, 2026-10-27). Do not report a build as passing unless one actually ran. There is no test target.
- The real TMDB key lives in `ReelRankings/Secrets.swift`, which is gitignored. Never commit it; the repo is public. `Secrets.swift.example` at the repo root is the template. A cloud session's fresh clone has no `Secrets.swift` and cannot build until one is created from the template.
- Cloud sessions have no Xcode: say plainly that a change is unbuilt, push a `claude/...` branch, and merge it into `main` rather than copying its commits onto `main`.
- The project uses synchronized folder groups, so new files in `ReelRankings/` are picked up without editing `project.pbxproj`.
- Before committing, review your own diff for regressions. Commit and push to `main` when the work is done.

## Layout

- `ReelRankings/`: app entry, `ContentView` + `ContentViewModel` (year wheel, the two lists), `MovieListView`, `MovieRowView`, `FilmDetail` + `FilmDetailView` (one `movie/{id}?append_to_response=credits` call, cached as JSON in Caches), `MovieSearchView`, `MyFilmsView`, `StarRatingView`, `TMDBService`, `UserMovie` (SwiftData model), `Config`, `TipJar`, `ReelRankings.storekit`
- `index.html` at the repo root: GitHub Pages privacy and support page
- App Store screenshots and icon PNGs at the repo root

## Conventions and gotchas

- `UserMovie` syncs through CloudKit (container `iCloud.NickRichards.ReelRankings`). Any change to the model's shape needs a Development-to-Production schema deploy in the CloudKit Console before release, and production fields can never be deleted or retyped.
- CloudKit can't enforce unique `tmdbID`, so duplicates happen across devices. `UserMovie.deduplicate` merges them on each scene activation; edits go through `UserMovie.update` / `setSeen` / `setOnWatchlist` / `setRating` so they apply to every duplicate.
- Years come from the Gregorian calendar explicitly. `Calendar.current` follows the user's setting, and Buddhist or Japanese calendars broke the year list.
- Before 1939 TMDB rarely has revenue data. `TMDBService.fetchVerifiedBoxOfficeTop` checks each candidate's revenue on its detail endpoint and ranks only confirmed figures; unfilled ranks show as blank rows. Audience Favorites always has a full list.
- Don't speculatively tune networking (for example `httpMaximumConnectionsPerHost`). It once slowed every year on real devices. Prefer changes that reduce the number of requests.
- No widget: one existed briefly and was removed on purpose. Don't suggest one.
- No web views anywhere. The app was rejected twice under Guideline 4.2.2 ("only web content") and approved after native film-detail and library features were added.
- The info screen carries TMDB attribution with the official logo (asset `TMDBLogo`).
- Project default actor isolation is MainActor; mark things `nonisolated` where they must run off the main actor.
- A "freeze" reported while running from Xcode is often a breakpoint or a debugger-caught iOS 27 assertion during rapid wheel scrolling, not an app bug. Ask whether it was launched from Xcode before investigating.
- Version bumps are their own commits, titled like `Bump to 1.6 (11)`. The owner archives and uploads from Xcode.
