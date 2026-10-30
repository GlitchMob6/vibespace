# Technology Stack

**Analysis Date:** 2026-10-30

## Languages

**Primary:**
- **Dart** (SDK `^3.10.0`, bundled with Flutter SDK 3.47.7): `lib/` (UI, state management, controllers, services, models)
- **Rust** (Edition 2024, `rust-version = "1.99.0"`): `rust_backend/` (audio analysis, metadata matching, tags, network transport, extension JavaScript sandbox)

**Secondary:**
- **Kotlin** (1.9+ / Gradle Kotlin DSL `build.gradle.kts`): `android/` (Android platform bridge, foreground `DownloadService`, SAF handling, USB PCM bit-perfect playback)
- **Swift** (5.9+): `ios/` (`AppDelegate.swift`, `CoreBackend.swift`, `PlayerWidgetBridge.swift`, WidgetKit extension in `ios/PlayerWidget/`)
- **C++ / CMake** (C++17, CMake 3.14+): `windows/` and `linux/` (Windows runner, custom plugin shims, MSVC build pipeline)
- **JavaScript (ES2020)**: `rust_backend/crates/extensions/src/` (rquickjs runtime executing community metadata and download provider scripts)

## Runtime

**Environment:**
- **Flutter Framework:** Pinned to `3.47.7` in `.fvmrc`
- **Dart Runtime:** `3.13.5` (bundled with Flutter 3.47.7)
- **Rust Toolchain:** Pinned via `rust_backend/rust-toolchain.toml` (`1.99.0-x86_64-pc-windows-msvc` / host target)
- **JavaScript Engine:** `rquickjs` v0.14.0 (QuickJS embedded engine with Rust bindings)
- **Audio Decoding / Playback Core:**
  - Desktop (Windows/Linux): `media_kit` (libmpv engine via `media_kit_libs_windows_audio` 1.0.9)
  - Mobile & Apple (Android, iOS, macOS): `audioplayers` 6.8.1 with vendored forks in `third_party/`
  - Audio Conversion / Tagging: FFmpeg / FFprobe (via `ffmpeg_kit_flutter_new_audio` 2.5.7 and standalone desktop CLI binaries)

**Package Manager:**
- **Flutter / Dart:** `pub` (Lockfile: `pubspec.lock` present)
- **Rust:** `cargo` (Lockfile: `rust_backend/Cargo.lock` present)
- **Version Management:** `FVM` (Flutter Version Management, `.fvmrc` present)

## Frameworks

**Core:**
- **Flutter SDK:** Cross-platform GUI framework rendering via Impeller / Skia
- **Flutter Riverpod** (`^3.4.2`): Compile-safe reactive state management with CodeGen & Notifiers
- **GoRouter** (`^18.0.2`): Declarative root navigation (`/`, `/setup`, `/tutorial`) with nested tab navigators
- **UniFFI** (`0.32.2`): Foreign Function Interface code generator binding Rust to Kotlin (`com.mornye.backend`) and Swift (`MornyeBackend`)

**Testing:**
- **`flutter_test`** / **`integration_test`**: Flutter unit, widget, and end-to-end integration drivers
- **`cargo test`**: Rust crate unit and integration testing suite
- **`JUnit / Kotlin Test`**: Android native routing and SAF tests

**Build/Dev:**
- **`build_runner`** (`2.16.2`): Code generation for `json_serializable`
- **Inno Setup 6**: Windows packaging and installer compilation (`windows/installer/mornye.iss`)
- **CMake**: Native build orchestration for desktop Windows and Linux runners

## Key Dependencies

**Critical:**
- `flutter_riverpod` (`^3.4.2`): Core state backbone across library, player, queue, and settings (`lib/providers/`)
- `rquickjs` (`=0.14.0`): Sandboxed JavaScript execution engine for community extensions (`rust_backend/crates/extensions/`)
- `media_kit` (`^1.2.6`): High-performance MPV-backed media playback for Windows and Linux (`lib/services/media_kit_playback_deck.dart`)
- `audio_service` (`third_party/audio_service`): Background audio playback coordination and lockscreen transport integration
- `sqflite` (`^2.4.4+1`) & `sqflite_common_ffi` (`^2.4.4`): Local relational storage for tracks, albums, artists, history, and app state (`lib/services/library_database.dart`)
- `rusqlite` (`=0.40.2`): Bundled modern SQLite engine for the Rust desktop backend

**Infrastructure:**
- `tokio` (`=1.53.2`): Multi-threaded asynchronous runtime for Rust network and background tasks
- `hyper-util` (`=0.1.21`) & `rustls` (`0.23`): High-performance, memory-safe HTTP/1.1 and HTTP/2 network transport
- `shared_preferences` (`^2.5.6`): High-level persistent key-value configuration storage
- `flutter_secure_storage` (`10.3.4`): Secure credential and token storage with platform keystore integration
- `smtc_windows` (`^1.1.0`): Windows System Media Transport Controls integration
- `dbus` (`^0.7.15`): Linux MPRIS media control interface

## Configuration

**Environment:**
- Flutter compile-time definitions passed via `--dart-define`:
  - `GIT_COMMIT`: Short SHA commit hash injected into app build metadata (`lib/constants/app_info.dart`)
  - `MORNYE_DISCORD_SDK`: Toggle for Discord Rich Presence staging
- Rust toolchain options configured in `rust_backend/rust-toolchain.toml` and workspace cargo profile (`profile.release.lto = "thin"`).

**Build:**
- `pubspec.yaml`: Dart dependencies, assets, fonts, and dependency overrides
- `rust_backend/Cargo.toml`: Multi-crate workspace declaration and patch table (`vendor/rustix-1.1.5`, `vendor/libusb1-sys-0.7.0`, `vendor/cap-primitives-4.0.3`)
- `android/app/build.gradle.kts`: Android SDK versions, NDK configuration, and Rust library staging
- `windows/CMakeLists.txt`: Windows executable target compilation and binary asset copying

## Platform Requirements

**Development:**
- Windows 10/11 64-bit (or macOS / Linux)
- Flutter SDK `3.47.7` via FVM
- Rust `1.99.0` with `x86_64-pc-windows-msvc` target
- Visual Studio 2019/2022 C++ Build Tools with ATL component
- Git

**Production:**
- **Android:** Android 7.0+ (API level 24 to 35); ARM64-v8a, armeabi-v7a, x86_64
- **iOS:** iOS 14.0+ (iPhone, iPad)
- **Windows:** Windows 10 / 11 64-bit (x64 / ARM64)
- **Linux:** Modern 64-bit distributions with GTK3, D-Bus, and libmpv

---

*Stack analysis: 2026-10-30*

