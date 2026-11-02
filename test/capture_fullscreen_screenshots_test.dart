import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibespace/controllers/player_metadata_controller.dart';
import 'package:vibespace/l10n/l10n.dart';
import 'package:vibespace/providers/music_player_provider.dart';
import 'package:vibespace/providers/system_volume_provider.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/theme/app_theme.dart';
import 'package:vibespace/utils/desktop_platform.dart';
import 'package:vibespace/utils/lyrics_parser.dart';
import 'package:vibespace/widgets/desktop/desktop_inspector.dart';
import 'package:vibespace/widgets/desktop/desktop_now_playing.dart';
import 'package:vibespace/widgets/desktop/desktop_window.dart';
import 'package:vibespace/widgets/desktop/windows_audio_quick_settings.dart';

const _testTrack = MediaItem(
  id: 'track-hires-1',
  title: 'Mangal Rang',
  artist: 'Ramayana OST',
  album: 'VibeSpace Hi-Res Collection',
  duration: Duration(minutes: 5, seconds: 12),
  extras: {'source': '/music/mangal_rang.flac'},
);

const _lrcText = '''
[00:00.00]Mangal bhavan amangal haari
[00:06.00]Dravahu sudasharath ajir bihaari
[00:12.00]Ram siya ram siya ram jai jai ram
[00:18.00]Experience high-fidelity sound with pure bit-perfect stream
[00:24.00]Immersive desktop listening space in WASAPI Exclusive
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDesktopPlatformOverride = true;

    messenger.setMockMethodCallHandler(
      const MethodChannel('com.zarz.mornye/windows_audio'),
      (call) async {
        if (call.method == 'getAudioEndpoints') return <dynamic>[];
        if (call.method == 'getDeviceCapabilities') {
          return <String, dynamic>{
            'supportedSampleRates': [44100, 48000, 96000, 192000],
            'supportedSampleFormats': ['s16', 's24', 's32', 'float'],
            'exclusiveSampleRates': [44100, 48000, 96000, 192000],
            'exclusiveSampleFormats': ['s16', 's24', 's32', 'float'],
          };
        }
        return null;
      },
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('com.zarz.mornye/windows_audio_events'),
      (call) async => null,
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('com.zarz.mornye/window'),
      (call) async => null,
    );

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );

    windowsAudioStatus.value = const WindowsAudioStatus(
      mode: 'exclusive_event',
      sampleRate: 96000,
      bitDepth: 32,
      format: 's32',
      channels: 'stereo',
      isBitPerfect: true,
      bitPerfectReason: 'Verified bit-perfect output stream via WASAPI Exclusive mode.',
      reason: 'Playing',
    );
    desktopLiveAudioMonitorOpen.value = true;
    desktopAudioQuickSettingsOpen.value = false;
    desktopNowPlayingOpen.value = true;
    desktopWindowFullScreen.value = true;
    desktopWindowMode.value = DesktopWindowMode.fullscreen;
  });

  tearDown(() {
    debugDesktopPlatformOverride = null;
    messenger.setMockMethodCallHandler(const MethodChannel('com.zarz.mornye/windows_audio'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('com.zarz.mornye/windows_audio_events'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('com.zarz.mornye/window'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), null);
    windowsAudioStatus.value = const WindowsAudioStatus();
    desktopLiveAudioMonitorOpen.value = false;
    desktopAudioQuickSettingsOpen.value = false;
    desktopNowPlayingOpen.value = false;
    desktopWindowFullScreen.value = false;
    desktopWindowMode.value = DesktopWindowMode.windowed;
  });

  Widget buildCaptureWidget(FullscreenListeningMode mode, GlobalKey boundaryKey) {
    final effectivePlayback = PlaybackState(
      playing: false,
      processingState: AudioProcessingState.ready,
      updatePosition: const Duration(seconds: 8),
    );

    return ProviderScope(
      overrides: [
        currentMediaItemProvider.overrideWithBuild(
          (ref, notifier) => Stream.value(_testTrack),
        ),
        playbackStateProvider.overrideWith((ref) => Stream.value(effectivePlayback)),
        playQueueProvider.overrideWith(
          (ref) => Stream.value(const [_testTrack]),
        ),
        systemVolumeProvider.overrideWith((ref) => Stream.value(0.85)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: DesktopNowPlaying(
              initialMode: mode,
              metadataControllerFactory: () => PlayerMetadataController(
                readMetadata: (_) async => {'lyrics': _lrcText},
                parseLyrics: (raw) async => LyricsParser.parse(raw!),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Capture 3 Fullscreen Presentation Mode Screenshots', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    const artifactDir = r'C:\Users\pushk\.gemini\antigravity\brain\3c0b11a0-6069-4105-8fb2-98d6ad7169a4';

    // 1. Cover + Audio Mode
    final audioKey = GlobalKey();
    await tester.pumpWidget(buildCaptureWidget(FullscreenListeningMode.audio, audioKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() async {
      final boundary = audioKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$artifactDir\\vibespace_fullscreen_cover_audio.png').writeAsBytesSync(byteData!.buffer.asUint8List());
    });

    // 2. Cover + Lyrics Mode
    final lyricsKey = GlobalKey();
    await tester.pumpWidget(buildCaptureWidget(FullscreenListeningMode.lyrics, lyricsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() async {
      final boundary = lyricsKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$artifactDir\\vibespace_fullscreen_cover_lyrics.png').writeAsBytesSync(byteData!.buffer.asUint8List());
    });

    // 3. Cover Only Mode
    final coverKey = GlobalKey();
    await tester.pumpWidget(buildCaptureWidget(FullscreenListeningMode.coverOnly, coverKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.runAsync(() async {
      final boundary = coverKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$artifactDir\\vibespace_fullscreen_cover_only.png').writeAsBytesSync(byteData!.buffer.asUint8List());
    });
  });
}

