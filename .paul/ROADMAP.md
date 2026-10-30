# Roadmap: Mornye WASAPI Integration

## Overview

Add native Windows WASAPI audio output (shared and exclusive modes) to Mornye's existing cross-platform playback architecture, using media_kit/libmpv as the Windows audio backend. The integration preserves all existing playback paths and adds Windows-specific output mode selection with accurate status reporting.

## Current Milestone

**v1.0 WASAPI Integration** (v5.2.7)
Status: Not started
Phases: 0 of 4 complete

## Phases

| Phase | Name | Plans | Status | Completed |
|-------|------|-------|--------|-----------|
| 1 | Windows WASAPI Backend Foundation | 3 | Not started | - |
| 2 | Exclusive Mode Support & Format Negotiation | 3 | Not started | - |
| 3 | UI Integration & Settings | 2 | Not started | - |
| 4 | Testing, Verification & Documentation | 3 | Not started | - |

## Phase Details

### Phase 1: Windows WASAPI Backend Foundation

**Goal:** Extend the existing MediaKitPlaybackDeck to support configurable exclusive output mode on Windows, with shared mode as the default and reliable fallback.
**Depends on:** Nothing (first phase)
**Research:** Likely (mpv audio-exclusive property behavior, device format negotiation)

**Scope:**
- Add `exclusiveOutput` parameter to `MediaKitPlaybackDeck` constructor (already exists but always false)
- Wire `exclusiveOutput` from `PlaybackDependencies.createDeck` based on platform and settings
- Implement `configureOutput()` to set mpv's `audio-exclusive` property when enabled
- Add Windows-specific playback mode status reporting (shared vs exclusive)

**Plans:**
- [ ] 01-01: Extend MediaKitPlaybackDeck with exclusive output control
- [ ] 01-02: Wire exclusiveOutput from PlaybackDependencies.createDeck
- [ ] 01-03: Add Windows playback mode status reporting

### Phase 2: Exclusive Mode Support & Format Negotiation

**Goal:** Implement robust exclusive mode initialization with format negotiation, graceful fallback to shared mode, and accurate mode reporting.
**Depends on:** Phase 1
**Research:** Likely (WASAPI format support matrix, mpv behavior on format mismatch, device contention)

**Scope:**
- Detect exclusive mode availability before/after initialization
- Negotiate supported sample formats, rates, and channel layouts with the device
- Handle exclusive mode failures (contention, unsupported format, disabled) explicitly
- Never silently fall back — report actual mode to user
- Preserve source audio precision where device supports it

**Plans:**
- [ ] 02-01: Implement format negotiation and device capability detection
- [ ] 02-02: Handle exclusive mode failures with explicit fallback
- [ ] 02-03: Add diagnostic logging for format negotiation

### Phase 3: UI Integration & Settings

**Goal:** Expose Windows output mode selection in the existing playback settings page, following Mornye's settings conventions.
**Depends on:** Phase 2
**Research:** Unlikely (existing settings patterns)

**Scope:**
- Add Windows-specific settings section to playback settings (conditional on Windows)
- Add `windowsOutputMode` setting (shared/exclusive/auto)
- Add `windowsOutputDevice` setting for device selection
- Display active mode and device in settings with actionable feedback

**Plans:**
- [ ] 03-01: Add Windows output mode settings to AppSettings and SettingsProvider
- [ ] 03-02: Add Windows settings section to PlaybackSettingsPage

### Phase 4: Testing, Verification & Documentation

**Goal:** Verify the implementation works correctly across scenarios and document behavior.
**Depends on:** Phase 3
**Research:** Unlikely (project testing conventions)

**Scope:**
- Unit tests for format negotiation and fallback logic
- Integration tests for backend selection and mode reporting
- Manual verification on Windows with various audio devices
- Update CHANGELOG and any relevant docs

**Plans:**
- [ ] 04-01: Add unit and integration tests for WASAPI backend
- [ ] 04-02: Manual verification on Windows hardware
- [ ] 04-03: Update documentation and CHANGELOG

---
*Roadmap created: 2026-10-29*
