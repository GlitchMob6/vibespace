# Vibescape

<p align="center">
  <strong>A music player shaped around the listening experience.</strong>
  <br />
  An independently maintained, desktop-focused derivative of the open-source <a href="https://github.com/mornyeapp/Mornye">Mornye</a> project.
</p>

<p align="center">
  <a href="https://github.com/GlitchMob6/vibespace">Source</a>
  ·
  <a href="https://github.com/GlitchMob6/vibespace/releases">Releases</a>
  ·
  <a href="https://github.com/GlitchMob6/vibespace/issues">Issues</a>
  ·
  <a href="https://github.com/mornyeapp/Mornye">Mornye upstream</a>
</p>

> **Development status:** Vibescape is actively being developed. Windows playback and WASAPI output are being hardened across audio devices and driver configurations. Treat current builds as development builds until a stable release is published.

## About

Vibescape is a separately branded continuation of the Mornye codebase, with a particular focus on the desktop listening experience and Windows audio output.

The project keeps the existing Flutter/Dart application and Rust backend foundations while developing a dedicated Windows experience. It is maintained independently from Mornye; it is not an official Mornye release and is not affiliated with or endorsed by the upstream maintainers.

## What it includes

The repository builds on capabilities present in the Mornye codebase and develops them for Vibescape:

- **Music library and playback** — browse and play local music, organize tracks into a library, and manage playback queues and playlists.
- **Metadata and extensions** — use the extension-based provider architecture for supported metadata, lyrics and download integrations.
- **Lyrics** — display synchronized lyrics when supported by the file or an enabled provider.
- **Playback tools** — equalizer, volume normalization and ReplayGain-related functionality available in the application.
- **Network music sources** — support in the codebase for SMB, WebDAV, HTTP/HTTPS and Subsonic/OpenSubsonic sources. Availability can vary by platform.
- **Desktop foundation** — Flutter UI with a Rust backend and native platform integrations.

### Windows audio: WASAPI

Windows audio output is a central area of Vibescape development. The Windows playback path uses the existing `media_kit` / `libmpv` architecture and MPV's WASAPI audio output.

The implementation is designed to support:

| Output mode | Intended behaviour |
| --- | --- |
| **WASAPI Shared** | Plays through the Windows shared audio engine, allowing other applications to share the endpoint. |
| **WASAPI Exclusive (Event)** | Requests exclusive endpoint access with event-driven buffer handling. |
| **WASAPI Exclusive (Push)** | Requests exclusive endpoint access with push/timer-driven buffer handling, where supported. |

The Windows audio work also includes endpoint discovery, device selection, format negotiation, runtime status reporting and recovery/fallback handling.

**Important:** Available modes and formats depend on the Windows endpoint, driver and bundled MPV build. Selecting an exclusive or “bit-perfect” option does not by itself prove that the active stream is exclusive or bit-perfect. Vibescape should report the mode and format actually negotiated at runtime. Compatibility and playback lifecycle stability are still being validated across hardware.

## Platform focus

The repository contains platform projects for Windows, Android, iOS, Linux and macOS. Vibescape's current development focus is the Windows desktop experience. Feature parity, build readiness and runtime behaviour are not guaranteed to be identical on every platform.

Windows-specific WASAPI functionality applies only to Windows audio output.

## Downloads

There are no published Vibescape release binaries at the time of writing. When releases are ready, they will be published on the [GitHub Releases page](https://github.com/GlitchMob6/vibespace/releases).

Until then, the project can be built from source by developers with the required toolchain.

## Build from source (Windows)

### Requirements

- Windows with the Visual Studio C++ build tools (MSVC).
- Flutter **3.47.7**, pinned in [`.fvmrc`](.fvmrc).
- [FVM](https://fvm.app/) to install and use the pinned Flutter SDK (recommended).
- Rust **1.99.0**, pinned in [`rust_backend/rust-toolchain.toml`](rust_backend/rust-toolchain.toml).
- Git and PowerShell.

### Build

Run these commands from the repository root:

```powershell
# Install the repository-pinned Flutter SDK.
fvm install

# Apply the repository's Flutter SDK preparation step.
fvm dart scripts/prepare_flutter_sdk.dart

# Resolve Dart/Flutter dependencies.
fvm flutter pub get

# Build and stage the native Rust desktop backend.
pwsh scripts/build_rust_backend_windows.ps1

# Build the Windows Release application.
fvm flutter build windows --release
```

The Windows build expects the Rust desktop library to be staged before CMake configures the application. The build script selects the host Windows architecture by default; see its help and source for the ARM64 target option.

The generated application bundle is produced under:

```text
build/windows/x64/runner/Release/
```

The exact output architecture directory depends on the target used to build.

For the full development workflow and platform-specific requirements, see [CONTRIBUTING.md](CONTRIBUTING.md). That guide is inherited from the upstream codebase and may still use upstream project terminology.

## Repository map

| Path | Purpose |
| --- | --- |
| `lib/` | Flutter UI, state management, playback orchestration and platform services |
| `rust_backend/` | Rust backend, native bindings and desktop functionality |
| `windows/` | Windows runner, native integration and packaging configuration |
| `android/`, `ios/` | Mobile platform projects and bridges |
| `linux/`, `macos/` | Desktop platform projects |
| `test/` | Unit and widget tests |
| `integration_test/` | Integration and device-level tests |
| `third_party/` | Vendored or patched dependencies |
| `scripts/` | Build, packaging and maintenance scripts |
| `.paul/`, `.planning/` | Project planning and engineering notes |

## Project relationship and attribution

Vibescape is a downstream derivative of [Mornye](https://github.com/mornyeapp/Mornye), originally created and maintained by **zarzet**. The upstream project provides the codebase and application foundations on which Vibescape is built.

Vibescape adds its own branding and independently maintained changes, including Windows-focused audio work. It is not the official Mornye application, and no affiliation, endorsement or support by the Mornye maintainers is implied.

Please visit and support the original project:

- [Mornye source repository](https://github.com/mornyeapp/Mornye)
- [Mornye project website](https://mornye.com)

## Contributing

Bug reports, focused fixes, documentation improvements and testing feedback are welcome.

Before opening an issue or pull request:

1. Search existing issues to avoid duplicates.
2. Include the operating system, audio endpoint, output mode and relevant logs for playback problems.
3. Keep pull requests focused and explain how changes were tested.
4. Never commit API keys, credentials, signing material, downloaded music or generated build artifacts.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the inherited development workflow and toolchain details. Please note that some instructions may refer to Mornye and should be interpreted in the context of this derivative repository.

## Licensing

This repository retains the upstream **GNU Lesser General Public License v3.0 only (LGPL-3.0-only)** licensing files. See [`LICENSE`](LICENSE), [`COPYING`](COPYING) and [`NOTICE`](NOTICE) for the applicable terms and upstream notice.

Third-party components keep their own copyright and licence terms. Their notices are maintained in the relevant component directories and licence folders. Do not assume that every bundled dependency is licensed under the same terms.

When modifying or redistributing Vibescape, preserve the required copyright notices and comply with the applicable licence obligations, including source and relinking requirements where they apply.

---

<p align="center">
  <strong>Vibescape</strong><br />
  Built on Mornye. Maintained independently.
</p>
