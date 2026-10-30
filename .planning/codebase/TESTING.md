# Testing Patterns

**Analysis Date:** 2026-10-30

## Test Framework

**Runner:**
- Dart/Flutter: `flutter_test` (bundled with Flutter SDK)
- Rust: Cargo built-in test runner (`cargo test`)
- End-to-End: Flutter `integration_test`

**Assertion Library:**
- `package:flutter_test/flutter_test.dart` (`expect`, `find`, `matchesGoldenFile`)

**Run Commands:**
```bash
# Run all Flutter unit and widget tests
fvm flutter test

# Run a specific test file
fvm flutter test test/app_settings_model_test.dart

# Run all Rust crate unit tests
(cd rust_backend && cargo test --workspace)

# Run end-to-end integration and performance tests
fvm flutter test integration_test/performance_driver.dart
```

## Test File Organization

**Location:**
- Unit & Widget Tests: Standalone `test/` directory mirroring `lib/` components.
- Device & Performance Tests: `integration_test/` directory.
- Rust Unit Tests: Co-located in `rust_backend/crates/*/tests` or inline `#[cfg(test)]` modules.

**Naming:**
- Dart test files strictly end with `*_test.dart` (e.g., `accessibility_guidelines_test.dart`, `design_system_test.dart`).

**Structure:**
```
test/
├── fixtures/                           # Sample audio metadata, mock JSON, CUE files
├── support/                            # In-memory mock helpers and fake database providers
├── accessibility_guidelines_test.dart  # WCAG / contrast ratio verification
├── app_settings_model_test.dart        # Settings serialization and migration tests
├── design_system_test.dart             # Static design system enforcement
├── library_database_test.dart          # SQLite CRUD and batch transaction tests
└── music_player_service_test.dart      # Audio state machine and AutoMix tests
```

## Test Structure

**Suite Organization:**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibescape/models/settings.dart';

void main() {
  group('AppSettings', () {
    setUp(() {
      // Set up in-memory mock state or clean fixtures
    });

    tearDown(() {
      // Clean up resources, reset mock method handlers
    });

    test('serializes to and from JSON preserving defaults', () {
      final settings = AppSettings.defaults();
      final json = settings.toJson();
      final restored = AppSettings.fromJson(json);

      expect(restored, equals(settings));
    });
  });
}
```

## Mocking

**Framework:**
- Manual lightweight fakes and Flutter's `TestDefaultBinaryMessengerBinding`.

**Patterns:**
```dart
// Mocking the native backend MethodChannel:
TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(
  const MethodChannel('com.zarz.mornye/backend'),
  (MethodCall call) async {
    if (call.method == 'resolveTrackMetadata') {
      return {'title': 'Mock Track', 'artist': 'Mock Artist'};
    }
    return null;
  },
);
```

**What to Mock:**
- External HTTP endpoints and network latency.
- Hardware audio outputs (speakers, DACs, USB interfaces).
- OS file pickers and system dialogs.

**What NOT to Mock:**
- Model serialization logic (`toJson` / `fromJson`).
- In-memory SQLite transaction logic (use SQLite memory databases to test real SQL queries).

## Fixtures and Factories

**Test Data:**
- Located in `test/fixtures/`: Contains authentic ID3v2 tagged audio snippets, Vorbis comments, FLAC headers, and album art PNGs.

## Coverage

**Requirements:**
- High test coverage on core persistence (`LibraryDatabase`, `AppStateDatabase`, `Settings`), metadata parsers, and download queue state transitions.

**View Coverage:**
```bash
fvm flutter test --coverage
# Coverage report generated at coverage/lcov.info
```

## Test Types

**Unit Tests:**
- Validates data model parsing, lyrics alignment algorithms, AutoMix phase calculations, and SQLite queries.

**Widget Tests:**
- Validates UI component layout, theme responsiveness, touch target sizes, and accessibility semantics.

**Integration & Benchmark Tests:**
- Validates frame rendering rates, list scrolling speed under 10,000+ tracks, and native download worker handoffs.

---

*Testing analysis: 2026-10-30*

