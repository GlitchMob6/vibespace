import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vibespace/services/media_kit_playback_deck.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/services/playback_deck.dart';

void main() {
  test('Live WASAPI device query and playback verification on Windows', () async {
    final dllPath = r'D:\audiolab\Mornye\build\windows\x64\runner\Release\libmpv-2.dll';
    expect(File(dllPath).existsSync(), isTrue);
    MediaKit.ensureInitialized(libmpv: dllPath);

    // 1. Query available WASAPI devices
    final devices = await MediaKitPlaybackDeck.queryWASAPIDevices();
    print('\n=== Discovered ${devices.length} WASAPI device(s) ===');
    for (final d in devices) {
      print('  Device: ${d["name"]} | Description: ${d["description"]}');
    }

    final testTrack = r'E:\music\Anirudh Ravichander\Love Insurance Kompany (Original Motion Picture Soundtrack)\Anirudh Ravichander - Adaavadi.flac';
    expect(File(testTrack).existsSync(), isTrue, reason: 'Test track must exist');

    // 2. Test Shared Mode with previously corrupted device ID: "wasapi/1e463064-4a08-414f-bd1b-6da70bd88c8a"
    print('\n=== Testing Shared Mode with Stored Corrupted Device ID ===');
    const storedCorruptedId = 'wasapi/1e463064-4a08-414f-bd1b-6da70bd88c8a';
    final sharedDeck = MediaKitPlaybackDeck(
      playerId: 'live-test-shared',
      wasapiDeviceId: storedCorruptedId,
      exclusiveOutput: false,
    );
    addTearDown(sharedDeck.dispose);

    await sharedDeck.configureOutput();
    print('Configured Shared output:');
    print('  Active mpv device: ${sharedDeck.debugActiveDeviceId}');
    print('  Is fallback device: ${sharedDeck.debugIsFallbackDevice}');
    print('  windowsAudioStatus: ${windowsAudioStatus.value}');

    // Check dynamic presence of KT02H20 IEM
    final isIemPresent = devices.any(
      (d) =>
          (d['name'] as String).toLowerCase() ==
          'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
    );

    if (isIemPresent) {
      expect(sharedDeck.debugIsFallbackDevice, isFalse);
      expect(
        sharedDeck.debugActiveDeviceId,
        'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
      );
      expect(windowsAudioStatus.value.reason, 'active');
    } else {
      expect(sharedDeck.debugIsFallbackDevice, isTrue);
      expect(sharedDeck.debugActiveDeviceId, 'auto');
      expect(windowsAudioStatus.value.reason, 'fallback');
    }

    print('Loading audio track on shared deck...');
    await sharedDeck.setFileSource(testTrack);
    final sharedDuration = await sharedDeck.getDuration();
    print('Track loaded successfully! Duration: $sharedDuration');
    expect(sharedDuration, isNotNull);
    expect(sharedDuration!.inSeconds, greaterThan(0));

    print('Starting playback...');
    await sharedDeck.resume();
    expect(sharedDeck.state, PlaybackDeckState.playing);
    await Future.delayed(const Duration(seconds: 2));
    final pos = await sharedDeck.getCurrentPosition();
    print('Playback position after 2s: $pos');
    print('windowsAudioStatus during playback: ${windowsAudioStatus.value}');
    expect(pos, isNotNull);
    expect(pos!.inMilliseconds, greaterThan(0));
    await sharedDeck.stop();

    // 3. Test Exclusive Mode
    print('\n=== Testing Exclusive Mode ===');
    final exclusiveDeck = MediaKitPlaybackDeck(
      playerId: 'live-test-exclusive',
      exclusiveOutput: true,
    );
    addTearDown(exclusiveDeck.dispose);

    await exclusiveDeck.configureOutput();
    print('Configured Exclusive output:');
    print('  windowsAudioStatus: ${windowsAudioStatus.value}');

    print('Loading audio track on exclusive deck...');
    await exclusiveDeck.setFileSource(testTrack);
    final exclusiveDuration = await exclusiveDeck.getDuration();
    print('Track loaded successfully! Duration: $exclusiveDuration');
    expect(exclusiveDuration, isNotNull);

    print('Starting exclusive playback...');
    await exclusiveDeck.resume();
    expect(exclusiveDeck.state, PlaybackDeckState.playing);
    await Future.delayed(const Duration(seconds: 2));
    final exclusivePos = await exclusiveDeck.getCurrentPosition();
    print('Playback position after 2s: $exclusivePos');
    print('windowsAudioStatus during playback: ${windowsAudioStatus.value}');
    expect(exclusivePos, isNotNull);
    expect(exclusivePos!.inMilliseconds, greaterThan(0));
    await exclusiveDeck.stop();

    print('\n=== End-to-end Live Playback Verified Successfully! ===');
  });
}

