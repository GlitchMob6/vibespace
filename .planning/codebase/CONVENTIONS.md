# Coding Conventions

**Analysis Date:** 2026-10-30

## Naming Patterns

**Files:**
- Dart files strictly use `snake_case.dart`.
- Part files append the sub-domain after an underscore (e.g., `download_queue_provider_native_worker.dart`, `platform_bridge/bridge_saf.dart`).
- Data model generator outputs append `.g.dart` (e.g., `settings.g.dart`, `track.g.dart`).

**Classes & Types:**
- `PascalCase` for all classes, enums, typedefs, and mixins (e.g., `MusicPlayerHandler`, `PlaybackDeck`, `DownloadItem`, `SelectionModeMixin`).
- Private classes prefix an underscore `_PascalCase` (e.g., `_TabNavigator`).

**Functions & Methods:**
- `camelCase` for methods and standalone functions (e.g., `playTrackList`, `ensureInitialized`, `resolveSource`).
- Private methods prefix an underscore (e.g., `_startResolvedSource`, `_processQueue`).

**Variables & Constants:**
- Fields and local variables use `camelCase`.
- Static top-level constants and loggers use `camelCase` or `lowerCamelCase` with an underscore if private (e.g., `final _log = AppLogger('PlatformBridge')`).

## Code Style

**Formatting:**
- Dart: `dart format` with standard 80-character line limit.
- Rust: `rustfmt` with 100-character line limit and 2024 edition styling.
- Kotlin / Swift: Standard official style guides.

**Linting:**
- Dart: Configured in `analysis_options.yaml`. Strict rules include `avoid_print`, `unawaited_futures`, `curly_braces_in_flow_control_structures`, and `prefer_const_constructors`.
- Rust: Denies `unsafe_code` at the workspace level (`[workspace.lints.rust] unsafe_code = "deny"`).
- Automated Design System Linting: `test/design_system_test.dart` verifies that all `IconButton` instances have tooltips and forbids ad-hoc modal sheets.

## Import Organization

**Order:**
1. Dart core SDK imports (`dart:async`, `dart:io`, `dart:math`, `dart:ffi`).
2. Flutter framework imports (`package:flutter/...`).
3. External package imports (`package:flutter_riverpod/...`, `package:media_kit/...`).
4. Internal project imports (`package:vibescape/...` or `package:mornye/...`).
5. Relative imports / `part` directives.

**Path Aliases:**
- Standard absolute package imports (`package:vibescape/...`) are preferred across all modules; relative paths are reserved for `part` files.

## Error Handling

**Patterns:**
- **No Uncaught Exceptions:** All platform channel and I/O calls are wrapped in `try / catch` blocks.
- **Fail-Safe Fallbacks:** Downloader errors trigger automatic failover to the next available provider in `ProviderPriority`.
- **Typed Error Classes:** Domain errors use dedicated exception classes (e.g., `UsbOutputUnavailable`, `ExtensionError`).
- **User-Facing Alerts:** Surface non-fatal errors via `AppSnackBar` or retryable UI indicators rather than modal crashes.

## Logging

**Framework:**
- Structured `AppLogger` (`lib/utils/logger.dart`) wrapping `logger: ^2.7.0`.

**Patterns:**
- Always instantiate a file-level logger with the component tag: `final _log = AppLogger('SubsystemName');`.
- Log levels: `_log.d()` for debug tracing, `_log.i()` for state changes, `_log.w()` for recoverable issues, `_log.e()` for failures with stack traces.
- `print()` is strictly forbidden in production code.

## Comments

**When to Comment:**
- Document public APIs, non-obvious performance trade-offs, and platform-specific workarounds (e.g., why a specific package version is pinned or why a symlink is required).
- Use `///` docstrings on all exported classes and methods.

## Function Design

**Size:**
- Functions should focus on a single responsibility. Large multi-step operations (such as queue processing) are broken down into private helper functions or chained through async streams.

**Parameters:**
- Named parameters are preferred for functions with more than two arguments to ensure call-site clarity.
- Nullable parameters must be explicitly typed with `?` and guarded against null-pointer errors.

## Module Design

**Riverpod Notifiers:**
- Complex notifiers are decomposed across multiple files using Dart's `part` and `part of` directives to prevent massive monolithic files while maintaining full access to private members.

---

*Convention analysis: 2026-10-30*

