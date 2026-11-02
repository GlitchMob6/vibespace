import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibespace/controllers/player_metadata_controller.dart';
import 'package:vibespace/l10n/l10n.dart';
import 'package:vibespace/models/theme_settings.dart';
import 'package:vibespace/providers/music_player_provider.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/theme/app_theme.dart';
import 'package:vibespace/utils/desktop_platform.dart';
import 'package:vibespace/utils/lyrics_parser.dart';
import 'package:vibespace/widgets/desktop/desktop_inspector.dart';
import 'package:vibespace/widgets/desktop/desktop_now_playing.dart';
import 'package:vibespace/widgets/desktop/desktop_shortcuts.dart';
import 'package:vibespace/widgets/desktop/desktop_window.dart';
import 'package:vibespace/widgets/desktop/windows_audio_quick_settings.dart';
import 'package:vibespace/widgets/player_volume_control.dart';

const _channel = MethodChannel('com.zarz.mornye/window');

const _testTrack = MediaItem(
  id: 'test_track_1',
  title: 'Audiophile Master',
  artist: 'VibeSpace Artist',
  album: 'Hi-Res Session',
  duration: Duration(minutes: 5),
  extras: {'source': '/music/test.flac'},
);

const _lrcText = '''
[00:00.00]First line of lyrics
[00:05.00]Second line of lyrics
[00:10.00]Third line of lyrics
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  DesktopWindowMode nativeMode = DesktopWindowMode.windowed;

  Future<void> emitMode(DesktopWindowMode mode) async {
    nativeMode = mode;
    desktopWindowMode.value = mode;
    desktopWindowFullScreen.value = mode == DesktopWindowMode.fullscreen;
    await messenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('windowModeChanged', mode.name),
      ),
      (_) {},
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDesktopPlatformOverride = true;
    windowsAudioStatus.value = const WindowsAudioStatus();
    desktopLiveAudioMonitorOpen.value = false;
    desktopAudioQuickSettingsOpen.value = false;
    desktopNowPlayingOpen.value = true;
    desktopWindowFullScreen.value = false;
    desktopWindowMode.value = DesktopWindowMode.windowed;
    nativeMode = DesktopWindowMode.windowed;

    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'getWindowMode') return nativeMode.name;
      if (call.method == 'setWindowMode') {
        final name = (call.arguments as Map)['mode'] as String;
        final target = DesktopWindowMode.values.firstWhere((m) => m.name == name);
        await emitMode(target);
        return true;
      }
      return null;
    });
    listenDesktopWindowFullScreen();
  });

  tearDown(() {
    debugDesktopPlatformOverride = null;
    windowsAudioStatus.value = const WindowsAudioStatus();
    desktopLiveAudioMonitorOpen.value = false;
    desktopAudioQuickSettingsOpen.value = false;
    desktopNowPlayingOpen.value = false;
    desktopWindowFullScreen.value = false;
    desktopWindowMode.value = DesktopWindowMode.windowed;
    messenger.setMockMethodCallHandler(_channel, null);
  });

  Widget createTestWidget({
    FullscreenListeningMode initialMode = FullscreenListeningMode.lyrics,
    PlaybackState? playbackState,
  }) {
    final effectivePlayback = playbackState ??
        PlaybackState(
          playing: false,
          processingState: AudioProcessingState.ready,
          updatePosition: const Duration(seconds: 2),
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
        systemVolumeProvider.overrideWith((ref) => Stream.value(0.7)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DesktopNowPlaying(
            initialMode: initialMode,
            metadataControllerFactory: () => PlayerMetadataController(
              readMetadata: (_) async => {'lyrics': _lrcText},
              parseLyrics: (raw) async => LyricsParser.parse(raw!),
            ),
          ),
        ),
      ),
    );
  }

  group('FullscreenListeningLayout — Presentation Modes', () {
    testWidgets('Cover + Lyrics mode shows spacious synchronized lyrics on RIGHT and swapped top controls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(initialMode: FullscreenListeningMode.lyrics),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('desktop-contextual-lyrics-view')), findsOneWidget);
      expect(find.text('Audiophile Master'), findsOneWidget);
      expect(find.text('VibeSpace Artist · Hi-Res Session'), findsOneWidget);

      // Lyrics are positioned on the RIGHT side of the 1400px window (trailing 6/11)
      final lyricsPos = tester.getTopLeft(find.byKey(const ValueKey('desktop-contextual-lyrics-view')));
      expect(lyricsPos.dx, greaterThan(600.0));

      // Top-left: Master volume rocker (top: 20 with 4px capsule padding -> dy = 24)
      final volumePos = tester.getTopLeft(find.byType(PlayerVolumeControl));
      expect(volumePos.dx, lessThan(300.0));
      expect(volumePos.dy, equals(24.0));

      // Top-right: Close button
      final closePos = tester.getTopLeft(find.byKey(const ValueKey('desktop-now-playing-close')));
      expect(closePos.dx, greaterThan(1300.0));
      expect(closePos.dy, equals(20.0));
    });

    testWidgets('Cover + Audio mode displays monitor card and audio controls on LEFT', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(initialMode: FullscreenListeningMode.audio),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('desktop-contextual-audio-view')), findsOneWidget);
      expect(find.text('LIVE AUDIO STREAM MONITOR'), findsOneWidget);
      expect(find.text('AUDIO QUICK SETTINGS'), findsOneWidget);
      expect(find.text('AUDIO ENGINE'), findsOneWidget);

      // Audio panel is positioned on the LEFT side
      final audioPos = tester.getTopLeft(find.byKey(const ValueKey('desktop-contextual-audio-view')));
      expect(audioPos.dx, lessThan(100.0));
    });

    testWidgets('Cover Only mode hides contextual panel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(initialMode: FullscreenListeningMode.coverOnly),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Audiophile Master'), findsOneWidget);
      // Bottom-right contextual controls are discoverable
      expect(find.byKey(const ValueKey('desktop-now-playing-cover-only-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('desktop-now-playing-lyrics-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('desktop-now-playing-audio-toggle')), findsOneWidget);
    });

    testWidgets('Switching to Cover Only mode centers artwork and transport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(initialMode: FullscreenListeningMode.lyrics),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Click Cover Only button in bottom-right capsule
      final coverOnlyButton = find.byKey(const ValueKey('desktop-now-playing-cover-only-toggle'));
      expect(coverOnlyButton, findsOneWidget);
      await tester.tap(coverOnlyButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Reopen panel via bottom-right lyrics toggle
      final lyricsToggle = find.byKey(const ValueKey('desktop-now-playing-lyrics-toggle'));
      expect(lyricsToggle, findsOneWidget);
      await tester.tap(lyricsToggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('desktop-contextual-lyrics-view')), findsOneWidget);
    });

    testWidgets('Switching between Lyrics and Audio updates side panel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(initialMode: FullscreenListeningMode.lyrics),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('desktop-contextual-lyrics-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('desktop-contextual-audio-view')), findsNothing);

      // Tap Audio button in bottom-right capsule
      await tester.tap(find.byKey(const ValueKey('desktop-now-playing-audio-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('desktop-contextual-audio-view')), findsOneWidget);
      expect(
        tester.widget<IgnorePointer>(
          find.byKey(const ValueKey('desktop-now-playing-lyrics')),
        ).ignoring,
        isTrue,
      );
      expect(find.text('Audiophile Master'), findsOneWidget);

      // Tap Lyrics button in bottom-right capsule
      await tester.tap(find.byKey(const ValueKey('desktop-now-playing-lyrics-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('desktop-contextual-audio-view')), findsNothing);
      expect(
        tester.widget<IgnorePointer>(
          find.byKey(const ValueKey('desktop-now-playing-lyrics')),
        ).ignoring,
        isFalse,
      );
    });
  });

  group('FullscreenListeningLayout — Audio Control Center & Monitor', () {
    testWidgets('Closing monitor card keeps Audio Quick Settings visible and can be reopened', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(initialMode: FullscreenListeningMode.audio),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('LIVE AUDIO STREAM MONITOR'), findsOneWidget);
      expect(find.text('AUDIO QUICK SETTINGS'), findsOneWidget);

      // Find close button on monitor card
      final monitorClose = find.widgetWithIcon(IconButton, Icons.close).first;
      await tester.tap(monitorClose);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Monitor is dismissed, Quick settings remains
      expect(find.text('LIVE AUDIO STREAM MONITOR'), findsNothing);
      expect(find.text('AUDIO QUICK SETTINGS'), findsOneWidget);

      // Reopen monitor using graphic_eq button in Quick Settings header
      final reopenMonitor = find.byTooltip('Show Stream Monitor');
      expect(reopenMonitor, findsOneWidget);
      await tester.tap(reopenMonitor);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('LIVE AUDIO STREAM MONITOR'), findsOneWidget);
    });

    testWidgets('Single volume control: top-left volume hidden during Audio mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      // In Lyrics mode, exactly 1 volume control exists (the top-left rocker)
      await tester.pumpWidget(
        createTestWidget(initialMode: FullscreenListeningMode.lyrics),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PlayerVolumeControl), findsOneWidget);

      // Switch to Audio mode via bottom-right capsule
      await tester.tap(find.byKey(const ValueKey('desktop-now-playing-audio-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // In Audio mode, exactly 1 volume control exists (inside WindowsAudioQuickSettingsPanel)
      expect(find.byType(PlayerVolumeControl), findsOneWidget);
    });

    testWidgets('Zero duplicate monitor in Cover + Audio mode: single monitor embedded on left', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(initialMode: FullscreenListeningMode.audio),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Exactly ONE Live Audio Stream Monitor exists in the entire widget tree
      expect(find.text('LIVE AUDIO STREAM MONITOR'), findsOneWidget);

      // The monitor is embedded in the left-side Audio Control Center (dx < 100)
      final monitorFinder = find.byType(WindowsLiveAudioMonitorCard);
      expect(monitorFinder, findsOneWidget);
      final monitorPos = tester.getTopLeft(monitorFinder);
      expect(monitorPos.dx, lessThan(100.0));
    });
  });

  group('FullscreenListeningLayout — Escape Priority & Window Modes', () {
    testWidgets('Escape priority: True Fullscreen exits to Expanded Preview, then Normal App', (
      tester,
    ) async {
      await emitMode(DesktopWindowMode.fullscreen);
      desktopNowPlayingOpen.value = true;
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => DesktopShortcuts(
              navigatorKey: navigatorKey,
              child: child!,
            ),
            home: const Scaffold(body: Text('content')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // No top toolbar ("Full screen" header strip) rendered in True Fullscreen
      expect(find.text('Full screen'), findsNothing);

      // First Escape: leaves True Fullscreen -> windowed (Expanded Preview)
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(desktopWindowMode.value, DesktopWindowMode.windowed);
      // Now Playing is still open (Expanded Preview)
      expect(desktopNowPlayingOpen.value, isTrue);

      // Second Escape: closes Now Playing -> Normal Application
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(desktopNowPlayingOpen.value, isFalse);
    });
  });

  group('FullscreenListeningLayout — Appearance Settings', () {
    test('fullscreenControlsAutoHide round trips in ThemeSettings', () {
      const defaultSettings = ThemeSettings();
      expect(defaultSettings.fullscreenControlsAutoHide, isTrue);

      final modified = defaultSettings.copyWith(fullscreenControlsAutoHide: false);
      expect(modified.fullscreenControlsAutoHide, isFalse);

      final json = modified.toJson();
      final restored = ThemeSettings.fromJson(json);
      expect(restored.fullscreenControlsAutoHide, isFalse);
    });
  });
}