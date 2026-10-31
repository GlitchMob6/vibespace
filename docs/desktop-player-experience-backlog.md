# Desktop Player Experience — Execution Backlog

Working branch: `ux/player-experience-quick-controls`

This backlog records the agreed desktop UX changes for VibeSpace. Keep the existing Flutter/Rust playback architecture and WASAPI runtime as the source of truth. Do not ship UI-only controls or infer runtime audio state from selected settings.

## 1. Audio Quick Settings

- [ ] Replace the Mornye desktop player-bar volume slider popover with a compact Windows Quick Settings-inspired Audio Quick Settings panel.
- [ ] Keep the panel compact and anchored to the player-bar volume button.
- [ ] Arrange controls in this order:
  1. Volume slider.
  2. Audio engine selector: Shared / Exclusive (Event) / Exclusive (Push), plus automatic fallback.
  3. One-row, three-column grid: Output Sample Rate / Output Sample Format / Channel Layout.
  4. Output device selector.
- [ ] Reuse existing `settingsProvider`, `WindowsAudioDeviceService`, endpoint enumeration, capability probing, and `windowsAudioStatus`; do not duplicate audio-engine state.
- [ ] Populate choices from the selected endpoint's probed capabilities where supported. Never imply that an unsupported format or setting is active.
- [ ] Keep the existing hardware-capability probe available without making the default flyout oversized.

## 2. Live Audio Stream Monitor — separate floating surface

- [ ] Reuse the existing live monitor data and presentation from Windows Audio Output settings.
- [ ] Present it as a distinct floating card/surface, visually separate from the Audio Quick Settings panel.
- [ ] Do not nest it inside the Audio Quick Settings panel or its scrollable content.
- [ ] Keep runtime telemetry honest: endpoint, actual mode, source format, output format, state, and bit-perfect reason must come from current runtime status.
- [ ] Show a Bit-perfect badge only when the runtime's verified `isBitPerfect` state is true.
- [ ] Decide/implement the exact trigger and dismiss behaviour during the UI execution step.

## 3. Fullscreen player experience

- [ ] Add an Expanded Preview mode that fills the VibeSpace content area and hides the app's top chrome.
- [ ] Add a True Fullscreen action from Expanded Preview, using the existing native desktop window fullscreen API.
- [ ] Add the first-level fullscreen/expand action to the persistent player bar; it opens Expanded Preview first.
- [ ] Allow Esc to step back one level: True Fullscreen → Expanded Preview → normal application view.
- [ ] Make fullscreen control visibility configurable under Settings → Appearance: Auto-hide / Always visible.
- [ ] For Auto-hide, expose a configurable delay (initial default proposed: 3 seconds); reveal controls on pointer movement.
- [ ] Keep controls available for keyboard-only and accessible-navigation users.

## 4. Navigation inputs

- [ ] Preserve existing keyboard shortcuts; do not remap or regress them.
- [ ] Keep the existing Escape handling priority for open menus/dialogs and text-field focus, then route back through the player/window/page layers in the correct order.
- [ ] Add mouse Button 4 → backward navigation and mouse Button 5 → forward navigation.
- [ ] Make mouse navigation use real in-app history and handle unavailable back/forward history safely.
- [ ] Avoid intercepting mouse buttons while text entry or another control legitimately owns the event.

## 5. Windows branding / icon

- [ ] Inspect the existing source logo and current `windows/runner/resources/app_icon.ico`.
- [ ] Correct transparent padding/cropping so the mark remains legible at taskbar and shortcut sizes.
- [ ] Generate a proper multi-resolution Windows ICO (including small and large sizes).
- [ ] Verify the runner resource, shortcut/installer icon, Start menu icon, and taskbar AppUserModelID grouping.
- [ ] Account for Windows icon cache when validating the updated build.

## 6. Settings-page visual polish

- [ ] Tighten the relationship between each uppercase section heading and its corresponding settings group/card so headings read as part of the section, not detached labels.
- [ ] Apply consistent spacing/alignment across Output Device, Audio Engine, and Output Format sections.

## Execution / verification rules

- Make changes in small, reviewable commits on this branch.
- Preserve the existing playback engine and current audio defaults unless explicitly agreed.
- Run formatting, targeted Flutter tests, relevant Windows build checks, and manual interaction checks where the environment permits.
- Report any checks that could not be run; do not claim a feature is verified until it has been tested on Windows hardware.
