# External Integrations

**Analysis Date:** 2026-10-30

## APIs & External Services

**Music Metadata & Search:**
- **Deezer API:** Direct catalog search and album/artist metadata resolution
  - Implementation: `rust_backend/crates/providers/src/deezer.rs`
  - Authentication: None required for public endpoints; user-defined token support for extended metadata
- **MusicBrainz:** Open music encyclopedia for release IDs, acoustic fingerprints, and canonical metadata
  - Implementation: `rust_backend/crates/providers/src/musicbrainz.rs`
  - Rate Limiting: Built-in 1 req/sec throttler complying with MusicBrainz API fair usage
- **Community Extensions:** Dynamic external catalog, lyrics, and download provider integration
  - Implementation: `rust_backend/crates/extensions/src/provider.rs` and `lib/providers/extension_provider.dart`
  - Protocol: Custom JavaScript sandbox with `fetch`, `crypto`, and `session` host APIs

**Lyrics Services:**
- **LRCLIB / Kugou / Netease / Musixmatch:** Synchronized word-by-word and line-by-line LRC lyrics
  - Implementation: `rust_backend/crates/providers/src/lyrics/` and `lib/utils/lyrics_parser.dart`
  - Format: Standard and enhanced LRC format with phonetic pronunciation cues

**Social & Presence:**
- **Discord Rich Presence:** Displays currently playing track, artist, album art, elapsed time, and duration
  - Implementation: `third_party/mornye_discord/` and `lib/services/discord_presence_service.dart`
  - Authentication: Local IPC socket communication with desktop/mobile Discord client (Application ID)

**Network Storage & Streaming:**
- **SMB2 / SMB3:** Windows File Sharing protocol integration for remote library scanning and streaming
  - Client: `dart_smb2` (`0.1.3`) in `lib/services/network_storage_service.dart`
- **WebDAV / Nextcloud / ownCloud:** HTTP-based directory listing and audio streaming
  - Implementation: `lib/services/webdav_service.dart`
- **Subsonic API (Navidrome, Jellyfin, Subsonic):** Remote server synchronization and streaming
  - Implementation: `lib/services/subsonic_service.dart`

## Data Storage

**Databases:**
- **SQLite (via `sqflite` on mobile, `sqflite_common_ffi` on desktop):**
  - **`LibraryDatabase`** (`lib/services/library_database.dart`): Primary catalog storing scanned tracks, albums, artists, genres, playlists, and folder trees (`mornye_library.db`).
  - **`AppStateDatabase`** (`lib/services/app_state_database.dart`): Cached remote artist images, concert calendars, and playback state (`mornye_app_state.db`).
  - **`HistoryDatabase`** (`lib/services/history_database.dart`): Immutable log of completed, failed, and canceled downloads (`mornye_history.db`).
  - **`LibraryCollectionsDatabase`** (`lib/services/library_collections_database.dart`): User-curated playlists, loved items, and custom tags.

**File Storage:**
- **Android Storage Access Framework (SAF):** Document tree URI abstraction allowing secure SD card and internal storage writes (`lib/services/platform_bridge/bridge_saf.dart`).
- **Desktop Local Filesystem:** Direct access using standard OS file handles with unicode support (`cap-std` in Rust, `dart:io` in Flutter).
- **Temporary Cache:** Download staging buffers, artwork caches, and FFmpeg transient files located in OS temporary directories.

**Caching:**
- **Image & Cover Cache:** `flutter_cache_manager` and custom in-memory LRU cover cache (`lib/services/cover_cache_service.dart`).
- **Platform Lookup Cache:** In-memory metadata and query caching (`lib/services/platform_bridge/bridge_lookup_cache.dart`).

## Authentication & Identity

**Auth Provider:**
- **Decentralized Extension Authentication:**
  - Implementation: OAuth2 flows and webview/browser redirects captured via deep links (`app_links`).
  - Host Callbacks: `ExtensionAuthCallbacks.kt` on Android, `ExtensionCallbackParser.swift` on iOS.
  - Token Encryption: Stored securely in platform keychain/Keystore via `flutter_secure_storage`.

## Monitoring & Observability

**Error Tracking:**
- **Local Crash Logging:** In-app crash reporter and diagnostic dump (`lib/utils/logger.dart`, `lib/services/desktop_diagnostics.dart`).
- **No Third-Party Telemetry:** Zero external tracker SDKs (no Firebase, no Google Analytics, no Sentry) to preserve complete user privacy.

**Logs:**
- Unified `AppLogger` writing structured logs to memory buffers and optional local log files for diagnostics export.

## CI/CD & Deployment

**Hosting:**
- **GitHub Releases:** Automated release binary publishing for APKs, DMG packages, and Windows portable/setup installers (`.github/workflows/release.yml`).
- **Crowdin:** Community translation synchronization (`crowdin.yml`, `lib/l10n/arb/`).

**CI Pipeline:**
- **GitHub Actions:**
  - `.github/workflows/ci.yml`: Multi-platform test runner, static analysis, and code quality verification.
  - `.github/workflows/android.yml`: Split APK and universal APK generation with R8 shrinking and symbol extraction.
  - `.github/workflows/desktop.yml`: Windows MSVC and Linux package build matrix.
  - `.github/workflows/ios.yml`: Xcode archive and unsigned IPA packaging.

## Environment Configuration

**Required compile-time parameters:**
- `GIT_COMMIT`: Injected at build time (`--dart-define="GIT_COMMIT=$(git rev-parse --short=8 HEAD)"`).
- `MORNYE_RUST_ANDROID_ABIS`: Comma-separated ABIs for Android builds (`arm64-v8a`, `armeabi-v7a`, `x86_64`).

**Secrets Location:**
- Production Discord SDK encryption secrets supplied exclusively through GitHub Actions repository secrets; zero secrets stored in repository.

## Webhooks & Callbacks

**Incoming:**
- Custom URI scheme deep links (`mornye://auth/callback` or `vibescape://auth/callback`) dispatched through `app_links` to complete extension authorization.

**Outgoing:**
- None (fully offline-capable client).

---

*Integration audit: 2026-10-30*

