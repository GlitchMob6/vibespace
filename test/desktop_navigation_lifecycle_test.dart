import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibespace/l10n/l10n.dart';
import 'package:vibespace/services/shell_navigation_service.dart';
import 'package:vibespace/utils/desktop_platform.dart';
import 'package:vibespace/widgets/desktop/desktop_inspector.dart';
import 'package:vibespace/widgets/desktop/desktop_shortcuts.dart';
import 'package:vibespace/widgets/desktop/desktop_window.dart';
import 'package:vibespace/widgets/desktop/windows_audio_quick_settings.dart';

const _channel = MethodChannel('com.zarz.mornye/window');

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
    debugDesktopPlatformOverride = true;
    desktopLiveAudioMonitorOpen.value = false;
    desktopAudioQuickSettingsOpen.value = false;
    desktopNowPlayingOpen.value = false;
    desktopWindowFullScreen.value = false;
    desktopWindowMode.value = DesktopWindowMode.windowed;
    nativeMode = DesktopWindowMode.windowed;
    ShellNavigationService.resetHistory();

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
    desktopLiveAudioMonitorOpen.value = false;
    desktopAudioQuickSettingsOpen.value = false;
    desktopNowPlayingOpen.value = false;
    desktopWindowFullScreen.value = false;
    desktopWindowMode.value = DesktopWindowMode.windowed;
    nativeMode = DesktopWindowMode.windowed;
    ShellNavigationService.resetHistory();
    messenger.setMockMethodCallHandler(_channel, null);
  });

  Widget buildTestApp({
    required GlobalKey<NavigatorState> navigatorKey,
    required Widget child,
  }) {
    return ProviderScope(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, widgetChild) => DesktopShortcuts(
          navigatorKey: navigatorKey,
          child: widgetChild!,
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  group('Keyboard Escape Priority Hierarchy', () {
    testWidgets('Priority 1: Escape dismisses active dialog before ACC or fullscreen', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      desktopAudioQuickSettingsOpen.value = true;
      desktopLiveAudioMonitorOpen.value = true;

      await tester.pumpWidget(
        buildTestApp(
          navigatorKey: navKey,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    title: Text('Test Dialog'),
                  ),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Test Dialog'), findsOneWidget);
      expect(desktopAudioQuickSettingsOpen.value, isTrue);

      // Press Escape -> Dialog dismisses first!
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Test Dialog'), findsNothing);
      // ACC remains open
      expect(desktopAudioQuickSettingsOpen.value, isTrue);
      expect(desktopLiveAudioMonitorOpen.value, isTrue);

      // Next Escape -> Closes ACC and monitor together!
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(desktopAudioQuickSettingsOpen.value, isFalse);
      expect(desktopLiveAudioMonitorOpen.value, isFalse);
    });

    testWidgets('Priority 2: Escape closes normal application ACC and monitor together', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      desktopAudioQuickSettingsOpen.value = true;
      desktopLiveAudioMonitorOpen.value = true;

      await tester.pumpWidget(
        buildTestApp(
          navigatorKey: navKey,
          child: const Text('Base Content'),
        ),
      );
      await tester.pumpAndSettle();

      expect(desktopAudioQuickSettingsOpen.value, isTrue);
      expect(desktopLiveAudioMonitorOpen.value, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(desktopAudioQuickSettingsOpen.value, isFalse);
      expect(desktopLiveAudioMonitorOpen.value, isFalse);
    });

    testWidgets('Priority 3 & 4: Escape steps from True Fullscreen -> Expanded Preview -> Normal App', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await emitMode(DesktopWindowMode.fullscreen);
      desktopNowPlayingOpen.value = true;

      await tester.pumpWidget(
        buildTestApp(
          navigatorKey: navKey,
          child: const Text('Normal Content'),
        ),
      );
      await tester.pumpAndSettle();

      // First Escape: exits True Fullscreen to Expanded Preview
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(desktopWindowMode.value, DesktopWindowMode.windowed);
      expect(desktopNowPlayingOpen.value, isTrue);

      // Second Escape: exits Expanded Preview to Normal App
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(desktopNowPlayingOpen.value, isFalse);
    });

    testWidgets('Priority 5: Escape navigates to previous page/tab in history', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      ShellTab? currentActiveTab = ShellTab.home;

      ShellNavigationService.registerTabSelectionHandler(
        owner: 'test-owner',
        handler: (tab) => currentActiveTab = tab,
      );
      addTearDown(() => ShellNavigationService.unregisterTabSelectionHandler('test-owner'));

      ShellNavigationService.recordTabVisit(ShellTab.library);
      currentActiveTab = ShellTab.library;
      ShellNavigationService.recordTabVisit(ShellTab.settings);
      currentActiveTab = ShellTab.settings;

      await tester.pumpWidget(
        buildTestApp(
          navigatorKey: navKey,
          child: const Text('Tab Shell'),
        ),
      );
      await tester.pumpAndSettle();

      expect(ShellNavigationService.canNavigateBack, isTrue);

      // Escape navigates back from settings to library
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(currentActiveTab, ShellTab.library);

      // Escape navigates back from library to home
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(currentActiveTab, ShellTab.home);
      expect(ShellNavigationService.canNavigateBack, isFalse);

      // Further Escape does not crash or navigate away from root
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(currentActiveTab, ShellTab.home);
    });

    testWidgets('Escape unfocuses active text editing without popping page', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        buildTestApp(
          navigatorKey: navKey,
          child: TextField(
            focusNode: focusNode,
            decoration: const InputDecoration(labelText: 'Search Field'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      // Escape unfocuses text input first
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isFalse);
    });
  });

  group('Mouse Button 4 (Back) and Button 5 (Forward)', () {
    testWidgets('Mouse Button 4 navigates back and Button 5 navigates forward', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      ShellTab? currentActiveTab = ShellTab.home;

      ShellNavigationService.registerTabSelectionHandler(
        owner: 'test-owner-mouse',
        handler: (tab) => currentActiveTab = tab,
      );
      addTearDown(() => ShellNavigationService.unregisterTabSelectionHandler('test-owner-mouse'));

      ShellNavigationService.recordTabVisit(ShellTab.library);
      currentActiveTab = ShellTab.library;
      ShellNavigationService.recordTabVisit(ShellTab.settings);
      currentActiveTab = ShellTab.settings;

      await tester.pumpWidget(
        buildTestApp(
          navigatorKey: navKey,
          child: const Center(child: Text('Mouse Test Page')),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('Mouse Test Page'));

      // Simulate physical press of Mouse Button 4 (kBackMouseButton = 0x08)
      final pointer = TestPointer(1, PointerDeviceKind.mouse);

      // Down with Mouse Button 4
      await tester.sendEventToBinding(pointer.down(center, buttons: kBackMouseButton));
      await tester.pumpAndSettle();
      await tester.sendEventToBinding(pointer.up());
      await tester.pumpAndSettle();

      // Navigated backward from settings to library
      expect(currentActiveTab, ShellTab.library);
      expect(ShellNavigationService.canNavigateForward, isTrue);

      // Down with Mouse Button 5 (kForwardMouseButton = 0x10)
      await tester.sendEventToBinding(pointer.down(center, buttons: kForwardMouseButton));
      await tester.pumpAndSettle();
      await tester.sendEventToBinding(pointer.up());
      await tester.pumpAndSettle();

      // Navigated forward from library to settings
      expect(currentActiveTab, ShellTab.settings);
      expect(ShellNavigationService.canNavigateForward, isFalse);
    });

    testWidgets('Holding mouse button does not repeatedly trigger navigation', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      ShellTab? currentActiveTab = ShellTab.home;

      ShellNavigationService.registerTabSelectionHandler(
        owner: 'test-owner-mouse-hold',
        handler: (tab) => currentActiveTab = tab,
      );
      addTearDown(() => ShellNavigationService.unregisterTabSelectionHandler('test-owner-mouse-hold'));

      ShellNavigationService.recordTabVisit(ShellTab.library);
      currentActiveTab = ShellTab.library;
      ShellNavigationService.recordTabVisit(ShellTab.settings);
      currentActiveTab = ShellTab.settings;

      await tester.pumpWidget(
        buildTestApp(
          navigatorKey: navKey,
          child: const Center(child: Text('Mouse Hold Page')),
        ),
      );
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.text('Mouse Hold Page'));
      final pointer = TestPointer(2, PointerDeviceKind.mouse);

      // Down with Mouse Button 4
      await tester.sendEventToBinding(pointer.down(center, buttons: kBackMouseButton));
      await tester.pumpAndSettle();

      expect(currentActiveTab, ShellTab.library);

      // Move while held: should NOT trigger another back navigation!
      await tester.sendEventToBinding(pointer.move(center + const Offset(10, 10), buttons: kBackMouseButton));
      await tester.pumpAndSettle();

      expect(currentActiveTab, ShellTab.library);

      await tester.sendEventToBinding(pointer.move(center + const Offset(20, 20), buttons: kBackMouseButton));
      await tester.pumpAndSettle();

      expect(currentActiveTab, ShellTab.library);

      // Release
      await tester.sendEventToBinding(pointer.up());
      await tester.pumpAndSettle();

      expect(currentActiveTab, ShellTab.library);
    });

    testWidgets('No interference with sliders or normal pointer controls', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      double sliderVal = 0.5;

      await tester.pumpWidget(
        buildTestApp(
          navigatorKey: navKey,
          child: StatefulBuilder(
            builder: (context, setState) => Slider(
              value: sliderVal,
              onChanged: (val) => setState(() => sliderVal = val),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      // Drag slider with primary mouse button
      final topLeft = tester.getTopLeft(sliderFinder);
      final bottomRight = tester.getBottomRight(sliderFinder);
      final target = Offset(bottomRight.dx - 20, (topLeft.dy + bottomRight.dy) / 2);

      await tester.tapAt(target);
      await tester.pumpAndSettle();

      // Value updated properly via primary button drag/click
      expect(sliderVal, greaterThan(0.7));
    });
  });

  group('ShellNavigationService History Architecture', () {
    test('Tracks tab history and forward stack correctly', () {
      ShellNavigationService.resetHistory(initialTab: ShellTab.home);
      expect(ShellNavigationService.canNavigateBack, isFalse);
      expect(ShellNavigationService.canNavigateForward, isFalse);

      ShellNavigationService.recordTabVisit(ShellTab.library);
      expect(ShellNavigationService.canNavigateBack, isTrue);
      expect(ShellNavigationService.currentTabForTesting, ShellTab.library);

      ShellNavigationService.recordTabVisit(ShellTab.settings);
      expect(ShellNavigationService.currentTabForTesting, ShellTab.settings);

      // Navigate back to library
      expect(ShellNavigationService.navigateBack(), isTrue);
      expect(ShellNavigationService.currentTabForTesting, ShellTab.library);
      expect(ShellNavigationService.canNavigateForward, isTrue);

      // Navigate back to home
      expect(ShellNavigationService.navigateBack(), isTrue);
      expect(ShellNavigationService.currentTabForTesting, ShellTab.home);
      expect(ShellNavigationService.canNavigateBack, isFalse);

      // Navigate forward to library
      expect(ShellNavigationService.navigateForward(), isTrue);
      expect(ShellNavigationService.currentTabForTesting, ShellTab.library);

      // New navigation clears forward stack
      ShellNavigationService.recordTabVisit(ShellTab.search);
      expect(ShellNavigationService.currentTabForTesting, ShellTab.search);
      expect(ShellNavigationService.canNavigateForward, isFalse);
    });
  });
}
