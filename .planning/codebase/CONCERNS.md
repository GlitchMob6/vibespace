# Codebase Concerns

**Analysis Date:** 2026-10-30

## Tech Debt

**Dual Audio Deck Engine Maintenance:**
- Issue: Desktop platforms (Windows, Linux) use `libmpv` through `media_kit`, whereas mobile platforms (Android, iOS) use `audioplayers` with native forks.
- Files: `lib/services/media_kit_playback_deck.dart`, `lib/services/music_playback_deck.dart`, `lib/services/playback_deck.dart`
- Impact: Features such as equalizer filters, AutoMix crossfade, and pitch adjustment must be implemented and tested twice.
- Fix approach: Gradually unify desktop and mobile audio engines or abstract all audio DSP into the Rust core backend.

**Android IPC Large Payload Workaround:**
- Issue: Android's Binder IPC has a hard 1 MB transaction buffer limit. Transferring large library scans over MethodChannels can trigger `TransactionTooLargeException`.
- Files: `lib/services/platform_bridge.dart`, `android/app/src/main/kotlin/com/zarz/mornye/MainActivity.kt`
- Impact: Requires custom disk-spooling logic (`bridgeJsonResult`) for payloads exceeding 256 KiB.
- Fix approach: Maintain existing file-spooling mechanism or transition library scanning directly into the native SQLite database without serializing over the channel.

## Known Bugs & Environmental Hurdles

**Windows Build Missing ATL Header (`atlbase.h`):**
- Symptoms: `C1083: Cannot open include file: 'atlbase.h': No such file or directory` when compiling `flutter_local_notifications_windows`.
- Files: `windows/flutter/ephemeral/.plugin_symlinks/flutter_local_notifications_windows/`
- Trigger: Building on Windows systems where Visual Studio Build Tools were installed without the optional "C++ ATL" component.
- Workaround: Install `Microsoft.VisualStudio.Component.VC.ATL` via the Visual Studio Installer.

**Windows Symlink Privilege Restriction:**
- Symptoms: `FileSystemException: Cannot create link ... OS Error: A required privilege is not held by the client (errno = 1314)`.
- Files: `.fvm/`, `.dart_tool/`
- Trigger: Running Flutter commands without Windows Developer Mode enabled.
- Workaround: Enable Windows Developer Mode (`ms-settings:developers`) or run terminal with elevated privileges.

## Security Considerations

**Extension JavaScript Execution:**
- Risk: Community extensions could attempt to execute arbitrary code or exfiltrate private user listening history.
- Files: `rust_backend/crates/extensions/src/runtime.rs`, `rust_backend/crates/extensions/src/host.rs`
- Current mitigation: Extensions run inside `rquickjs` with strict resource limits (heap memory, execution timeouts). Extensions have zero access to system shell or raw sockets; all I/O is mediated by Rust host functions.
- Recommendations: Continue restricting host capabilities and perform runtime validation of extension manifests.

**Local File Path Traversal:**
- Risk: Malicious filenames in downloaded audio tags could attempt directory traversal (`../../`).
- Files: `rust_backend/crates/core/src/filename.rs`, `lib/services/platform_bridge/bridge_saf.dart`
- Current mitigation: Filenames are sanitized, stripped of path separators, and clamped to safe ASCII/Unicode subsets.

## Performance Bottlenecks

**Large Library Scan (10,000+ Tracks):**
- Problem: Extracting ID3/Vorbis tags and computing ReplayGain across massive storage trees can saturate CPU and I/O.
- Files: `rust_backend/crates/core/src/tags.rs`, `lib/providers/local_library_provider.dart`
- Cause: Reading tag headers for thousands of files sequentially.
- Improvement path: Parallelize directory traversal in Rust using multi-threaded worker pools and batch SQLite inserts.

## Fragile Areas

**Pinned Dependencies with Binary Compatibility Requirements:**
- Files: `pubspec.yaml`, `rust_backend/Cargo.toml`
- Why fragile:
  - `flutter_secure_storage` is pinned to `10.3.4` because v11 drops legacy Android encryption keys.
  - `desktop_drop` is pinned to `0.8.4` due to upstream `cross_file` conflicts.
  - `connectivity_plus` is pinned to `^7.3.1` due to Linux `dbus` version mismatches.
- Safe modification: Never run blind `flutter pub upgrade` or `cargo update` without testing across all four supported operating systems.

## Test Coverage Gaps

**Hardware DAC & USB Bit-Perfect Audio:**
- What's not tested: Real hardware USB DAC sample-rate switching and Direct DSD playback.
- Files: `android/app/src/main/kotlin/com/zarz/mornye/UsbBitPerfectPlugin.kt`
- Risk: Subtle audio artifacts or device-specific USB driver incompatibilities.
- Priority: Medium (requires physical test devices with external USB DACs).

---

*Concerns audit: 2026-10-30*

