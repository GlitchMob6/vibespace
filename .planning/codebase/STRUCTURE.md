# Codebase Structure

**Analysis Date:** 2026-10-30

## Directory Layout

```
d:/audiolab/Mornye/
├── android/            # Android platform host, foreground DownloadService, USB audio plugin
├── assets/             # Vector icons, branding artwork, and default font assets
├── docs/               # Architecture guides, component contracts, and specifications
│   └── architecture/   # System architecture deliverables and interactive dashboard
├── integration_test/   # Flutter end-to-end performance and integration tests
├── ios/                # iOS platform host, AppDelegate, WidgetKit extension, CoreBackend
├── lib/                # Flutter frontend Dart codebase
│   ├── constants/      # Static application metadata and service identifiers
│   ├── controllers/    # Shared UI interaction logic, selection mixins, metadata editors
│   ├── l10n/           # ARB localization files and generated locale helpers
│   ├── models/         # Immutable data models and json_serializable definitions
│   ├── providers/      # Riverpod state notifiers (Library, Player, Queue, Settings)
│   ├── routes/         # Root route definitions and transitions
│   ├── screens/        # Main application pages and settings sub-screens
│   ├── services/       # SQLite databases, audio player engines, FFmpeg, and IPC bridges
│   ├── theme/          # Material 3 tokens, dynamic palettes, motion, and styling
│   ├── utils/          # Helpers for file I/O, hashing, logging, and lyrics parsing
│   └── widgets/        # Reusable design-system components and slivers
├── linux/              # Linux desktop runner and D-Bus integration
├── patches/            # Upstream patch tracking files
├── rust_backend/       # High-performance native Rust core workspace
│   ├── crates/         # Multi-crate workspace modules (core, extensions, mobile, desktop, etc.)
│   └── vendor/         # Vendored platform compatibility patches (rustix, libusb1-sys)
├── scripts/            # Reproducible cross-platform packaging and build scripts
├── test/               # Flutter unit and widget tests (50+ test suites)
├── third_party/        # Vendored and customized packages (audio_service, audioplayers forks)
└── windows/            # Windows desktop runner, CMake build, and Inno Setup installer
```

## Directory Purposes

**`lib/providers/`:**
- Purpose: Application state management and reactive data streams.
- Contains: Riverpod `Notifier` and `StateNotifier` classes, partitioned with `part` files for complex state machines like the download queue and local library index.
- Key files: `playback_provider.dart`, `download_queue_provider.dart`, `local_library_provider.dart`, `track_provider.dart`, `settings_provider.dart`.

**`lib/services/`:**
- Purpose: Infrastructure, persistence, hardware abstraction, and platform communication.
- Contains: SQLite databases, audio engines, background workers, FFmpeg bindings.
- Key files: `library_database.dart`, `music_player_service.dart`, `media_kit_playback_deck.dart`, `platform_bridge.dart`, `app_state_database.dart`, `history_database.dart`.

**`rust_backend/crates/`:**
- Purpose: Core business logic, secure JavaScript extension sandboxing, network I/O, and audio analysis.
- Contains: Modular Rust crates with strict downward dependency hierarchies.
- Key files: `crates/extensions/src/runtime.rs`, `crates/core/src/tags.rs`, `crates/mobile/src/manager.rs`, `crates/desktop/src/lib.rs`.

**`third_party/`:**
- Purpose: Vendored libraries carrying custom patches necessary for high-fidelity audio playback.
- Key files: `third_party/audio_service` (modified background handler), `third_party/audioplayers_android` (direct stream routing), `third_party/mornye_discord` (IPC presence bridge).

## Key File Locations

**Entry Points:**
- `lib/main.dart`: Flutter mobile and desktop entry point.
- `android/app/src/main/kotlin/com/zarz/mornye/MainActivity.kt`: Android native application entry.
- `ios/Runner/AppDelegate.swift`: iOS native application entry.
- `windows/runner/main.cpp`: Windows native executable bootstrap.

**Configuration:**
- `pubspec.yaml`: Flutter dependencies and asset registrations.
- `rust_backend/Cargo.toml`: Rust workspace dependencies and optimizations.
- `.fvmrc`: Flutter SDK version constraint (`3.47.7`).
- `windows/CMakeLists.txt`: Desktop CMake compiler and link configuration.

**Core Logic:**
- `lib/services/music_player_service.dart`: Playback state machine, queue scheduling, AutoMix crossfade.
- `lib/providers/download_queue_provider.dart`: Multi-threaded download scheduler with native foreground worker handoff.
- `rust_backend/crates/extensions/src/manager.rs`: Community extension registry, lifecycle, and provider priority resolution.

**Testing:**
- `test/`: Flutter unit tests matching the structure of `lib/`.
- `integration_test/`: Performance benchmarks and end-to-end device drivers.
- `rust_backend/crates/*/tests/`: Rust crate unit tests.

## Naming Conventions

**Files:**
- Dart: `snake_case.dart` (e.g., `music_player_service.dart`, `track_detail_actions.dart`)
- Rust: `snake_case.rs` (e.g., `native_audio_analysis.rs`, `signed_session.rs`)
- Kotlin / Swift: `PascalCase.kt` / `PascalCase.swift` (e.g., `DownloadService.kt`, `CoreBackend.swift`)

**Directories:**
- Lowercase alphanumeric with underscores (e.g., `rust_backend`, `integration_test`, `third_party`).

## Where to Add New Code

**New Feature Screen:**
- Primary code: `lib/screens/<feature_name>_screen.dart` (split subcomponents into `<feature_name>_*.dart`)
- Navigation: Add route in `lib/app.dart` or open via `slidePageRoute` in parent tab.
- Tests: `test/<feature_name>_screen_test.dart`

**New Audio / Domain Service:**
- Implementation: `lib/services/<service_name>_service.dart`
- Interface / Deck: Inherit from `PlaybackDeck` in `lib/services/playback_deck.dart` if hardware-facing.
- Provider: Wrap in Riverpod notifier inside `lib/providers/`.

**New Platform Bridge API:**
- Dart: Add method to `PlatformBridge` in `lib/services/platform_bridge.dart`.
- Android: Add method to `nativeBackendMethods` in `MainActivity.kt` and handle in matching `MainActivity*Calls.kt`.
- iOS: Add method to `osMethods` in `AppDelegate.swift` or `CoreBackend.swift`.
- Desktop: Add C-ABI export in `rust_backend/crates/desktop/src/lib.rs` and Dart FFI binding in `rust_ffi_backend.dart`.

## Special Directories

**`.planning/`:**
- Purpose: GSD workflow state, codebase maps, research notes, and plans.
- Generated: Semi-automated by GSD workflows.
- Committed: Yes.

**`build/`:**
- Purpose: Output directory for compiled Dart AOT binaries, Android APKs, and Windows `.exe` bundles.
- Generated: Yes.
- Committed: No (strictly gitignored).

---

*Structure analysis: 2026-10-30*

