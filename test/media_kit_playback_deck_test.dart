import 'package:flutter_test/flutter_test.dart';
import 'package:vibespace/models/equalizer_settings.dart';
import 'package:vibespace/services/media_kit_playback_deck.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/services/playback_deck.dart';
import 'package:vibespace/services/playback_equalizer.dart';

import 'support/fake_mpv_engine.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

void main() {
  late FakeMpvEngine engine;
  late MediaKitPlaybackDeck deck;

  setUp(() {
    MediaKitPlaybackDeck.debugResetMissingFilters();
    playbackEqualizer.value = const EqualizerSettings();
    playbackEqualizerError.value = null;
    playbackOutputVolume.value = 1;
    engine = FakeMpvEngine();
    deck = MediaKitPlaybackDeck(playerId: 'mpv-test', engine: engine);
  });

  tearDown(() async {
    await deck.dispose();
    playbackEqualizer.value = const EqualizerSettings();
    playbackOutputVolume.value = 1;
  });

  test('loads a file paused and reports its duration', () async {
    final durations = <Duration>[];
    deck.onDurationChanged.listen(durations.add);
    await deck.setFileSource('/music/song.flac');
    expect(
      engine.calls,
      containsAllInOrder([
        ['stop'],
        ['open', '/music/song.flac'],
      ]),
    );
    expect(await deck.getDuration(), const Duration(seconds: 90));
    expect(durations, [const Duration(seconds: 90)]);
    expect(engine.calls, isNot(contains(['play'])));
  });

  test('transport changes the reported state', () async {
    final states = <PlaybackDeckState>[];
    deck.onPlayerStateChanged.listen(states.add);
    await deck.setFileSource('/song.flac');
    await deck.resume();
    expect(deck.state, PlaybackDeckState.playing);
    await deck.pause();
    expect(deck.state, PlaybackDeckState.paused);
    await deck.resume();
    engine.completedEvents.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(deck.state, PlaybackDeckState.completed);
    expect(states, [
      PlaybackDeckState.stopped,
      PlaybackDeckState.playing,
      PlaybackDeckState.paused,
      PlaybackDeckState.playing,
      PlaybackDeckState.completed,
    ]);
  });

  test('positions are published on a timer while playing', () async {
    final positions = <Duration>[];
    deck.onPositionChanged.listen(positions.add);
    deck.startPositionUpdates(const Duration(milliseconds: 10));
    await deck.setFileSource('/song.flac');
    engine.position = const Duration(seconds: 3);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(positions, isEmpty);
    await deck.resume();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(positions, isNotEmpty);
    expect(positions.last, const Duration(seconds: 3));
  });

  test(
    'a source that fails to open throws, DSD as UsbDsdUnavailable',
    () async {
      engine.openError = (prefix: 'cplayer', text: 'Failed to recognize file');
      await expectLater(
        deck.setFileSource('/broken.flac'),
        throwsA(isA<MediaKitSourceException>()),
      );
      await expectLater(
        deck.setFileSource('/song.dsf', requiresDsd: true),
        throwsA(isA<UsbDsdUnavailable>()),
      );
      engine.openError = null;
      await deck.setFileSource('/song.dsf', requiresDsd: true);
      expect(await deck.getDuration(), const Duration(seconds: 90));
    },
  );

  test('a runtime source error fails the next resume', () async {
    final errors = <Object>[];
    deck.onPlayerStateChanged.listen((_) {}, onError: errors.add);
    await deck.setFileSource('/song.flac');
    await deck.resume();
    engine.errorEvents.add((prefix: 'ad', text: 'Error decoding frame'));
    await Future<void>.delayed(Duration.zero);
    expect(errors, isEmpty);
    engine.errorEvents.add((prefix: 'stream', text: 'Read error'));
    await Future<void>.delayed(Duration.zero);
    expect(errors.single, isA<MediaKitSourceException>());
    await expectLater(deck.resume(), throwsA(isA<MediaKitSourceException>()));
  });

  for (final diagnostic in [
    (prefix: 'ffmpeg', text: 'Incorrect BOM value'),
    (prefix: 'ffmpeg/demuxer', text: 'Error reading frame TIT2, skipped'),
    (prefix: 'ad', text: 'Error decoding frame'),
  ]) {
    test(
      'recoverable ${diagnostic.prefix} error does not abort opening',
      () async {
        engine.openError = diagnostic;
        final errors = <Object>[];
        final subscription = deck.onPlayerStateChanged.listen(
          (_) {},
          onError: errors.add,
        );
        addTearDown(subscription.cancel);
        final loaded = expectLater(
          deck.setFileSource('/tagged.mp3'),
          completes,
        );
        await Future<void>.delayed(Duration.zero);
        engine.durationEvents.add(const Duration(seconds: 90));
        await loaded;
        expect(await deck.getDuration(), const Duration(seconds: 90));
        await deck.resume();
        expect(deck.state, PlaybackDeckState.playing);
        expect(errors, isEmpty);
        expect(
          engine.calls.where((call) => call.first == 'stop'),
          hasLength(1),
        );
      },
    );
  }

  test(
    'a fatal opening error after a tag diagnostic still rejects the source',
    () async {
      engine.openError = (prefix: 'ffmpeg', text: 'Incorrect BOM value');
      final failed = expectLater(
        deck.setFileSource('/broken.mp3'),
        throwsA(
          isA<MediaKitSourceException>().having(
            (error) => error.message,
            'fatal error',
            contains('Failed to recognize file'),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      engine.errorEvents.add((
        prefix: 'cplayer',
        text: 'Failed to recognize file',
      ));
      await failed;
    },
  );

  test(
    'volume is scaled by the in-app output volume on a cubic curve',
    () async {
      await deck.setVolume(0.8);
      expect(engine.volume, closeTo(100 * 0.9283, 0.01));
      playbackOutputVolume.value = 0.5;
      await Future<void>.delayed(Duration.zero);
      // 0.8 * 0.5 = 0.4 linear gain; mpv's volume is cubic.
      expect(engine.volume, closeTo(100 * 0.7368, 0.01));
      await deck.setVolume(0);
      expect(engine.volume, 0);
    },
  );

  test('equalizer changes set the chain while playing', () async {
    await _settle();
    expect(engine.filterWrites.single, ['set', 'af', '']);

    playbackEqualizer.value = const EqualizerSettings(enabled: true);
    await _settle();
    expect(
      engine.properties['af'],
      contains('@mornye_dsp:lavfi=[volume@pre=precision=float:volume=0dB,'),
    );

    await deck.setFileSource('/song.flac');
    await deck.resume();
    playbackEqualizer.value = playbackEqualizer.value.copyWith(preamp: -2);
    await _settle();
    expect(engine.properties['af'], contains('volume=-2dB'));

    var writes = engine.filterWrites.length;
    for (final gain in [-1.0, -1.5, -2.0]) {
      playbackEqualizer.value = playbackEqualizer.value.copyWith(
        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, gain],
      );
    }
    await _settle();
    expect(engine.filterWrites.length, writes + 1);
    expect(
      engine.properties['af'],
      contains('equalizer@band9=f=16000:t=q:w=1.4142:g=-2,'),
    );

    // An identical chain, here from a new rate below every band, is not set
    // again.
    writes = engine.filterWrites.length;
    engine.sampleRateEvents.add(48000);
    await _settle();
    expect(engine.filterWrites.length, writes);
    expect(playbackEqualizerError.value, isNull);

    playbackEqualizer.value = const EqualizerSettings();
    await _settle();
    expect(engine.properties['af'], '');
  });

  test('filters libmpv lacks are probed once and left out', () async {
    MediaKitPlaybackDeck.debugResetMissingFilters();
    addTearDown(MediaKitPlaybackDeck.debugResetMissingFilters);
    engine.missingFilters = {'volume', 'stereotools', 'alimiter'};
    await deck.setVolume(1);
    playbackEqualizer.value = const EqualizerSettings(
      enabled: true,
    ).copyWith(gains: [6, 0, 0, 0, 0, 0, 0, 0, 0, 0], balance: 0.5);
    await _settle();
    final af = engine.properties['af']!;
    expect(af, contains('equalizer@band0'));
    expect(af, isNot(contains('volume@pre')));
    expect(af, isNot(contains('stereotools')));
    // The -6 dB headroom moves to mpv's cubic volume.
    expect(engine.volume, closeTo(100 * 0.7943, 0.01));
    expect(playbackEqualizerError.value, contains('balance'));

    final probes = engine.filterWrites
        .where((call) => call[2].startsWith('@mornye_probe'))
        .length;
    expect(probes, 4);
    final other = FakeMpvEngine()..missingFilters = engine.missingFilters;
    final second = MediaKitPlaybackDeck(playerId: 'mpv-other', engine: other);
    await _settle();
    expect(
      other.filterWrites.where((call) => call[2].startsWith('@mornye_probe')),
      isEmpty,
    );
    await second.dispose();
  });

  test('a chain mpv disabled is set again on the next change', () async {
    playbackEqualizer.value = const EqualizerSettings(enabled: true);
    await _settle();
    engine.errorEvents.add((
      prefix: 'af',
      text: 'Disabling filter mornye_dsp because it has failed.',
    ));
    await Future<void>.delayed(Duration.zero);
    expect(playbackEqualizerError.value, contains('mornye_dsp'));
    final writes = engine.filterWrites.length;
    // Same chain as before: a rate change that leaves every band in place.
    engine.sampleRateEvents.add(48000);
    await _settle();
    expect(engine.filterWrites.length, writes + 1);
    expect(playbackEqualizerError.value, isNull);
  });

  test('a new sample rate rebuilds the bands', () async {
    playbackEqualizer.value = const EqualizerSettings(
      enabled: true,
    ).withBandCount(31);
    await _settle();
    expect(engine.properties['af'], contains('f=19845'));
    engine.sampleRateEvents.add(96000);
    await _settle();
    expect(engine.properties['af'], contains('f=20000'));
  });

  test('filter failures are reported for this player only', () async {
    engine.rejectFilters = true;
    playbackEqualizer.value = const EqualizerSettings(enabled: true);
    await _settle();
    expect(playbackEqualizerError.value, contains('mpv error -7'));
    engine.rejectFilters = false;
    playbackEqualizer.value = const EqualizerSettings();
    await _settle();
    expect(playbackEqualizerError.value, isNull);

    playbackEqualizer.value = const EqualizerSettings(enabled: true);
    await _settle();
    engine.errorEvents.add((
      prefix: 'ffmpeg/Parsed_equalizer_0',
      text: 'Invalid frequency',
    ));
    await Future<void>.delayed(Duration.zero);
    expect(playbackEqualizerError.value, contains('Invalid frequency'));
    await deck.dispose();
    expect(playbackEqualizerError.value, isNull);
    expect(engine.disposed, isTrue);
  });

  group('WASAPI Device Management & Fallback', () {
    test('parseAudioDeviceList parses JSON array from mpv and preserves GUID braces', () {
      const json =
          '[{"name":"wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}","description":"IEMs (KT02H20 HIFI Audio)"},{"name":"auto","description":"Autoselect device"}]';
      final devices = MediaKitPlaybackDeck.parseAudioDeviceList(json);
      expect(devices, hasLength(2));
      expect(devices[0]['name'], 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(devices[0]['description'], 'IEMs (KT02H20 HIFI Audio)');
      expect(devices[1]['name'], 'auto');
    });

    test('parseAudioDeviceList handles empty and fallback formats safely', () {
      expect(MediaKitPlaybackDeck.parseAudioDeviceList(''), isEmpty);
      expect(MediaKitPlaybackDeck.parseAudioDeviceList('[]'), isEmpty);

      final fallback = MediaKitPlaybackDeck.parseAudioDeviceList('Speakers, Headphones');
      expect(fallback, hasLength(2));
      expect(fallback[0]['name'], 'Speakers');
      expect(fallback[1]['name'], 'Headphones');
    });

    test('normalizeWasapiDeviceId repairs unbraced GUIDs and preserves valid IDs', () {
      expect(
        MediaKitPlaybackDeck.normalizeWasapiDeviceId('wasapi/1e463064-4a08-414f-bd1b-6da70bd88c8a'),
        'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
      );
      expect(
        MediaKitPlaybackDeck.normalizeWasapiDeviceId('wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}'),
        'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
      );
      expect(MediaKitPlaybackDeck.normalizeWasapiDeviceId('auto'), 'auto');
      expect(MediaKitPlaybackDeck.normalizeWasapiDeviceId(''), '');
    });

    test('configureOutput selects requested device when present in device list', () async {
      final customEngine = FakeMpvEngine();
      customEngine.properties['audio-device-list'] =
          '[{"name":"wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}","description":"IEMs (KT02H20 HIFI Audio)"}]';

      final customDeck = MediaKitPlaybackDeck(
        playerId: 'mpv-iem',
        engine: customEngine,
        wasapiDeviceId: 'wasapi/1e463064-4a08-414f-bd1b-6da70bd88c8a', // Unbraced, should be normalized
      );
      addTearDown(customDeck.dispose);

      await customDeck.configureOutput();

      expect(customEngine.properties['audio-device'], 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(customDeck.debugActiveDeviceId, 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(customDeck.debugIsFallbackDevice, isFalse);
      expect(windowsAudioStatus.value.reason, 'active');
      expect(windowsAudioStatus.value.device, 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
    });

    test('configureOutput falls back to auto when requested device is absent', () async {
      final customEngine = FakeMpvEngine();
      customEngine.properties['audio-device-list'] =
          '[{"name":"wasapi/{different-guid}","description":"Speakers"}]';

      final customDeck = MediaKitPlaybackDeck(
        playerId: 'mpv-iem-missing',
        engine: customEngine,
        wasapiDeviceId: 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
      );
      addTearDown(customDeck.dispose);

      await customDeck.configureOutput();

      expect(customEngine.properties['audio-device'], 'auto');
      expect(customDeck.debugActiveDeviceId, 'auto');
      expect(customDeck.debugIsFallbackDevice, isTrue);
      expect(windowsAudioStatus.value.reason, 'fallback');
      expect(
        windowsAudioStatus.value.device,
        'auto (requested: wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a})',
      );
    });

    test('configureOutput defaults to auto when no device is specified', () async {
      await deck.configureOutput();
      expect(engine.properties['audio-device'], 'auto');
      expect(deck.debugActiveDeviceId, 'auto');
      expect(deck.debugIsFallbackDevice, isFalse);
      expect(windowsAudioStatus.value.reason, 'active');
      expect(windowsAudioStatus.value.device, 'auto');
    });

    test('_load retries once with audio-device=auto when audio driver fails on selected device', () async {
      final retryEngine = FakeMpvEngine();
      retryEngine.properties['audio-device-list'] =
          '[{"name":"wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}","description":"IEMs"}]';

      // Fail with ao error when audio-device is not auto
      retryEngine.openErrorCallback = (source) {
        if (retryEngine.properties['audio-device'] != 'auto') {
          return (prefix: 'ao', text: "Failed to initialize audio driver 'wasapi'");
        }
        return null; // Succeed when auto
      };

      final retryDeck = MediaKitPlaybackDeck(
        playerId: 'mpv-retry',
        engine: retryEngine,
        wasapiDeviceId: 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
      );
      addTearDown(retryDeck.dispose);

      await retryDeck.configureOutput();
      expect(retryEngine.properties['audio-device'], 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}');

      // setFileSource should succeed thanks to automatic single retry with audio-device=auto
      await retryDeck.setFileSource('/music/test.flac');

      expect(retryEngine.properties['audio-device'], 'auto');
      expect(retryDeck.debugIsFallbackDevice, isTrue);
      expect(windowsAudioStatus.value.reason, 'fallback');
      expect(
        windowsAudioStatus.value.device,
        'auto (requested: wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a})',
      );
      expect(await retryDeck.getDuration(), const Duration(seconds: 90));
    });

    test('_load does not retry if the error is a regular non-audio source failure', () async {
      final customEngine = FakeMpvEngine();
      customEngine.openError = (prefix: 'cplayer', text: 'Failed to recognize file');

      final customDeck = MediaKitPlaybackDeck(
        playerId: 'mpv-non-audio-fail',
        engine: customEngine,
        wasapiDeviceId: 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
      );
      addTearDown(customDeck.dispose);

      await expectLater(
        customDeck.setFileSource('/bad.file'),
        throwsA(isA<MediaKitSourceException>()),
      );
      expect(customDeck.debugIsFallbackDevice, isFalse);
    });
  });
}
