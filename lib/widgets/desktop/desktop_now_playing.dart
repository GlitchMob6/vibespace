import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibespace/controllers/player_metadata_controller.dart';
import 'package:vibespace/l10n/l10n.dart';
import 'package:vibespace/providers/music_player_provider.dart';
import 'package:vibespace/providers/theme_provider.dart';
import 'package:vibespace/services/music_playback_deck.dart'
    show WindowsAudioStatus, windowsAudioStatus;
import 'package:vibespace/theme/mornye_theme.dart';
import 'package:vibespace/theme/player_artwork_theme.dart';
import 'package:vibespace/utils/playback_seek_preview.dart';
import 'package:vibespace/widgets/app_icon.dart';
import 'package:vibespace/widgets/desktop/desktop_inspector.dart';
import 'package:vibespace/widgets/desktop/desktop_window.dart';
import 'package:vibespace/widgets/desktop/windows_audio_quick_settings.dart';
import 'package:vibespace/widgets/material_player_backdrop.dart';
import 'package:vibespace/widgets/mornye_player_background.dart';
import 'package:vibespace/widgets/mornye_player_favorite_button.dart';
import 'package:vibespace/widgets/no_scrollbars.dart';
import 'package:vibespace/widgets/player_artwork.dart';
import 'package:vibespace/widgets/player_lyrics_section.dart';
import 'package:vibespace/widgets/player_metadata_title.dart';
import 'package:vibespace/widgets/player_playback_controls.dart';
import 'package:vibespace/widgets/player_volume_control.dart';

/// The three listening presentation modes in fullscreen / expanded preview.
enum FullscreenListeningMode {
  coverOnly,
  lyrics,
  audio,
}

/// The contextual left-side panel view (Lyrics or Audio Control Center).
enum FullscreenContextualPanel {
  lyrics,
  audio,
}

/// Now Playing on the desktop, covering the whole window in Expanded Preview
/// or True Fullscreen.
///
/// Features a two-region composition:
/// - Left region: contextual side panel switching between Synchronized Lyrics
///   and Audio Control Center (with Live Audio Stream Monitor), or collapsible
///   for pure Cover Only listening.
/// - Main region: Now Playing stage with prominent album cover, metadata,
///   audio quality telemetry, seek preview, and transport controls.
class DesktopNowPlaying extends ConsumerStatefulWidget {
  const DesktopNowPlaying({
    super.key,
    this.metadataControllerFactory,
    this.initialMode,
  });

  final PlayerMetadataController Function()? metadataControllerFactory;
  final FullscreenListeningMode? initialMode;

  @override
  ConsumerState<DesktopNowPlaying> createState() => _DesktopNowPlayingState();
}

class _DesktopNowPlayingState extends ConsumerState<DesktopNowPlaying> {
  late final _metadata =
      widget.metadataControllerFactory?.call() ?? PlayerMetadataController();
  final _seekPreview = PlaybackSeekPreview();
  ProviderSubscription<AsyncValue<MediaItem?>>? _mediaItemSub;

  late FullscreenContextualPanel _contextualPanel;
  FullscreenContextualPanel? _lastContextualPanel;
  late bool _isPanelVisible;

