# Mornye WASAPI Integration

## What This Is

A Windows WASAPI audio output backend integration for Mornye, an extension-driven music metadata and downloads application with a built-in audiophile-grade player. This integration adds native Windows audio output using WASAPI (Windows Audio Session API) through libmpv/media_kit, supporting both shared and exclusive modes where the architecture permits, while preserving the existing playback backend as a fallback.

## Core Value

Windows users get native bit-transparent audio output through WASAPI exclusive mode when hardware supports it, with shared-mode as a reliable fallback, integrated into Mornye's existing cross-platform playback architecture without disrupting Android, iOS, macOS, or Linux playback paths.

## Current State

| Attribute | Value |
|-----------|-------|
| Type | Application |
| Version | 5.2.6+165 |
| Status | Production |
| Last Updated | 2026-10-29 |

## Requirements

### Core Features

- WASAPI shared-mode audio output on Windows through libmpv/media_kit
- WASAPI exclusive-mode audio output where device and format permit
- Accurate reporting of active output mode (shared vs exclusive) to the user
- Graceful fallback when exclusive mode is unavailable (device contention, unsupported format, disabled)
- Format negotiation preserving source sample rate, bit depth, and channel layout where possible
- No silent mode switching — never claim exclusive when shared is active
- Preserve existing playback backend (audioplayers on mobile, media_kit on Linux) as fallback
- Cross-platform regression prevention

### Validated (Shipped)

- [x] media_kit/libmpv playback on Windows (shared mode)
- [x] audioplayers backend on Android, iOS, macOS
- [x] USB bit-perfect and AAudio exclusive on Android
- [x] Equalizer, ReplayGain normalization, AutoMix
- [x] Playback queue, session restore, gapless via AutoMix

### Active (In Progress)

- [ ] Windows WASAPI exclusive mode support through media_kit/libmpv

### Planned (Next)

- [ ] Windows device selection UI in playback settings
- [ ] Shared/exclusive mode toggle with clear availability feedback
- [ ] Format negotiation logging and diagnostics
- [ ] Device change handling and recovery

### Out of Scope

- WASAPI loopback recording (this is playback only)
- Direct implementation of WASAPI COM interfaces (use media_kit/libmpv)
- Kernel streaming (KS) or ASIO support
- System-wide audio settings changes

## Constraints

### Technical Constraints

- Windows-only integration; must not affect Android, iOS, macOS, Linux
- Uses existing media_kit/libmpv abstraction — cannot directly call WASAPI COM
- media_kit's `audio-exclusive` property controls exclusive mode via mpv
- mpv's Windows audio output uses WASAPI; exclusive mode requires device format support
- Exclusive mode can fail due to: device contention, unsupported format, disabled in Windows settings
- Must integrate with existing `PlaybackDeck` abstraction and `MusicPlayerHandler`
- Existing settings: `usbBitPerfect`, `usbDirect`, `dapExclusive` are Android-only
- Settings provider and UI conventions must be followed
- No `unsafe_code` in Rust workspace (deny policy)

### Business Constraints

- Preserve existing user settings and behavior
- No breaking changes to playback on other platforms
- Follow existing codebase conventions and architecture
- Minimal UI changes — only where settings surface exists

## Key Decisions

| Decision | Rationale | Date | Status |
|----------|-----------|------|--------|
| Use media_kit/libmpv for Windows audio | Already used on Windows/Linux; provides WASAPI via mpv | 2026-10-29 | Active |
| Extend existing `MediaKitPlaybackDeck` with exclusiveOutput flag | Reuses existing deck abstraction; minimal change | 2026-10-29 | Planned |
| Add Windows-specific settings under existing playback settings | Follows existing settings organization | 2026-10-29 | Planned |
| Report actual negotiated mode via `UsbAudioStatus`-like mechanism | Consistent with Android USB status reporting | 2026-10-29 | Planned |

## Success Metrics

| Met | Target | Current | Status |
|-----|--------|---------|--------|
| Windows build succeeds | Yes | Yes (shared mode) | On track |
| Exclusive mode initializes when available | Yes | Not implemented | Not started |
| Shared mode fallback works | Yes | Works (current) | Achieved |
| Mode reported accurately | 100% | N/A | Not started |
| No resource leaks on stop/restart | 0 leaks | N/A | Not started |
| Existing tests pass | 100% | Yes | Achieved |

## Tech Stack / Tools

| Layer | Technology | Notes |
|-------|------------|-------|
| Framework | Flutter 3.10+ (pinned via FVM) | Cross-platform UI |
| State | flutter_riverpod | Reactive state management |
| Windows Audio | media_kit + libmpv (WASAPI) | Already in use |
| Rust Backend | Rust 1.99 (workspace) | Core logic, FFI to Dart |
| Build | CMake + Ninja | Windows native |
| Audio Engine | mpv via media_kit | Handles WASAPI |
| Settings | shared_preferences + JSON | Persisted AppSettings |

---
*Created: 2026-10-29*
