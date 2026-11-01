# Android audio exclusivity and bit-perfect strategy

This is the Android-specific audio design record for VibeSpace.

## Current codebase baseline

The root Flutter package already uses the name `vibespace`. Its current playback split, as declared in the root `pubspec.yaml`, is:

- Windows/Linux: `media_kit` / libmpv packages.
- Android/iOS: `audioplayers`.
- Android's `audioplayers_android` implementation is a local fork at `third_party/audioplayers_android`.

That local fork's README documents project-specific behaviour beyond upstream AudioPlayers: player-session effects using Android `DynamicsProcessing`, and direct USB / exclusive bit-perfect paths that bypass those effects. The README is evidence of an intended/implemented fork feature, not by itself proof that every device is obtaining bit-perfect output. Audit and test the native implementation before exposing a verified status in the UI.

## Do not collapse two different meanings of "exclusive"

VibeSpace should expose separate, precisely named capabilities.

### 1. Exclusive low-latency stream — Oboe / AAudio

Oboe is a C++ wrapper over AAudio on Android 8.1 / API 27 and later. It can request low-latency performance mode and exclusive sharing mode.

- Request `PerformanceMode::LowLatency`.
- Request `SharingMode::Exclusive`.
- Prefer the device's native sample rate and use a real-time data callback.
- Inspect the opened stream's actual sharing mode, performance mode, sample rate, burst size, xrun count and device route.
- Treat an exclusive request that opens as shared as a fallback, not as successful exclusive playback.

Android explicitly documents that an app may not receive exclusive MMAP access. Oboe/AAudio exclusive mode is primarily an endpoint/latency capability. It is not a bit-perfect guarantee: the application pipeline can still resample, change gain, apply EQ or alter samples before writing them.

API/reference reading:
- https://developer.android.com/games/sdk/oboe/low-latency-audio
- https://source.android.com/docs/core/audio/aaudio

### 2. Bit-perfect USB output — Android 14 / API 34+

Android 14 introduced preferred mixer attributes for USB audio devices. The public `AudioMixerAttributes` API can describe the format, channel mask, sample rate and mixer behaviour. The app can request `MIXER_BEHAVIOR_BIT_PERFECT` for a compatible USB route.

Important constraints:

- Preferred mixer attributes are only settable for USB devices.
- Bit-perfect mixer behaviour is optional, not guaranteed on every Android 14+ device.
- Vendor Audio HAL support is required; AOSP specifies support through the AIDL Audio HAL and the bit-perfect output flag on a routable dynamic mix port.
- Query the target USB device's supported mixer attributes before offering a format/mode.
- Apply the preferred attributes, then verify the actual active route/format/state; do not mark success merely because the request returned.
- In bit-perfect mode, the HAL must not apply volume scaling, sample-rate conversion, audio effects or DSP mixing. The DAC/hardware controls volume; software volume and DSP/effects must be disabled or bypassed for that path.
- Keep unsupported devices on a clearly reported shared/default route. Do not label Bluetooth, internal speakers or unsupported USB routes as bit-perfect.

API/reference reading:
- https://source.android.com/docs/core/audio/preferred-mixer-attr
- https://developer.android.com/reference/android/media/AudioMixerAttributes

### 3. Existing direct USB path

The local `third_party/audioplayers_android` fork README documents a direct USB / exclusive bit-perfect path. Audit this path first before building another engine:

1. Locate the exact Kotlin/Java/C++ implementation and lifecycle.
2. Confirm whether it uses Android's USB Host APIs and how it handles device permissions, detach/re-attach, alternate interfaces, clocking and endpoint formats.
3. Establish exactly which code path bypasses Android AudioTrack/framework mixing and which devices are supported.
4. Confirm how the decoder provides PCM/encoded data and how underruns, buffer sizes, sample-rate changes and track transitions are handled.
5. Verify that effects, ReplayGain, volume normalization, automix and EQ are bypassed when the path is active.
6. Capture the actual active DAC, negotiated sample rate, bit depth/encoding, channel count and stream state from runtime—not from selected settings.

Do not add a competing USB engine until this audit determines whether the existing implementation can be hardened and surfaced.

## Proposed VibeSpace Android modes

| UI mode | Implementation | What VibeSpace may claim |
| --- | --- | --- |
| Shared | Existing Android playback route | Android shared/system-managed playback |
| Exclusive Low Latency | Oboe/AAudio exclusive request, if actually granted | Exclusive stream only when the opened stream confirms it; otherwise show shared fallback |
| USB Bit-Perfect | Android 14+ preferred USB mixer attributes when vendor HAL supports BIT_PERFECT, or a separately verified supported direct-USB path | Bit-perfect only after route, format and processing bypass are verified |

Do not name Android modes "WASAPI Event" or "WASAPI Push". Those are Windows concepts.

## Runtime status contract

The Audio Control Center should show at least:

- Requested mode vs actual active mode.
- Active output device and route type (USB DAC / wired / Bluetooth / speaker).
- Android API level and relevant capability availability.
- Source format and actual negotiated output format.
- Sample-rate conversion status where it can be established.
- Effects / EQ / gain processing enabled or bypassed.
- Exclusive-sharing result for Oboe/AAudio.
- Preferred-mixer behaviour result for USB.
- Clear fallback reason.
- A verified bit-perfect indicator only when every required condition is proven by the active output path.

If the platform does not expose proof for a condition, label it "unverified" rather than inferring success.

## Recommended implementation sequence

1. Audit the existing forked `audioplayers_android` direct-USB implementation and the current Android playback deck.
2. Add a native capability probe for connected USB DACs and supported preferred mixer attributes on API 34+.
3. Add an Android-only native audio output coordinator that owns request, apply, rollback and route-change handling.
4. Integrate the coordinator with the existing Flutter playback state without introducing a second decoder/player unless the existing output path is technically incapable.
5. Add Oboe/AAudio only if a specific requirement—exclusive low-latency endpoint access or unsupported format/routing—cannot be met by the audited existing path.
6. Add runtime telemetry and tests using fake capability providers plus real-device instrumentation.
7. Validate across multiple Android vendors, Android API levels, USB DACs, sample rates and disconnect/reconnect cases.

## Test matrix

- Android 13 and below: no preferred mixer API; report capability unavailable and use a supported fallback.
- Android 14+ USB DAC with preferred mixer support but no BIT_PERFECT: allow only supported default/preferred formats; no bit-perfect badge.
- Android 14+ USB DAC with BIT_PERFECT HAL support: request supported formats, verify active mode, disable app-side processing/volume, and test PCM plus encoded formats only where supported.
- Android 14+ USB DAC without dynamic mix-port support: graceful shared/default fallback.
- Oboe stream requested exclusive but returned shared: report fallback truthfully.
- Route changes, USB detach/reattach, competing app audio, calls/notifications and playback interruptions.
- EQ/ReplayGain/normalization/automix transitions while an exclusive or bit-perfect mode is requested.

## Acceptance rule

A successful API request is not proof of exclusive or bit-perfect output. VibeSpace must report the active stream and hardware/route capabilities, preserve automatic fallback, and never make a stronger claim than its runtime evidence supports.
