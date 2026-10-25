# Yuin · 余音

English | [简体中文](README.zh-CN.md)

[![Build and Release](https://github.com/linq/yuin/actions/workflows/build-release.yml/badge.svg)](https://github.com/linq/yuin/actions/workflows/build-release.yml)

A native macOS music player inspired by Apple Music, built with SwiftUI, AppKit, and AVPlayer. Yuin supports music search, playlists, charts, downloads, synchronized lyrics, and custom LX-compatible JavaScript music sources.

Yuin is currently a **0.1.1 development release**. Public catalog APIs for five platforms have been checked against live services. A user-provided Hei Music source, v2.2.1-fix, has passed sample checks for local and online import, initialization, playback across all five platforms, downloads, and offline playback. Successful quality requests do not certify the actual bitrate or bit depth of the audio. See the [validation record](docs/STATUS.md) for details.

## Download and run

Download a Universal build from [GitHub Releases](https://github.com/linq/yuin/releases), with support for both Apple Silicon and Intel. Releases include a DMG, a ZIP, and SHA-256 checksums. Current builds use ad-hoc signing and do not have an Apple Developer ID signature or notarization.

To build and open the app locally:

```bash
./scripts/build-app.sh
open dist/Yuin.app
```

The script creates a Release build by default; use `./scripts/build-app.sh debug` for a Debug build. The app is named **Yuin** in English and **余音** in Chinese. The interface supports English, Simplified Chinese, and automatic system language selection, along with light, dark, and system appearance modes.

Building requires **Xcode 26 or newer** and its full toolchain. There are no external Swift package dependencies. When available, the script selects `/Applications/Xcode.app` through `DEVELOPER_DIR` for that process without changing the global `xcode-select` setting.

You can also open `Package.swift` in Xcode. Before using `swift run MyMusic` directly, run `swift build` so the `MusicSourceHost` executable is available too. The deployment target is macOS 14+. Local validation has used macOS 27.0.1 on Apple Silicon, and CI uses macOS 26. Universal builds contain Intel code, but Intel hardware and macOS 14–15 have not been tested at runtime.

## Automated builds and releases

- Pushing to `main` or opening a pull request runs tests, builds the Universal app, and packages a DMG, ZIP, and checksums. Download these from the workflow's artifacts.
- Pushing a `vX.Y.Z` or `vX.Y.Z-beta.1` tag runs the same checks, then creates a GitHub Release and uploads the packages. Tags with a version suffix are marked as prereleases.
- Update and commit the root `VERSION` file before pushing a matching version tag. Only the release job receives `contents: write`; no personal access token is required.

```bash
./scripts/package-release.sh 0.1.1

# After updating VERSION to 0.2.0 and committing and pushing that change:
git tag v0.2.0
git push origin v0.2.0
```

See the [release guide](docs/RELEASING.md) for details. Supporting project documentation is currently in Chinese, except for the third-party notices.

## Usage

1. Choose a platform in Search, Playlists, or Charts to browse its catalog. These pages share the most recently selected platform, which is saved across restarts and included in backups.
2. In Music Sources, import a local `.js` file or an HTTP(S) URL, then enable the source. You can save multiple sources; one is active at a time.
3. Double-click a song to play it. Right-click or use its menu to play next, add to the queue, favorite, add to a personal playlist, or download.
4. Save a complete playlist or chart as a local playlist, or download its tracks in bulk. If the full list cannot be retrieved, the app reports the error rather than silently saving a partial list.
5. Choose a download quality and destination. Up to two downloads run concurrently. Before saving, the app checks the format, bitrate, and 24-bit depth when requested, rejecting mismatched quality. Existing files are checked too. Downloaded files are preferred for playback and can be played offline.
6. Use Settings to change default quality, export a backup, or restore one. After restoring a backup, enable your music source manually.

The floating player provides playback controls, shuffle and repeat-one modes, seeking, song actions, queue access, and volume. Click its artwork or song title to expand Now Playing. Narrow windows hide some controls, while playback modes remain available in the song menu.

Track changes fade out the previous song while the new song starts at normal volume, without fading in. In Settings → Playback → Fade Out, choose 0–12 seconds (5 seconds by default; 0 turns the fade off). Sequential playback prepares the next track and starts the transition before the current song ends. Network buffering or the remaining audio may shorten the fade. Artwork and song information transition smoothly, keeping the previous artwork visible until its replacement has loaded.

The app opens to Playlists. Settings uses General, Playback, Files, and Advanced tabs; changes take effect immediately. Download quality and the download folder are under Files.

Switching away from Search and back within the same window preserves draft keywords, submitted results, loaded pages, selection, and scroll position. Changing platforms elsewhere causes Search to refresh for the new platform when you return. Search sessions are not restored across app restarts.

Keyboard shortcuts: `⌘N` creates a playlist, `⇧⌘I` imports a source, `Space` toggles playback, `⌘←` / `⌘→` skips tracks, and `⌘U` toggles the queue. Space continues to work normally when typing in search or other text fields. System media controls are supported.

## Data and backups

Yuin was originally named MyMusic. Its bundle identifier, library, and preferences remain compatible with previous builds, so the existing data paths are retained:

- Library state: `~/Library/Application Support/MyMusic/library.json`.
- Default download folder: `~/Music/MyMusic`, configurable in Settings or the download dialog.
- Backups include playlists, history, queue, settings, source scripts, and download records, **but not audio files**. Offline playback still depends on the original file paths.
- Restoring a backup first saves a snapshot of the current state. A damaged library is not automatically overwritten with an empty one.
- Restarts restore the queue and playback position without starting playback automatically. Interrupted downloads remain listed and can be retried manually.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
MUSIC_NETWORK_TESTS=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Normal tests use a local HTTP fixture server and temporary directories without contacting music platforms. Enable live platform checks with `MUSIC_NETWORK_TESTS=1`. These report platform capabilities and full-list retrieval results; passing tests do not guarantee continuous availability of external services.

Local integration coverage includes online source import, LX HTTP callbacks, Buffer operations, MD5, AES/RSA comparisons against OpenSSL, zlib, failed source initialization, infinite-loop timeouts, download cancellation, duplicate handling, downloaded file validation, and AVPlayer offline playback. Audio fixtures are generated silence, not music from a real service. No sample music source is bundled.

Real-source validation requires an explicitly supplied trusted script, either a URL or a local path:

```bash
MUSIC_REAL_SOURCE='/absolute/path/source.js' DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter RealSourceTests
```

Optional environment variables:

- `MUSIC_REAL_ALL_QUALITIES=1`: check every quality declared by the source.
- `MUSIC_REAL_QUERY`: set the search query.
- `MUSIC_REAL_PLATFORM=kw`: restrict validation to one platform.
- `MUSIC_REAL_DOWNLOAD_ALL=1`: download every sample that played successfully.

These checks play silently and download into temporary directories, without changing your library. The minimum passing case is one real sample that plays, downloads, and plays offline after the source host stops. Individual platform failures are reported separately. Third-party scripts are not distributed with the project and may contact their own analytics services.

## Project structure

- `Sources/MusicCore/`: track models, five platform adapters, complete-list pagination, persistence, source process client, and downloads.
- `Sources/MusicSourceHost/`: a separate JavaScriptCore process providing the `window.lx` API 2.0 bridge. It can be terminated on timeout without blocking the native interface.
- `Sources/MyMusic/`: SwiftUI views, AVPlayer integration, system media controls, download scheduling, and source management.
- `Tests/`: models, pagination regressions, source protocol checks, local end-to-end tests, and optional live-service checks.
- `scripts/build-app.sh`: assembles the full `.app`, resources, and source host, then applies an ad-hoc signature.
- `scripts/package-release.sh`: builds the Universal app and creates the DMG, ZIP, and checksums.

The compatibility layer provides HTTP, timers, basic Buffer operations, MD5, random bytes, AES CBC/ECB, LX's 1024-bit RSA raw-padding behavior, and zlib. It does not provide a full Node.js or browser environment, DOM access, the Node filesystem, or arbitrary native modules. The separate process isolates script failures; it is not an operating-system permission sandbox. Compatibility must be checked against each source script.

Platform APIs can change. Errors are shown with retry options rather than replaced with sample results. Lyrics are supported; platform account sign-in, cross-device sync, local-folder scanning, and resumable downloads are outside the current scope.

See the [requirements](docs/REQUIREMENTS.md), [validation record](docs/STATUS.md), and [third-party notices](docs/THIRD_PARTY_NOTICES.md).
