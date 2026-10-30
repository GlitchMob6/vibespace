import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vibespace/services/media_kit_playback_deck.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/services/playback_deck.dart';

void main() {
  test(
    'Live WASAPI device query and playback verification on Windows',
    () async {
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

    // 2. Test Shared Mode with Realtek / primary physical speaker
    print('\n=== Testing Shared Mode with Physical Audio Device ===');
    // Find Realtek or first non-auto wasapi device
    final testDevice = devices.firstWhere(
      (d) => (d['name'] as String).startsWith('wasapi/{88dac15c'),
      orElse: () => devices.firstWhere(
        (d) => (d['name'] as String).startsWith('wasapi/{'),
        orElse: () => devices.first,
      ),
    );
    final selectedDeviceId = testDevice['name'] as String;
    print('Testing with device: $selectedDeviceId (${testDevice["description"]})');

    final sharedDeck = MediaKitPlaybackDeck(
      playerId: 'live-test-shared',
      wasapiDeviceId: selectedDeviceId,
      exclusiveOutput: false,
    );
    addTearDown(sharedDeck.dispose);

    await sharedDeck.configureOutput();
    print('Configured Shared output:');
    print('  Active mpv device: ${sharedDeck.debugActiveDeviceId}');
    print('  Is fallback device: ${sharedDeck.debugIsFallbackDevice}');
    print('  windowsAudioStatus: ${windowsAudioStatus.value}');

    expect(sharedDeck.debugIsFallbackDevice, isFalse);
    expect(
      sharedDeck.debugActiveDeviceId,
      selectedDeviceId,
    );
    expect(windowsAudioStatus.value.reason, 'active');

    print('Loading audio track on shared deck...');
    await sharedDeck.setFileSource(testTrack);
    final sharedDuration = await sharedDeck.getDuration();
    print('Track loaded successfully! Duration: $sharedDuration');
    expect(sharedDuration, isNotNull);
    expect(sharedDuration!.inSeconds, greaterThan(0));

    print('Starting playback...');
    await sharedDeck.resume();
    expect(sharedDeck.state, PlaybackDeckState.playing);
    await Future.delayed(const Duration(seconds: 4));
    final pos = await sharedDeck.getCurrentPosition();
    print('Playback position after delay: $pos');
    print('windowsAudioStatus during playback: ${windowsAudioStatus.value}');
    expect(pos, isNotNull);
    expect(pos!.inMilliseconds, greaterThan(0));
    await sharedDeck.stop();

    // 3. Test Exclusive Mode
    print('\n=== Testing Exclusive Mode ===');
    final exclusiveDeck = MediaKitPlaybackDeck(
      playerId: 'live-test-exclusive',
      wasapiDeviceId: selectedDeviceId,
      exclusiveOutput: true,
      wasapiMode: 'exclusive_event',
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
  }, timeout: const Timeout(Duration(seconds: 45)));
}

