import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibespace/services/media_kit_playback_deck.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/services/playback_deck.dart';

import 'support/fake_mpv_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WASAPI Lifecycle Hardening & Multi-Configuration Tests', () {
    test('Configures exclusive_event with 0.05s buffer and low latency', () async {
      final engine = FakeMpvEngine();
      engine.properties['audio-exclusive'] = 'yes';
      final deck = MediaKitPlaybackDeck(
        playerId: 'test-exclusive-event',
        engine: engine,
        wasapiMode: 'exclusive_event',
      );
      addTearDown(deck.dispose);

      await deck.configureOutput();

      expect(engine.properties['audio-exclusive'], 'yes');
      expect(engine.properties['audio-buffer'], '0.05');
      expect(deck.isExclusive, isTrue);
      expect(windowsAudioStatus.value.mode, 'exclusive_event');
      expect(windowsAudioStatus.value.reason, 'active');
    });

    test('Configures exclusive_push with 0.2s buffer for USB DAC jitter stability', () async {
      final engine = FakeMpvEngine();
      engine.properties['audio-exclusive'] = 'yes';
      final deck = MediaKitPlaybackDeck(
        playerId: 'test-exclusive-push',
        engine: engine,
        wasapiMode: 'exclusive_push',
      );
      addTearDown(deck.dispose);

      await deck.configureOutput();

      expect(engine.properties['audio-exclusive'], 'yes');
      expect(engine.properties['audio-buffer'], '0.2');
      expect(deck.isExclusive, isTrue);
      expect(windowsAudioStatus.value.mode, 'exclusive_push');
      expect(windowsAudioStatus.value.reason, 'active');
    });

    test('Configures shared mode with audio-exclusive=no', () async {
      final engine = FakeMpvEngine();
      engine.properties['audio-exclusive'] = 'no';
      final deck = MediaKitPlaybackDeck(
        playerId: 'test-shared',
        engine: engine,
        wasapiMode: 'shared',
      );
      addTearDown(deck.dispose);

      await deck.configureOutput();

      expect(engine.properties['audio-exclusive'], 'no');
      expect(engine.properties['audio-buffer'], '0.2');
      expect(deck.isExclusive, isFalse);
      expect(windowsAudioStatus.value.mode, 'shared');
      expect(windowsAudioStatus.value.reason, 'active');
    });

    test('Fallback Step 2: Falls back to Shared mode on the same device when Exclusive fails', () async {
      final engine = FakeMpvEngine();
      const testDevice = 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}';
      engine.properties['audio-device-list'] =
          '[{"name":"$testDevice","description":"KT02H20 IEMs"}]';

      // Simulate Exclusive mode failing on device, but Shared mode succeeding
      engine.openErrorCallback = (source) {
        if (engine.properties['audio-exclusive'] == 'yes') {
          return (
            prefix: 'ao/wasapi',
            text: 'Error initializing device: AUDCLNT_E_DEVICE_IN_USE (0x8889000a)',
          );
        }
        return null; // Shared mode succeeds
      };

      final deck = MediaKitPlaybackDeck(
        playerId: 'test-step2-fallback',
        engine: engine,
        wasapiDeviceId: testDevice,
        wasapiMode: 'exclusive_event',
        exclusiveFallback: true,
      );
      addTearDown(deck.dispose);

      await deck.configureOutput();
      expect(engine.properties['audio-device'], testDevice);
      expect(engine.properties['audio-exclusive'], 'yes');

      // Attempt loading source
      await deck.setFileSource('/music/track.flac');

      // Verify Step 2 recovery: still on the same physical device, but fell back to Shared mode!
      expect(engine.properties['audio-device'], testDevice);
      expect(engine.properties['audio-exclusive'], 'no');
      expect(deck.debugIsFallbackDevice, isFalse);
      expect(windowsAudioStatus.value.reason, 'fallback');
      expect(windowsAudioStatus.value.mode, 'shared');
      expect(windowsAudioStatus.value.device, testDevice);
      // User's configured device preference was preserved (Step 4)
      expect(deck.wasapiDeviceId, testDevice);
    });

    test('Fallback Step 3: Falls back to auto when device fails in Shared mode too', () async {
      final engine = FakeMpvEngine();
      const testDevice = 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}';
      engine.properties['audio-device-list'] =
          '[{"name":"$testDevice","description":"KT02H20 IEMs"}]';

      // Both Exclusive and Shared fail on this device (e.g. disconnected or hardware locked)
      engine.openErrorCallback = (source) {
        if (engine.properties['audio-device'] != 'auto') {
          return (
            prefix: 'ao/wasapi',
            text: 'Error initializing device: AUDCLNT_E_DEVICE_IN_USE (0x8889000a)',
          );
        }
        return null; // Only auto succeeds
      };

      final deck = MediaKitPlaybackDeck(
        playerId: 'test-step3-fallback',
        engine: engine,
        wasapiDeviceId: testDevice,
        wasapiMode: 'exclusive_event',
        exclusiveFallback: true,
      );
      addTearDown(deck.dispose);

      await deck.configureOutput();
      await deck.setFileSource('/music/track.flac');

      // Verify Step 3 recovery: fell back to system default (auto) in Shared mode
      expect(engine.properties['audio-device'], 'auto');
      expect(engine.properties['audio-exclusive'], 'no');
      expect(deck.debugIsFallbackDevice, isTrue);
      expect(windowsAudioStatus.value.reason, 'fallback');
      expect(windowsAudioStatus.value.mode, 'shared');
      expect(windowsAudioStatus.value.device, 'auto (requested: $testDevice)');
      // User's configured device preference remains preserved (Step 4)
      expect(deck.wasapiDeviceId, testDevice);
    });

    test('updateOutputSettings dynamically switches modes and devices without destroying state', () async {
      final engine = FakeMpvEngine();
      final deck = MediaKitPlaybackDeck(
        playerId: 'test-dynamic-update',
        engine: engine,
        wasapiMode: 'shared',
      );
      addTearDown(deck.dispose);

      await deck.configureOutput();
      expect(engine.properties['audio-exclusive'], 'no');

      // User changes to Exclusive Push in Settings UI
      deck.updateOutputSettings(wasapiMode: 'exclusive_push');
      engine.properties['audio-exclusive'] = 'yes';
      await deck.configureOutput();
      expect(engine.properties['audio-exclusive'], 'yes');
      expect(engine.properties['audio-buffer'], '0.2');
      expect(windowsAudioStatus.value.mode, 'exclusive_push');

      // User changes to Exclusive Event
      deck.updateOutputSettings(wasapiMode: 'exclusive_event');
      await deck.configureOutput();
      expect(engine.properties['audio-buffer'], '0.05');
      expect(windowsAudioStatus.value.mode, 'exclusive_event');
    });

    test('Runtime AO error during playback recovers without unhandled exception', () async {
      final engine = FakeMpvEngine();
      final deck = MediaKitPlaybackDeck(
        playerId: 'test-runtime-ao-recovery',
        engine: engine,
        wasapiMode: 'exclusive_event',
        exclusiveFallback: true,
      );
      addTearDown(deck.dispose);

      await deck.configureOutput();
      await deck.setFileSource('/music/track.flac');
      await deck.resume();
      expect(deck.state, PlaybackDeckState.playing);

      // Trigger an AO runtime error while playing
      engine.errorEvents.add((
        prefix: 'ao/wasapi',
        text: 'Error initializing device: AUDCLNT_E_DEVICE_IN_USE (0x8889000a)',
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Output should have recovered to shared mode gracefully
      expect(engine.properties['audio-exclusive'], 'no');
      expect(windowsAudioStatus.value.reason, 'fallback');
      expect(windowsAudioStatus.value.mode, 'shared');
    });

    test('Deadlock prevention: Re-entrant serialization executes without hanging', () async {
      // Simulate the exact pattern that previously deadlocked MusicPlayerHandler:
      // An operation running inside _serializeSourceChange awaiting another action
      // that also calls _serializeSourceChange.
      Future<void> serializeSourceChange(Future<void> Function() action, List<Future<void>> queue) {
        if (Zone.current[#inSourceChange] == true) {
          return action();
        }
        final operation = queue.last.then((_) {
          return runZoned(
            () => action(),
            zoneValues: {#inSourceChange: true},
          );
        });
        queue.add(operation.catchError((Object _) {}));
        return operation;
      }

      final queue = <Future<void>>[Future.value()];
      final completedSteps = <String>[];

      final future = serializeSourceChange(() async {
        completedSteps.add('outer_start');
        // Nested re-entrant call (e.g. _reinitializeWindowsAudioOutput calling _playIndex)
        await serializeSourceChange(() async {
          completedSteps.add('inner_nested');
        }, queue);
        completedSteps.add('outer_end');
      }, queue);

      // Must complete promptly without timeout/deadlock
      await future.timeout(const Duration(seconds: 2));

      expect(completedSteps, ['outer_start', 'inner_nested', 'outer_end']);
    });

    test('Rapid transport sequence (play, pause, seek, volume, mode change) remains responsive', () async {
      final engine = FakeMpvEngine();
      final deck = MediaKitPlaybackDeck(
        playerId: 'test-transport-sequence',
        engine: engine,
        wasapiMode: 'shared',
      );
      addTearDown(deck.dispose);

      await deck.configureOutput();
      await deck.setFileSource('/music/track.flac');

      // Rapid sequence of controls
      await deck.resume();
      expect(deck.state, PlaybackDeckState.playing);

      await deck.pause();
      expect(deck.state, PlaybackDeckState.paused);

      await deck.resume();
      expect(deck.state, PlaybackDeckState.playing);

      await deck.seek(const Duration(seconds: 45));
      expect(engine.calls.any((c) => c[0] == 'seek' && c[1] == '45000'), isTrue);

      await deck.setVolume(0.8);
      expect(deck.state, PlaybackDeckState.playing);

      // Switch output mode while playing
      deck.updateOutputSettings(wasapiMode: 'exclusive_event');
      await deck.configureOutput();
      expect(deck.state, PlaybackDeckState.playing);

      // Pause and stop
      await deck.pause();
      expect(deck.state, PlaybackDeckState.paused);
      await deck.stop();
      expect(deck.state, PlaybackDeckState.stopped);
    });
  });
}
