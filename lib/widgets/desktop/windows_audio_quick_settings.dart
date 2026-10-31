import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibespace/providers/settings_provider.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/services/windows_audio_device_service.dart';
import 'package:vibespace/widgets/player_volume_control.dart';

/// The live WASAPI readout. It is intentionally its own Material surface so
/// it can sit beside (not inside) the Audio Quick Settings surface.
class WindowsLiveAudioMonitorCard extends StatelessWidget {
  const WindowsLiveAudioMonitorCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ValueListenableBuilder<WindowsAudioStatus>(
      valueListenable: windowsAudioStatus,
      builder: (context, status, _) {
        final bitPerfect = status.isBitPerfect;
        final exclusive = status.mode.startsWith('exclusive');
        final accent = bitPerfect
            ? Colors.green
            : exclusive
            ? colors.primary
            : Colors.amber;

        String format(int? rate, int? depth, String? sampleFormat) {
          if (rate == null) return 'Awaiting playback…';
          final detail = sampleFormat == null || sampleFormat.isEmpty
              ? ''
              : ' ($sampleFormat)';
          return '$rate Hz · ${depth ?? '—'}-bit$detail';
        }

        return Material(
          color: colors.surfaceContainerHigh,
          elevation: 4,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withValues(alpha: bitPerfect ? 0.65 : 0.28),
                width: bitPerfect ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      exclusive ? Icons.lock_outline : Icons.graphic_eq,
                      color: accent,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'LIVE AUDIO STREAM MONITOR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.65,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        bitPerfect
                            ? 'BIT-PERFECT'
                            : exclusive
                            ? (status.mode == 'exclusive_push'
                                ? 'EXCLUSIVE PUSH'
                                : 'EXCLUSIVE EVENT')
                            : 'SHARED',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MonitorValue(
                        label: 'DAC HARDWARE OUTPUT',
                        value: format(
                          status.sampleRate,
                          status.bitDepth,
                          status.format,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MonitorValue(
                        label: 'SOURCE TRACK FORMAT',
                        value: format(
                          status.sourceSampleRate,
                          status.sourceBitDepth,
                          status.sourceFormat,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  'Endpoint: ${status.device ?? 'Default'} · '
                  '${status.driver.toUpperCase()} · '
                  'State: ${status.reason.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.65,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        bitPerfect ? Icons.check_circle_outline : Icons.info_outline,
                        size: 15,
                        color: accent,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          status.bitPerfectReason ??
                              (status.sampleRate == null
                                  ? 'Start playback to inspect the negotiated output stream.'
                                  : 'Playback is active; bit-perfect output is not currently verified.'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: bitPerfect ? Colors.green : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MonitorValue extends StatelessWidget {
  const _MonitorValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 9,
            letterSpacing: 0.25,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Compact Windows audio controls. The panel reads and writes the same
/// settings and device service used by WindowsAudioOutputPage.
class WindowsAudioQuickSettingsPanel extends ConsumerStatefulWidget {
  const WindowsAudioQuickSettingsPanel({super.key});

  @override
  ConsumerState<WindowsAudioQuickSettingsPanel> createState() =>
      _WindowsAudioQuickSettingsPanelState();
}

class _WindowsAudioQuickSettingsPanelState
    extends ConsumerState<WindowsAudioQuickSettingsPanel> {
  final WindowsAudioDeviceService _devices = WindowsAudioDeviceService.instance;
  WindowsDeviceCapabilities? _capabilities;
  bool _loadingCapabilities = false;
  String? _requestedDevice;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _devices.addListener(_onDevicesChanged);
  }

  @override
  void dispose() {
    _devices.removeListener(_onDevicesChanged);
    super.dispose();
  }

  void _onDevicesChanged() {
    if (mounted) setState(() {});
  }

  void _loadCapabilitiesFor(String deviceId) {
    if (_requestedDevice == deviceId) return;
    _requestedDevice = deviceId;
    final generation = ++_requestGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _loadingCapabilities = true);
      final capabilities = await _devices.getDeviceCapabilities(deviceId);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _capabilities = capabilities;
        _loadingCapabilities = false;
      });
    });
  }

  String _rateLabel(int rate) => switch (rate) {
    0 => 'Auto',
    44100 => '44.1k',
    48000 => '48k',
    88200 => '88.2k',
    96000 => '96k',
    176400 => '176.4k',
    192000 => '192k',
    352800 => '352.8k',
    384000 => '384k',
    _ => '${(rate / 1000).toStringAsFixed(1)}k',
  };

  String _formatLabel(String format) => switch (format) {
    'auto' => 'Auto',
    's16' => '16-bit',
    's24' => '24-bit',
    's32' => '32-bit',
    'float' => '32f',
    _ => format,
  };

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final colors = Theme.of(context).colorScheme;
    _loadCapabilitiesFor(settings.windowsOutputDevice);

    final exclusive = settings.windowsOutputMode.startsWith('exclusive');
    final probedRates = _capabilities == null
        ? const <int>[]
        : exclusive
        ? _capabilities!.exclusiveRates
        : _capabilities!.sharedRates;
    final rates = <int>{0, ...probedRates};
    if (!rates.contains(settings.windowsOutputSampleRate)) {
      rates.add(settings.windowsOutputSampleRate);
    }
    final sortedRates = rates.toList()..sort();

    final rateKey = settings.windowsOutputSampleRate == 0
        ? ''
        : settings.windowsOutputSampleRate.toString();
    final probedFormats = _capabilities == null
        ? const <String>[]
        : (_capabilities!.formatsByRate[rateKey] ??
              (exclusive
                  ? _capabilities!.exclusiveFormats
                  : _capabilities!.sampleFormats));
    final formats = <String>{
      'auto',
      ...probedFormats,
      settings.windowsOutputSampleFormat,
    }.toList();

    final devices = _devices.endpoints;
    final selectedDevice = settings.windowsOutputDevice;
    final validDevice = selectedDevice.isEmpty ||
        devices.any((device) =>
            device.mpvDeviceId == selectedDevice ||
            device.id == selectedDevice ||
            device.guid == selectedDevice);
    final deviceValue = validDevice ? selectedDevice : '';

    return Material(
      color: colors.surfaceContainerHigh,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 17),
                const SizedBox(width: 8),
                Text(
                  'AUDIO QUICK SETTINGS',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.65,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('VOLUME', style: _sectionLabel(context)),
            const SizedBox(height: 2),
            const PlayerVolumeControl(),
            const Divider(height: 18),
            Text('AUDIO ENGINE', style: _sectionLabel(context)),
            const SizedBox(height: 7),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                ),
                textStyle: WidgetStatePropertyAll(
                  Theme.of(context).textTheme.labelSmall,
                ),
              ),
              segments: const [
                ButtonSegment(value: 'shared', label: Text('Shared')),
                ButtonSegment(
                  value: 'exclusive_event',
                  label: Text('Exclusive Event'),
                ),
                ButtonSegment(
                  value: 'exclusive_push',
                  label: Text('Exclusive Push'),
                ),
              ],
              selected: {
                switch (settings.windowsOutputMode) {
                  'exclusive_push' => 'exclusive_push',
                  'exclusive' || 'exclusive_event' => 'exclusive_event',
                  _ => 'shared',
                },
              },
              onSelectionChanged: (selected) {
                ref
                    .read(settingsProvider.notifier)
                    .setWindowsOutputMode(selected.first);
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Automatic fallback to Shared',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Switch.adaptive(
                  value: settings.windowsExclusiveFallback,
                  onChanged: (value) => ref
                      .read(settingsProvider.notifier)
                      .setWindowsExclusiveFallback(value),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const Divider(height: 18),
            Text('OUTPUT FORMAT', style: _sectionLabel(context)),
            const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _FormatDropdown<int>(
                    label: 'Sample Rate',
                    value: settings.windowsOutputSampleRate,
                    items: [
                      for (final rate in sortedRates)
                        DropdownMenuItem(
                          value: rate,
                          child: Text(_rateLabel(rate)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .setWindowsOutputSampleRate(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _FormatDropdown<String>(
                    label: 'Sample Format',
                    value: formats.contains(settings.windowsOutputSampleFormat)
                        ? settings.windowsOutputSampleFormat
                        : 'auto',
                    items: [
                      for (final format in formats)
                        DropdownMenuItem(
                          value: format,
                          child: Text(_formatLabel(format)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .setWindowsOutputSampleFormat(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _FormatDropdown<String>(
                    label: 'Channels',
                    value: settings.windowsOutputChannels,
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Auto')),
                      DropdownMenuItem(value: 'stereo', child: Text('Stereo')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .setWindowsOutputChannels(value);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (_loadingCapabilities)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  'Checking device capabilities…',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            else if (_capabilities != null)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  'Hardware: ${_capabilities!.exclusiveRates.length} exclusive rates · '
                  '${_capabilities!.exclusiveFormats.length} formats probed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            const Divider(height: 18),
            Text('OUTPUT DEVICE', style: _sectionLabel(context)),
            const SizedBox(height: 4),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: deviceValue,
                isExpanded: true,
                isDense: true,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('System Default (Automatic)'),
                  ),
                  for (final device in devices)
                    DropdownMenuItem(
                      value: device.mpvDeviceId,
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setWindowsOutputDevice(value);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _sectionLabel(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.55,
      );
}

class _FormatDropdown<T> extends StatelessWidget {
  const _FormatDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            isExpanded: true,
            isDense: true,
            iconSize: 16,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}