  // Auto-hide transient fullscreen controls
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _isInteracting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialMode != null) {
      switch (widget.initialMode!) {
        case FullscreenListeningMode.coverOnly:
          _isPanelVisible = false;
          _contextualPanel = FullscreenContextualPanel.lyrics;
          _lastContextualPanel = null;
        case FullscreenListeningMode.lyrics:
          _isPanelVisible = true;
          _contextualPanel = FullscreenContextualPanel.lyrics;
          _lastContextualPanel = FullscreenContextualPanel.lyrics;
        case FullscreenListeningMode.audio:
          _isPanelVisible = true;
          _contextualPanel = FullscreenContextualPanel.audio;
          _lastContextualPanel = FullscreenContextualPanel.audio;
          desktopLiveAudioMonitorOpen.value = true;
      }
    } else {
      if (desktopInspectorPanel.value == DesktopInspectorPanel.lyrics) {
        _isPanelVisible = true;
        _contextualPanel = FullscreenContextualPanel.lyrics;
        _lastContextualPanel = FullscreenContextualPanel.lyrics;
      } else {
        _isPanelVisible = false;
        _contextualPanel = FullscreenContextualPanel.lyrics;
        _lastContextualPanel = null;
      }
    }

    desktopInspectorPanel.addListener(_onInspectorPanelChanged);

    _mediaItemSub = ref.listenManual<AsyncValue<MediaItem?>>(
      currentMediaItemProvider,
      (previous, next) {
        if (previous?.value?.id != next.value?.id) _seekPreview.reset();
        if (previous?.value?.id == next.value?.id && previous != null) return;
        unawaited(
          _metadata.load(next.value, inspectUnresolvedContentUri: true),
        );
      },
      fireImmediately: true,
    );

    _resetHideTimer();
  }

  void _onInspectorPanelChanged() {
    final panel = desktopInspectorPanel.value;
    if (panel == DesktopInspectorPanel.lyrics) {
      if (!_isPanelVisible ||
          _contextualPanel != FullscreenContextualPanel.lyrics) {
        setState(() {
          _contextualPanel = FullscreenContextualPanel.lyrics;
          _lastContextualPanel = FullscreenContextualPanel.lyrics;
          _isPanelVisible = true;
        });
      }
    } else if (panel == DesktopInspectorPanel.upNext) {
      if (_contextualPanel == FullscreenContextualPanel.audio) {
        desktopLiveAudioMonitorOpen.value = false;
      }
      setState(() {
        _isPanelVisible = false;
        _lastContextualPanel = null;
      });
    } else if (panel == null && widget.initialMode == null) {
      if (_isPanelVisible &&
          _contextualPanel == FullscreenContextualPanel.lyrics) {
        setState(() {
          _isPanelVisible = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_contextualPanel == FullscreenContextualPanel.audio) {
      desktopLiveAudioMonitorOpen.value = false;
    }
    desktopInspectorPanel.removeListener(_onInspectorPanelChanged);
    _hideTimer?.cancel();
    _mediaItemSub?.close();
    _metadata.dispose();
    _seekPreview.dispose();
    super.dispose();
  }

  void _onUserActivity() {
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    final autoHide = ref.read(themeProvider).fullscreenControlsAutoHide;
    if (!autoHide) {
      if (!_controlsVisible && mounted) {
        setState(() => _controlsVisible = true);
      }
      return;
    }
    final isPlaying = ref.read(playbackPlayingProvider);
    if (!isPlaying || _isInteracting) return;

    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _isInteracting) return;
      final autoHideNow = ref.read(themeProvider).fullscreenControlsAutoHide;
      if (!autoHideNow) return;
      final playingNow = ref.read(playbackPlayingProvider);
      if (!playingNow) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _togglePanelVisibility([FullscreenContextualPanel? targetPanel]) {
    setState(() {
      if (targetPanel != null) {
        if (_isPanelVisible && _contextualPanel == targetPanel) {
          _isPanelVisible = false;
          desktopInspectorPanel.value = null;
          if (targetPanel == FullscreenContextualPanel.audio) {
            desktopLiveAudioMonitorOpen.value = false;
          }
        } else {
          final previousPanel = _contextualPanel;
          _contextualPanel = targetPanel;
          _lastContextualPanel = targetPanel;
          _isPanelVisible = true;
          if (targetPanel == FullscreenContextualPanel.audio) {
            desktopLiveAudioMonitorOpen.value = true;
            desktopInspectorPanel.value = null;
          } else {
            if (previousPanel == FullscreenContextualPanel.audio) {
              desktopLiveAudioMonitorOpen.value = false;
            }
            desktopInspectorPanel.value = DesktopInspectorPanel.lyrics;
          }
        }
      } else {
        _isPanelVisible = !_isPanelVisible;
        if (_isPanelVisible) {
          _lastContextualPanel = _contextualPanel;
          if (_contextualPanel == FullscreenContextualPanel.audio) {
            desktopLiveAudioMonitorOpen.value = true;
            desktopInspectorPanel.value = null;
          } else {
            desktopInspectorPanel.value = DesktopInspectorPanel.lyrics;
          }
        } else {
          if (_contextualPanel == FullscreenContextualPanel.audio) {
            desktopLiveAudioMonitorOpen.value = false;
          }
          desktopInspectorPanel.value = null;
        }
      }
    });
    _onUserActivity();
  }

  /// Spacing from top edge for floating controls.
  static const double _controlsTop = 20.0;

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    if (context.isMornye) return _buildPlayer(context, mediaItem);
    return PlayerArtworkTheme(
      artUri: mediaItem?.artUri?.toString(),
      child: Builder(builder: (context) => _buildPlayer(context, mediaItem)),
    );
  }

  Widget _buildPlayer(BuildContext context, MediaItem? mediaItem) {
    final mornye = context.isMornye;
    final theme = mornye
        ? MornyeTheme.fromContext(context, brightness: Brightness.dark)
        : Theme.of(context);
    final colorScheme = theme.colorScheme;
    final showTopVolume =
        !(_isPanelVisible && _contextualPanel == FullscreenContextualPanel.audio);

    return Theme(
      data: theme,
      child: Material(
        type: MaterialType.transparency,
        child: MouseRegion(
          onHover: (_) => _onUserActivity(),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              _isInteracting = true;
              _onUserActivity();
            },
            onPointerUp: (_) {
              _isInteracting = false;
              _resetHideTimer();
            },
            onPointerCancel: (_) {
              _isInteracting = false;
              _resetHideTimer();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Backdrop
                if (mornye)
                  MornyePlayerBackground(artUri: mediaItem?.artUri)
                else if (mediaItem != null)
                  MaterialPlayerBackdrop(
                    mediaItem: mediaItem,
                    colorScheme: colorScheme,
                    showArtwork: false,
                  )
                else
                  ColoredBox(color: colorScheme.surface),

                // Main two-region layout
                if (mediaItem == null)
                  Center(
                    child: Text(
                      context.l10n.nowPlayingNothingPlaying,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  _layout(context, mediaItem, colorScheme),

                // Top window drag area (disabled in True Fullscreen)
                ValueListenableBuilder<bool>(
                  valueListenable: desktopWindowFullScreen,
                  builder: (context, fullScreen, child) =>
                      fullScreen ? const SizedBox.shrink() : child!,
                  child: const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: desktopTitleBarHeight,
                    child: DesktopWindowDragArea(zoomOnDoubleClick: true),
                  ),
                ),

                // Volume slider at top-left (only when Audio mode is NOT active, transient)
                if (showTopVolume)
                  ValueListenableBuilder<bool>(
                    valueListenable: desktopWindowFullScreen,
                    builder: (context, fullScreen, child) =>
                        PositionedDirectional(
                      top: _controlsTop,
                      start: desktopTitleBarInContentFor(context) && !fullScreen
                          ? desktopWindowControlsWidth + 12
                          : 20,
                      width: 260,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: !_controlsVisible,
                          child: child,
                        ),
                      ),
                    ),
                    child: _Capsule(
                      child: PlayerVolumeControl(
                        foreground:
                            mornye ? Colors.white : colorScheme.onSurface,
                      ),
                    ),
                  ),

                // Close button at top-right (transient)
                PositionedDirectional(
                  top: _controlsTop,
                  end: 20,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: _RoundButton(
                        key: const ValueKey('desktop-now-playing-close'),
                        tooltip:
                            MaterialLocalizations.of(context).closeButtonTooltip,
                        icon: mornye ? CupertinoIcons.xmark : Icons.close,
                        onPressed: closeDesktopNowPlaying,
                      ),
                    ),
                  ),
                ),

                // Bottom-right quick controls capsule (transient)
                PositionedDirectional(
                  bottom: 20,
                  end: 20,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: _Capsule(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RoundButton(
                              key: const ValueKey(
                                'desktop-now-playing-cover-only-toggle',
                              ),
                              tooltip: 'Cover Only',
                              icon: mornye
                                  ? CupertinoIcons.square_stack
                                  : Icons.album_outlined,
                              selected: !_isPanelVisible,
                              onPressed: () {
                                setState(() {
                                  _isPanelVisible = false;
                                  desktopInspectorPanel.value = null;
                                });
                                _onUserActivity();
                              },
                            ),
                            const SizedBox(width: 4),
                            _RoundButton(
                              key: const ValueKey(
                                'desktop-now-playing-lyrics-toggle',
                              ),
                              tooltip: context.l10n.nowPlayingTabLyrics,
                              icon: mornye
                                  ? CupertinoIcons.quote_bubble
                                  : Icons.lyrics_outlined,
                              selected: _isPanelVisible &&
                                  _contextualPanel ==
                                      FullscreenContextualPanel.lyrics,
                              onPressed: () => _togglePanelVisibility(
                                FullscreenContextualPanel.lyrics,
                              ),
                            ),
                            const SizedBox(width: 4),
                            _RoundButton(
                              key: const ValueKey(
                                'desktop-now-playing-audio-toggle',
                              ),
                              tooltip: 'Audio Control Center',
                              icon: Icons.tune,
                              selected: _isPanelVisible &&
                                  _contextualPanel ==
                                      FullscreenContextualPanel.audio,
                              onPressed: () => _togglePanelVisibility(
                                FullscreenContextualPanel.audio,
                              ),
                            ),
                            const SizedBox(width: 4),
                            ValueListenableBuilder<DesktopWindowMode>(
                              valueListenable: desktopWindowMode,
                              builder: (context, mode, _) {
                                final isFullscreen =
                                    mode == DesktopWindowMode.fullscreen;
                                return _RoundButton(
                                  key: const ValueKey(
                                    'desktop-now-playing-fullscreen-toggle',
                                  ),
                                  tooltip: isFullscreen
                                      ? context.l10n.desktopExitFullscreen
                                      : context.l10n.desktopWindowFullscreen,
                                  icon: isFullscreen
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                  onPressed: toggleDesktopFullScreen,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout(
    BuildContext context,
    MediaItem mediaItem,
    ColorScheme colorScheme,
  ) {
    if (_isPanelVisible &&
        desktopInspectorPanel.value != DesktopInspectorPanel.upNext) {
      _lastContextualPanel = _contextualPanel;
    }
    final reduce = MediaQuery.disableAnimationsOf(context);
    const motion = Duration(milliseconds: 260);

    return LayoutBuilder(
      builder: (context, constraints) => TweenAnimationBuilder<double>(
        tween: Tween(end: _isPanelVisible ? 1.0 : 0.0),
        duration: reduce ? Duration.zero : motion,
        curve: Curves.easeInOutCubic,
        onEnd: () {
          if (!_isPanelVisible && mounted) {
            setState(() => _lastContextualPanel = null);
          }
        },
        builder: (context, progress, _) => _sideLayout(
          context,
          constraints,
          mediaItem,
          colorScheme,
          progress,
        ),
      ),
    );
  }

  Widget _sideLayout(
    BuildContext context,
    BoxConstraints constraints,
    MediaItem mediaItem,
    ColorScheme colorScheme,
    double progress,
  ) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final size = progress.clamp(0.0, 1.0);

    // Responsive side panel width for Audio Control Center
    const double maxPanelWidth = 390.0;
    final double panelWidth = width >= 1000
        ? maxPanelWidth
        : math.max(280.0, math.min(maxPanelWidth, width * 0.38));

    final panel = _lastContextualPanel;
    final bool isAudioActive = panel == FullscreenContextualPanel.audio;
    final bool showsLyrics = panel == FullscreenContextualPanel.lyrics;
    final bool showsAudio = panel == FullscreenContextualPanel.audio;

    final leading = width * 5 / 11;

    // Remaining horizontal space for stage when Audio mode is active on left
    const double panelMargin = 24.0;
    const double panelGap = 24.0;
    final double remainingStageWidth = math.max(
      280.0,
      width - (panelMargin + panelWidth + panelGap) - panelMargin,
    );

    // Stage center depending on active mode:
    // When Audio active: stage is on the right of Audio panel
    // When Lyrics active: stage is on the left 5/11 of the screen
    final double sideStageCenterX = isAudioActive
        ? (panelMargin + panelWidth + panelGap) + remainingStageWidth / 2
        : leading / 2;

    final double centerX = lerpDouble(width / 2, sideStageCenterX, size)!;

    // Artwork and column width bounds
    double columnWidthFor(double maxLimit, double containerLimit) =>
        math.max(220.0, math.min(maxLimit, math.min(containerLimit, height - 260.0)));

    final double fullWidthLimit = columnWidthFor(520.0, width - 64.0);
    final double lyricsWidthLimit =
        columnWidthFor(math.min(440.0, width * 0.34), leading - 32.0);
    final double audioWidthLimit =
        columnWidthFor(440.0, remainingStageWidth - 32.0);

    final double sideColumnWidthLimit =
        isAudioActive ? audioWidthLimit : lyricsWidthLimit;
    final double columnWidth =
        lerpDouble(fullWidthLimit, sideColumnWidthLimit, size)!;

    final player = SizedBox(
      width: columnWidth,
      child: _PlayerColumn(
        mediaItem: mediaItem,
        metadata: _metadata,
        seekPreview: _seekPreview,
        colorScheme: colorScheme,
        artworkSize: columnWidth,
        decodeSize: columnWidthFor(520.0, width),
      ),
    );

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final slide = ((1.0 - size) * 48.0 * pixelRatio).roundToDouble() / pixelRatio;

    final switchDuration = MediaQuery.disableAnimationsOf(context) || size < 0.5
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Stack(
      children: [
        // Main Now Playing stage (artwork + metadata + controls)
        Positioned.directional(
          textDirection: Directionality.of(context),
          start: centerX - columnWidth / 2,
          top: 0,
          bottom: 0,
          width: columnWidth,
          child: Center(child: player),
        ),

        // Synchronized Lyrics presentation: spacious, directly over ambient background
        // occupying trailing 6/11 region on the right
        PositionedDirectional(
          start: leading,
          end: 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            key: const ValueKey('desktop-now-playing-lyrics'),
            ignoring: !showsLyrics || size < 0.2,
            child: ExcludeFocus(
              excluding: !showsLyrics || size == 0,
              child: Opacity(
                opacity: showsLyrics ? size : 0.0,
                child: Transform.translate(
                  offset: Offset(slide * (rtl ? -1.0 : 1.0), 0),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      0,
                      72,
                      48,
                      80,
                    ),
                    child: AnimatedOpacity(
                      opacity: showsLyrics ? 1.0 : 0.0,
                      duration: switchDuration,
                      child: NoScrollbars(
                        child: KeyedSubtree(
                          key: const ValueKey('desktop-contextual-lyrics-view'),
                          child: PlayerLyricsSection(
                            metadata: _metadata,
                            seekPreview: _seekPreview,
                            colorScheme: colorScheme,
                            isActive: true,
                            animateWords: showsLyrics,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Audio Control Center on the LEFT (Live Stream Monitor + Quick Settings)
        if (isAudioActive)
          PositionedDirectional(
            start: panelMargin,
            top: 24.0,
            bottom: 24.0,
            width: panelWidth,
            child: IgnorePointer(
              ignoring: !showsAudio || size < 0.2,
              child: ExcludeFocus(
                excluding: !showsAudio || size == 0,
                child: Opacity(
                  opacity: showsAudio ? size : 0.0,
                  child: Transform.translate(
                    offset: Offset(-slide * (rtl ? -1.0 : 1.0), 0),
                    child: KeyedSubtree(
                      key: const ValueKey('desktop-contextual-audio-view'),
                      child: _AudioControlCenterSideView(
                        onClose: () => _togglePanelVisibility(
                          FullscreenContextualPanel.audio,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Audio Control Center side panel in Fullscreen / Expanded Preview.
/// Displays the Live Audio Stream Monitor stacked directly above Audio Quick Settings
/// with a 10px vertical gap, both sharing matching widths and acrylic glass styling.
class _AudioControlCenterSideView extends StatelessWidget {
  const _AudioControlCenterSideView({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: desktopLiveAudioMonitorOpen,
      builder: (context, monitorOpen, _) {
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (monitorOpen) ...[
                WindowsLiveAudioMonitorCard(
                  isFloating: false,
                  onDismiss: closeDesktopLiveAudioMonitor,
                ),
                const SizedBox(height: 10),
              ],
              WindowsAudioQuickSettingsPanel(
                onClose: onClose,
                showCloseButton: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerColumn extends StatelessWidget {
  const _PlayerColumn({
    required this.mediaItem,
    required this.metadata,
    required this.seekPreview,
    required this.colorScheme,
    required this.artworkSize,
    required this.decodeSize,
  });

  final MediaItem mediaItem;
  final PlayerMetadataController metadata;
  final PlaybackSeekPreview seekPreview;
  final ColorScheme colorScheme;
  final double artworkSize;
  final double decodeSize;

  @override
  Widget build(BuildContext context) {
    final mornye = context.isMornye;
    final textTheme = Theme.of(context).textTheme;
    final corners = BorderRadius.circular(mornye ? 12 : 28);
    final artwork = PlayerArtwork(
      artUri: mediaItem.artUri?.toString(),
      colorScheme: colorScheme,
      iconSize: 96,
      cacheWidth: (decodeSize * MediaQuery.devicePixelRatioOf(context)).round(),
    );
    final subtitle = [
      mediaItem.artist,
      mediaItem.album,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Prominent artwork
        Center(
          child: SizedBox.square(
            dimension: artworkSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: corners,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 32,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: mornye
                  ? ClipRSuperellipse(borderRadius: corners, child: artwork)
                  : ClipRRect(borderRadius: corners, child: artwork),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Track title & artist
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlayerMetadataTitle(
                    mediaItem: mediaItem,
                    metadata: metadata,
                    style: (mornye
                            ? textTheme.titleMedium
                            : textTheme.titleLarge)
                        ?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (mornye
                                ? textTheme.bodyMedium
                                : textTheme.titleSmall)
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            if (mornye)
              MornyePlayerFavoriteButton(
                mediaItem: mediaItem,
                color: colorScheme.onSurface,
                iconSize: 20,
              ),
          ],
        ),

        // Audio stream telemetry / format badge
        _AudioBadgeRow(mediaItem: mediaItem, metadata: metadata),

        // Playback progress slider and transport controls
        PlayerPlaybackControls(
          key: ValueKey(mediaItem.id),
          mediaId: mediaItem.id,
          duration: mediaItem.duration ?? Duration.zero,
          seekPreview: seekPreview,
          colorScheme: colorScheme,
          metadata: metadata,
          compact: true,
          edgeAligned: true,
        ),
      ],
    );
  }
}

/// Displays live stream telemetry or probed track format badges.
class _AudioBadgeRow extends StatelessWidget {
  const _AudioBadgeRow({
    required this.mediaItem,
    required this.metadata,
  });

  final MediaItem mediaItem;
  final PlayerMetadataController metadata;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<WindowsAudioStatus>(
      valueListenable: windowsAudioStatus,
      builder: (context, status, _) {
        final List<Widget> badges = [];

        if (status.isBitPerfect) {
          badges.add(
            _BadgeChip(
              text: 'BIT-PERFECT',
              highlight: true,
              color: colors.primary,
            ),
          );
        }

        if (status.sampleRate != null && status.sampleRate! > 0) {
          final rateStr = status.sampleRate! >= 1000
              ? '${(status.sampleRate! / 1000).toStringAsFixed(status.sampleRate! % 1000 == 0 ? 0 : 1)} kHz'
              : '${status.sampleRate} Hz';
          final bitsStr = status.bitDepth != null && status.bitDepth! > 0
              ? '${status.bitDepth}-bit'
              : '';
          final text = [rateStr, bitsStr].where((s) => s.isNotEmpty).join(' · ');
          badges.add(_BadgeChip(text: text));
        } else if (metadata.metadata != null) {
          final m = metadata.metadata!;
          final codec = m['codec']?.toString().toUpperCase() ?? '';
          final rate = m['sample_rate'] != null
              ? '${((m['sample_rate'] as num) / 1000).toStringAsFixed(1)} kHz'
              : '';
          final text = [codec, rate].where((s) => s.isNotEmpty).join(' · ');
          if (text.isNotEmpty) {
            badges.add(_BadgeChip(text: text));
          }
        }

        if (badges.isEmpty) return const SizedBox(height: 6);

        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: badges,
          ),
        );
      },
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.text,
    this.highlight = false,
    this.color,
  });

  final String text;
  final bool highlight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = color ?? colors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: highlight
            ? accent.withValues(alpha: 0.16)
            : colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight
              ? accent.withValues(alpha: 0.45)
              : colors.outlineVariant.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
          letterSpacing: 0.3,
          color: highlight ? accent : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = context.isMornye
        ? Colors.white.withValues(alpha: 0.12)
        : scheme.surfaceContainerHigh.withValues(alpha: 0.72);
    return DecoratedBox(
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      child: Padding(padding: const EdgeInsets.all(4), child: child),
    );
  }
}

/// A round icon button over the artwork backdrop; [selected] fills it.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (context.isMornye) {
      return Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: selected,
          child: CupertinoButton(
            minimumSize: const Size.square(36),
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.12),
            onPressed: onPressed,
            child: AppIcon(
              icon,
              size: 18,
              color: selected ? Colors.black : Colors.white,
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        foregroundColor: selected
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant,
      ),
      icon: AppIcon(icon),
      onPressed: onPressed,
    );
  }
}
