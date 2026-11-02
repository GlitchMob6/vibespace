import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibespace/l10n/l10n.dart';
import 'package:vibespace/providers/settings_provider.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/widgets/desktop/windows_audio_quick_settings.dart';
import 'package:vibespace/widgets/player_volume_control.dart';

void main() {
  Widget testFrame({required Widget child}) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  setUp(() {
    windowsAudioStatus.value = const WindowsAudioStatus();
    desktopLiveAudioMonitorOpen.value = false;
    desktopAudioQuickSettingsOpen.value = false;
  });

  tearDown(() {
    windowsAudioStatus.value = const WindowsAudioStatus();
    desktopLiveAudioMonitorOpen.value = false;
    desktopAudioQuickSettingsOpen.value = false;
  });

  group('WindowsLiveAudioMonitorCard', () {
    testWidgets('displays idle state without claiming bit-perfect', (
      tester,
    ) async {
      windowsAudioStatus.value = const WindowsAudioStatus(
        reason: 'idle',
        mode: 'shared',
        isBitPerfect: false,
      );

      await tester.pumpWidget(
        testFrame(child: const WindowsLiveAudioMonitorCard()),
      );
      await tester.pumpAndSettle();

      expect(find.text('LIVE AUDIO STREAM MONITOR'), findsOneWidget);
      expect(find.text('SHARED'), findsOneWidget);
      expect(find.text('BIT-PERFECT'), findsNothing);
      expect(
        find.text('Start playback to inspect the negotiated output stream.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'displays active bit-perfect badge only when isBitPerfect is verified',
      (tester) async {
        windowsAudioStatus.value = const WindowsAudioStatus(
          reason: 'active',
          mode: 'exclusive_event',
          device: 'wasapi/{sample-dac}',
          sampleRate: 96000,
          bitDepth: 32,
          format: 's32',
          sourceSampleRate: 96000,
          sourceBitDepth: 32,
          sourceFormat: 's32',
          isBitPerfect: true,
          bitPerfectReason:
              'Verified match: 96000 Hz, 32-bit s32 direct DAC rendering.',
        );

        await tester.pumpWidget(
          testFrame(child: const WindowsLiveAudioMonitorCard()),
        );
        await tester.pumpAndSettle();

        expect(find.text('BIT-PERFECT'), findsOneWidget);
        expect(
          find.text(
            'Verified match: 96000 Hz, 32-bit s32 direct DAC rendering.',
          ),
          findsOneWidget,
        );
        expect(find.text('96000 Hz · 32-bit (s32)'), findsNWidgets(2));
      },
    );

    testWidgets('displays close button and calls onDismiss', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        testFrame(
          child: WindowsLiveAudioMonitorCard(
            isFloating: true,
            onDismiss: () => dismissed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dismissButton = find.byTooltip('Close Monitor');
      expect(dismissButton, findsOneWidget);
      await tester.tap(dismissButton);
      await tester.pump();

      expect(dismissed, isTrue);
    });
  });

  group('WindowsAudioQuickSettingsPanel', () {
    testWidgets(
      'renders all required controls in compact layout with 400px width',
      (tester) async {
        await tester.pumpWidget(
          testFrame(
            child: const SizedBox(
              width: 400,
              child: WindowsAudioQuickSettingsPanel(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Header with title, independent stream monitor toggle and close button
        expect(find.text('AUDIO QUICK SETTINGS'), findsOneWidget);
        expect(find.byTooltip('Show Stream Monitor'), findsOneWidget);
        expect(find.byTooltip('Close Quick Settings'), findsOneWidget);

        // 2. Volume control at the top
        expect(find.text('VOLUME'), findsOneWidget);
        expect(find.byType(PlayerVolumeControl), findsOneWidget);

        // 3. Audio Engine selector (Shared / Exclusive Event / Exclusive Push)
        expect(find.text('AUDIO ENGINE'), findsOneWidget);
        expect(find.text('Shared'), findsOneWidget);
        expect(find.text('Exclusive Event'), findsOneWidget);
        expect(find.text('Exclusive Push'), findsOneWidget);

        // 4. Automatic fallback switch
        expect(find.text('Automatic fallback to Shared'), findsOneWidget);
        expect(find.byType(Switch), findsOneWidget);

        // 5. Three-column grid: Sample Rate, Sample Format, Channels
        expect(find.text('OUTPUT FORMAT'), findsOneWidget);
        expect(find.text('Sample Rate'), findsOneWidget);
        expect(find.text('Sample Format'), findsOneWidget);
        expect(find.text('Channels'), findsOneWidget);

        // 6. Output Device selector at bottom
        expect(find.text('OUTPUT DEVICE'), findsOneWidget);
        expect(find.text('System Default (Automatic)'), findsOneWidget);
      },
    );

    testWidgets('header button toggles independent live audio monitor state', (
      tester,
    ) async {
      expect(desktopLiveAudioMonitorOpen.value, isFalse);

      await tester.pumpWidget(
        testFrame(
          child: const SizedBox(
            width: 400,
            child: WindowsAudioQuickSettingsPanel(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final monitorToggle = find.byTooltip('Show Stream Monitor');
      expect(monitorToggle, findsOneWidget);

      await tester.tap(monitorToggle);
      await tester.pump();

      expect(desktopLiveAudioMonitorOpen.value, isTrue);
      expect(find.byTooltip('Hide Stream Monitor'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide Stream Monitor'));
      await tester.pump();

      expect(desktopLiveAudioMonitorOpen.value, isFalse);
    });

    testWidgets('panel close button closes quick settings', (tester) async {
      desktopAudioQuickSettingsOpen.value = true;

      await tester.pumpWidget(
        testFrame(
          child: const SizedBox(
            width: 400,
            child: WindowsAudioQuickSettingsPanel(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final closeButton = find.byTooltip('Close Quick Settings');
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pump();

      expect(desktopAudioQuickSettingsOpen.value, isFalse);
    });
  });

  group('DesktopAudioControlCenterOverlay', () {
    testWidgets(
      'renders on right side with 400px width and right spacing of 18px',
      (tester) async {
        desktopAudioQuickSettingsOpen.value = true;

        await tester.pumpWidget(
          testFrame(
            child: const SizedBox(
              width: 1200,
              height: 800,
              child: Stack(children: [DesktopAudioControlCenterOverlay()]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final positionedFinder = find.byWidgetPredicate(
          (w) => w is Positioned && w.right == 18.0,
        );
        expect(positionedFinder, findsOneWidget);
        final positioned = tester.widget<Positioned>(positionedFinder);

        // Right spacing is 18px
        expect(positioned.right, 18.0);
        // Width is 400px
        expect(positioned.width, 400.0);
        // Bottom spacing above player bar is 88px
        expect(positioned.bottom, 88.0);

        // Quick settings is present
        expect(find.byType(WindowsAudioQuickSettingsPanel), findsOneWidget);
        // Monitor is not open
        expect(find.byType(WindowsLiveAudioMonitorCard), findsNothing);
      },
    );

    testWidgets(
      'vertically stacks Live Monitor directly above Quick Settings with 10px gap',
      (tester) async {
        desktopAudioQuickSettingsOpen.value = true;
        desktopLiveAudioMonitorOpen.value = true;

        await tester.pumpWidget(
          testFrame(
            child: const SizedBox(
              width: 1200,
              height: 900,
              child: Stack(children: [DesktopAudioControlCenterOverlay()]),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Both panels are rendered simultaneously
        expect(find.byType(WindowsLiveAudioMonitorCard), findsOneWidget);
        expect(find.byType(WindowsAudioQuickSettingsPanel), findsOneWidget);

        // Verify vertical arrangement: Monitor top is above Quick Settings top
        final monitorRect = tester.getRect(
          find.byType(WindowsLiveAudioMonitorCard),
        );
        final quickSettingsRect = tester.getRect(
          find.byType(WindowsAudioQuickSettingsPanel),
        );

        expect(monitorRect.bottom < quickSettingsRect.top, isTrue);
        expect(quickSettingsRect.top - monitorRect.bottom, closeTo(10.0, 1.0));
        // Horizontal coordinates match
        expect(monitorRect.left, quickSettingsRect.left);
        expect(monitorRect.right, quickSettingsRect.right);
      },
    );

    testWidgets('dismissing monitor leaves quick settings open', (
      tester,
    ) async {
      desktopAudioQuickSettingsOpen.value = true;
      desktopLiveAudioMonitorOpen.value = true;

      await tester.pumpWidget(
        testFrame(
          child: const SizedBox(
            width: 1200,
            height: 900,
            child: Stack(children: [DesktopAudioControlCenterOverlay()]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final closeMonitorButton = find.byTooltip('Close Monitor');
      expect(closeMonitorButton, findsOneWidget);
      await tester.tap(closeMonitorButton);
      await tester.pumpAndSettle();

      expect(desktopLiveAudioMonitorOpen.value, isFalse);
      expect(desktopAudioQuickSettingsOpen.value, isTrue);
      expect(find.byType(WindowsLiveAudioMonitorCard), findsNothing);
      expect(find.byType(WindowsAudioQuickSettingsPanel), findsOneWidget);
    });
  });

  group('DesktopAudioControlCenterController Lifecycle Coordination', () {
    test('open() opens both ACC and monitor', () {
      desktopAudioQuickSettingsOpen.value = false;
      desktopLiveAudioMonitorOpen.value = false;

      DesktopAudioControlCenterController.instance.open();

      expect(desktopAudioQuickSettingsOpen.value, isTrue);
      expect(desktopLiveAudioMonitorOpen.value, isTrue);
    });

    test('close() closes both ACC and monitor', () {
      desktopAudioQuickSettingsOpen.value = true;
      desktopLiveAudioMonitorOpen.value = true;

      DesktopAudioControlCenterController.instance.close();

      expect(desktopAudioQuickSettingsOpen.value, isFalse);
      expect(desktopLiveAudioMonitorOpen.value, isFalse);
    });

    test('toggle() opens both when closed and closes both when open', () {
      desktopAudioQuickSettingsOpen.value = false;
      desktopLiveAudioMonitorOpen.value = false;

      // First toggle: opens both
      DesktopAudioControlCenterController.instance.toggle();
      expect(desktopAudioQuickSettingsOpen.value, isTrue);
      expect(desktopLiveAudioMonitorOpen.value, isTrue);

      // Second toggle: closes both
      DesktopAudioControlCenterController.instance.toggle();
      expect(desktopAudioQuickSettingsOpen.value, isFalse);
      expect(desktopLiveAudioMonitorOpen.value, isFalse);
    });

    test('closeMonitorOnly() closes only monitor leaving ACC open', () {
      desktopAudioQuickSettingsOpen.value = true;
      desktopLiveAudioMonitorOpen.value = true;

      DesktopAudioControlCenterController.instance.closeMonitorOnly();

      expect(desktopAudioQuickSettingsOpen.value, isTrue);
      expect(desktopLiveAudioMonitorOpen.value, isFalse);
    });

    test('openMonitor() reopens monitor while ACC is open', () {
      desktopAudioQuickSettingsOpen.value = true;
      desktopLiveAudioMonitorOpen.value = false;

      DesktopAudioControlCenterController.instance.openMonitor();

      expect(desktopAudioQuickSettingsOpen.value, isTrue);
      expect(desktopLiveAudioMonitorOpen.value, isTrue);
    });

    testWidgets('ACC X button closes both ACC and monitor', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      DesktopAudioControlCenterController.instance.open();

      await tester.pumpWidget(
        testFrame(
          child: const SizedBox(
            width: 1200,
            height: 900,
            child: Stack(children: [DesktopAudioControlCenterOverlay()]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WindowsLiveAudioMonitorCard), findsOneWidget);
      expect(find.byType(WindowsAudioQuickSettingsPanel), findsOneWidget);

      final closeACC = find.byTooltip('Close Quick Settings');
      expect(closeACC, findsOneWidget);
      await tester.tap(closeACC);
      await tester.pumpAndSettle();

      expect(desktopAudioQuickSettingsOpen.value, isFalse);
      expect(desktopLiveAudioMonitorOpen.value, isFalse);
      expect(find.byType(WindowsLiveAudioMonitorCard), findsNothing);
      expect(find.byType(WindowsAudioQuickSettingsPanel), findsNothing);
    });

    testWidgets('Outside tap closes both ACC and monitor', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      DesktopAudioControlCenterController.instance.open();

      await tester.pumpWidget(
        testFrame(
          child: SizedBox(
            width: 1200,
            height: 900,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('outside-target'),
                    onTap: () {},
                    child: Container(color: Colors.transparent),
                  ),
                ),
                const DesktopAudioControlCenterOverlay(),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WindowsLiveAudioMonitorCard), findsOneWidget);
      expect(find.byType(WindowsAudioQuickSettingsPanel), findsOneWidget);

      // Tap outside top-left
      await tester.tapAt(const Offset(50, 50));
      await tester.pumpAndSettle();

      expect(desktopAudioQuickSettingsOpen.value, isFalse);
      expect(desktopLiveAudioMonitorOpen.value, isFalse);
      expect(find.byType(WindowsLiveAudioMonitorCard), findsNothing);
      expect(find.byType(WindowsAudioQuickSettingsPanel), findsNothing);
    });

    testWidgets('Desktop overlay never renders orphan monitor if ACC is closed',
        (tester) async {
      desktopAudioQuickSettingsOpen.value = false;
      desktopLiveAudioMonitorOpen.value = true; // Stale or orphan monitor state

      await tester.pumpWidget(
        testFrame(
          child: const SizedBox(
            width: 1200,
            height: 900,
            child: Stack(children: [DesktopAudioControlCenterOverlay()]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WindowsLiveAudioMonitorCard), findsNothing);
      expect(find.byType(WindowsAudioQuickSettingsPanel), findsNothing);
    });
  });

  group('Format selection and persistence', () {
    testWidgets(
      'provides selectable sample rate options and persists changes',
      (tester) async {
        await tester.pumpWidget(
          testFrame(
            child: const SizedBox(
              width: 400,
              child: WindowsAudioQuickSettingsPanel(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find Sample Rate dropdown
        final dropdown = find.byType(DropdownButton<int>);
        expect(dropdown, findsOneWidget);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();

        // Options like 48k, 96k, 192k should be present
        expect(find.text('48k').last, findsOneWidget);
        expect(find.text('96k').last, findsOneWidget);

        // Select 96k
        await tester.tap(find.text('96k').last);
        await tester.pumpAndSettle();

        // Verify the selected value updated
        final container = ProviderScope.containerOf(
          tester.element(find.byType(WindowsAudioQuickSettingsPanel)),
        );
        expect(container.read(settingsProvider).windowsOutputSampleRate, 96000);
      },
    );
  });
}
