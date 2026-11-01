# Android build rebranding

This document tracks the Android-only VibeSpace rebrand on the `android` branch.

## Identity

| Item | Value | Notes |
| --- | --- | --- |
| User-facing app label | `VibeSpace` | Already set in the Android manifest on the base branch. |
| Android application ID | `com.zarz.vibespace` | Updated on this branch in `android/app/build.gradle.kts`. |
| Gradle/Kotlin namespace | `com.zarz.mornye` | Deliberately retained as an internal namespace for now. |
| Flutter package name | `vibespace` | Already set in the root `pubspec.yaml`. |
| Primary callback scheme | `vibespace://` | Already registered in the Android manifest. |
| Legacy callback scheme | `mornye://` | Retain during transition so previously issued extension/OAuth callback URIs do not silently stop resolving. |

## Why the namespace is temporarily retained

The Gradle `namespace` determines the generated Android `R` and `BuildConfig` package and is referenced by native Kotlin/Java source layout and generated bindings. Changing it safely requires auditing every Android native source file, generated Rust/Kotlin binding, manifest component, and platform-channel contract. The first rebrand pass therefore changes the installed Android identity (`applicationId`) while avoiding a speculative bulk package move.

The legacy package prefix in internal MethodChannel names is also an implementation contract, not user-facing branding. Rename those only after updating both Kotlin and Dart endpoints together and covering them with integration tests.

## Installation and data migration warning

Changing the application ID from `com.zarz.mornye` to `com.zarz.vibespace` creates a different Android package identity. Android will not treat a VibeSpace APK using the new ID as an in-place update of an already installed `com.zarz.mornye` app. Existing users may see both apps installed, and app-private data does not automatically migrate between them.

Before any public release, decide whether this is intentionally a fresh VibeSpace installation or whether an explicit export/import migration flow is needed. Do not promise automatic preservation of databases, SAF grants, credentials, downloads, or playback state.

## Branding checklist

- [x] Android application ID changed to `com.zarz.vibespace`.
- [x] Gradle root project named `VibeSpace`.
- [x] Android user-visible manifest label already reads `VibeSpace`.
- [x] New `vibespace://` callback scheme already registered.
- [x] Legacy `mornye://` callbacks retained for compatibility during migration.
- [ ] Audit/replace Android launcher, adaptive and monochrome icon resources with the approved VibeSpace assets.
- [ ] Audit Android notification, widget, shortcut and share-sheet labels.
- [ ] Audit package-qualified native component names and Kotlin namespace before deciding whether to migrate them.
- [ ] Build and install on a real Android device; verify deep links, media service, widgets, USB routing and app-data behaviour.
- [ ] Confirm final package identity and migration policy before Play Store publication.

## Scope boundary

This branch is for Android build identity, Android-specific rebranding and Android audio work. Do not rename Windows product resources, alter the Windows WASAPI implementation, or bulk-replace shared upstream identifiers that are still part of a native compatibility contract.
