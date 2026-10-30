import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibespace/providers/settings_provider.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/services/windows_audio_device_service.dart';
import 'package:vibespace/widgets/app_sliver_header.dart';
import 'package:vibespace/widgets/settings_group.dart';

class WindowsAudioOutputPage extends ConsumerStatefulWidget {
  const WindowsAudioOutputPage({super.key});

  @override
  ConsumerState<WindowsAudioOutputPage> createState() =>
      _WindowsAudioOutputPageState();
}

class _WindowsAudioOutputPageState
    extends ConsumerState<WindowsAudioOutputPage> {
  final WindowsAudioDeviceService _deviceService =
      WindowsAudioDeviceService.instance;

  WindowsDeviceCapabilities? _deviceCapabilities;
  WindowsMixFormat? _deviceMixFormat;
  bool _loadingCapabilities = false;

  @override
  void initState() {
    super.initState();
    _deviceService.addListener(_onDevicesChanged);
    _loadCapabilities();
  }

  @override
  void dispose() {
    _deviceService.removeListener(_onDevicesChanged);
    super.dispose();
  }

  void _onDevicesChanged() {
    if (mounted) {
      setState(() {});
      _loadCapabilities();
    }
  }

  Future<void> _loadCapabilities() async {
    if (!Platform.isWindows) return;
    final settings = ref.read(settingsProvider);
    final targetDevice = settings.windowsOutputDevice;

    setState(() => _loadingCapabilities = true);
    final caps = await _deviceService.getDeviceCapabilities(targetDevice);
    final mix = await _deviceService.getDeviceMixFormat(targetDevice);
    if (mounted) {
      setState(() {
        _deviceCapabilities = caps;
        _deviceMixFormat = mix;
        _loadingCapabilities = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final endpoints = _deviceService.endpoints;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(
            title: 'Windows Audio Output',
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Devices',
                onPressed: () async {
                  await _deviceService.refreshEndpoints();
                  await _loadCapabilities();
                },
              ),
            ],
          ),

          // SECTION D: Live Output Monitor (Put prominently at the top for instant feedback)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _buildLiveMonitorCard(context),
            ),
          ),

          // SECTION A: Output Device
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'OUTPUT DEVICE',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                // System Default Option
                SettingsItem(
                  icon: Icons.speaker_group_outlined,
                  title: 'System Default (Automatic)',
                  subtitle: 'Follows active Windows default console device',
                  trailing: settings.windowsOutputDevice.isEmpty
                      ? Icon(Icons.check_circle, color: colorScheme.primary)
                      : const Icon(Icons.radio_button_unchecked),
                  onTap: () {
                    ref
                        .read(settingsProvider.notifier)
                        .setWindowsOutputDevice('');
                    _loadCapabilities();
                  },
                ),
                // Core Audio Enumerated Endpoints
                for (final ep in endpoints)
                  SettingsItem(
                    icon: ep.name.toLowerCase().contains('iem') ||
                            ep.name.toLowerCase().contains('headphone')
                        ? Icons.headphones
                        : Icons.speaker,
                    title: ep.name,
                    subtitle: '${ep.mpvDeviceId}${ep.isDefault ? " • Default" : ""}',
                    titleTrailing: ep.isDefault
                        ? Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'DEFAULT',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : null,
                    trailing: (settings.windowsOutputDevice == ep.id ||
                            settings.windowsOutputDevice == ep.mpvDeviceId ||
                            settings.windowsOutputDevice == ep.guid)
                        ? Icon(Icons.check_circle, color: colorScheme.primary)
                        : const Icon(Icons.radio_button_unchecked),
                    onTap: () {
                      ref
                          .read(settingsProvider.notifier)
                          .setWindowsOutputDevice(ep.mpvDeviceId);
                      _loadCapabilities();
                    },
                  ),
              ],
            ),
          ),

          // SECTION B: Audio Engine
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'AUDIO ENGINE & EXCLUSIVE MODE',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'shared',
                            label: Text('Shared'),
                            icon: Icon(Icons.tune),
                          ),
                          ButtonSegment<String>(
                            value: 'exclusive_event',
                            label: Text('Exclusive (Event)'),
                            icon: Icon(Icons.bolt),
                          ),
                          ButtonSegment<String>(
                            value: 'exclusive_push',
                            label: Text('Exclusive (Push)'),
                            icon: Icon(Icons.waves),
                          ),
                        ],
                        selected: {
                          switch (settings.windowsOutputMode) {
                            'exclusive_push' => 'exclusive_push',
                            'exclusive' || 'exclusive_event' => 'exclusive_event',
                            _ => 'shared',
                          }
                        },
                        onSelectionChanged: (selected) {
                          ref
                              .read(settingsProvider.notifier)
                              .setWindowsOutputMode(selected.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        switch (settings.windowsOutputMode) {
                          'exclusive_push' =>
                            'Exclusive Push: Direct hardware access with buffered streaming. Maximizes DAC compatibility and prevents audio dropouts on sensitive USB endpoints.',
                          'exclusive' || 'exclusive_event' =>
                            'Exclusive Event: Event-driven hardware rendering with ultra-low latency. Directly feeds DAC endpoint buffers for raw, bit-perfect playback.',
                          _ =>
                            'Shared Mode: Routes through the Windows Audio Engine (WASAPI Shared), mixing audio with other applications and notification sounds.',
                        },
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsItem(
                  icon: Icons.safety_check_outlined,
                  title: 'Automatic Fallback to Shared Mode',
                  subtitle:
                      'Fall back gracefully if exclusive mode fails or device is in use by another app',
                  trailing: Switch(
                    value: settings.windowsExclusiveFallback,
                    onChanged: (val) {
                      ref
                          .read(settingsProvider.notifier)
                          .setWindowsExclusiveFallback(val);
                    },
                  ),
                  showDivider: false,
                ),
              ],
            ),
          ),

          // SECTION C: Output Format & Hardware Capabilities
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'OUTPUT FORMAT & HARDWARE CAPABILITIES',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                // Sample Rate Selector
                SettingsItem(
                  icon: Icons.speed,
                  title: 'Output Sample Rate',
                  subtitle: settings.windowsOutputSampleRate == 0
                      ? 'Auto (Bit-perfect source rate match)'
                      : '${settings.windowsOutputSampleRate} Hz',
                  trailing: DropdownButton<int>(
                    value: settings.windowsOutputSampleRate,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Auto (Source Match)')),
                      DropdownMenuItem(value: 44100, child: Text('44.1 kHz (CD)')),
                      DropdownMenuItem(value: 48000, child: Text('48.0 kHz (Standard)')),
                      DropdownMenuItem(value: 88200, child: Text('88.2 kHz')),
                      DropdownMenuItem(value: 96000, child: Text('96.0 kHz (Hi-Res)')),
                      DropdownMenuItem(value: 176400, child: Text('176.4 kHz')),
                      DropdownMenuItem(value: 192000, child: Text('192.0 kHz (Hi-Res Studio)')),
                      DropdownMenuItem(value: 352800, child: Text('352.8 kHz (DXD)')),
                      DropdownMenuItem(value: 384000, child: Text('384.0 kHz')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .setWindowsOutputSampleRate(val);
                      }
                    },
                  ),
                ),

                // Sample Format Selector
                SettingsItem(
                  icon: Icons.memory,
                  title: 'Output Sample Format',
                  subtitle: switch (settings.windowsOutputSampleFormat) {
                    's16' => '16-bit Integer PCM',
                    's24' => '24-bit Integer PCM',
                    's32' => '32-bit Integer PCM',
                    'float' => '32-bit Floating Point',
                    _ => 'Auto (Source Match / Hardware Direct)',
                  },
                  trailing: DropdownButton<String>(
                    value: settings.windowsOutputSampleFormat,
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Auto (Source Match)')),
                      DropdownMenuItem(value: 's16', child: Text('16-bit PCM (s16)')),
                      DropdownMenuItem(value: 's24', child: Text('24-bit PCM (s24)')),
                      DropdownMenuItem(value: 's32', child: Text('32-bit PCM (s32)')),
                      DropdownMenuItem(value: 'float', child: Text('32-bit Float (float)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .setWindowsOutputSampleFormat(val);
                      }
                    },
                  ),
                ),

                // Channels Selector
                SettingsItem(
                  icon: Icons.surround_sound,
                  title: 'Channel Layout',
                  subtitle: settings.windowsOutputChannels == 'auto'
                      ? 'Auto (Match Source)'
                      : 'Stereo (2 Channels)',
                  trailing: DropdownButton<String>(
                    value: settings.windowsOutputChannels,
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Auto')),
                      DropdownMenuItem(value: 'stereo', child: Text('Stereo (2 Ch)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .setWindowsOutputChannels(val);
                      }
                    },
                  ),
                ),

                // Hardware Probe Capabilities Display
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildHardwareCapabilitiesMatrix(context),
                ),
              ],
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildLiveMonitorCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ValueListenableBuilder<WindowsAudioStatus>(
      valueListenable: windowsAudioStatus,
      builder: (context, status, _) {
        final isBitPerfect = status.isBitPerfect;
        final isExclusive = status.mode.startsWith('exclusive');

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isBitPerfect
                  ? Colors.green.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant,
              width: isBitPerfect ? 1.5 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isExclusive ? Icons.lock : Icons.tune,
                          color: isBitPerfect
                              ? Colors.green
                              : (isExclusive ? colorScheme.primary : Colors.amber),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'LIVE AUDIO STREAM MONITOR',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isBitPerfect
                            ? Colors.green.withValues(alpha: 0.2)
                            : (isExclusive
                                ? colorScheme.primaryContainer
                                : Colors.amber.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isBitPerfect ? Icons.verified : Icons.info_outline,
                            size: 14,
                            color: isBitPerfect
                                ? Colors.green
                                : (isExclusive
                                    ? colorScheme.onPrimaryContainer
                                    : Colors.amber[800]),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isBitPerfect
                                ? 'BIT-PERFECT'
                                : (isExclusive
                                    ? (status.mode == 'exclusive_push'
                                        ? 'EXCLUSIVE (PUSH)'
                                        : 'EXCLUSIVE (EVENT)')
                                    : 'SHARED MIXER'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isBitPerfect
                                  ? Colors.green
                                  : (isExclusive
                                      ? colorScheme.onPrimaryContainer
                                      : Colors.amber[800]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),

                // Physical Output Details
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DAC Hardware Output:',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text(
                            status.sampleRate != null
                                ? '${status.sampleRate} Hz · ${status.bitDepth ?? 32}-bit (${status.format ?? "PCM"})'
                                : 'Awaiting playback...',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Source Track Format:',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text(
                            status.sourceSampleRate != null
                                ? '${status.sourceSampleRate} Hz · ${status.sourceBitDepth ?? 16}-bit'
                                : '—',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Active Device & Driver
                Text(
                  'Endpoint: ${status.device ?? "Default"} (${status.driver.toUpperCase()}) • State: ${status.reason.toUpperCase()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),

                // Honest Bit-Perfect Facts
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isBitPerfect ? Icons.check_circle_outline : Icons.info_outline,
                        size: 16,
                        color: isBitPerfect ? Colors.green : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status.bitPerfectReason ??
                              (status.sampleRate == null
                                  ? 'Start playing a track to inspect real hardware audio stream parameters.'
                                  : 'Processed stream active.'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isBitPerfect
                                ? Colors.green[700]
                                : colorScheme.onSurfaceVariant,
                            fontWeight: isBitPerfect ? FontWeight.w600 : FontWeight.normal,
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

  Widget _buildHardwareCapabilitiesMatrix(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loadingCapabilities) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final caps = _deviceCapabilities;
    final mix = _deviceMixFormat;

    if (caps == null) {
      return Text(
        'Select an endpoint to probe hardware capabilities via Windows Core Audio (IAudioClient).',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.developer_board, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'PROBED HARDWARE CAPABILITIES (IAudioClient)',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Default Shared Mix Format
        if (mix != null) ...[
          Text(
            'Default Windows Mix Format: ${mix.sampleRate} Hz, ${mix.validBits}-bit ${mix.isFloat ? "Float" : "Integer PCM"}, ${mix.channels == 2 ? "Stereo" : "${mix.channels} Channels"}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Exclusive Rates Chip Row
        Text(
          'Supported Exclusive Rates (${caps.exclusiveRates.length} detected):',
          style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final rate in caps.exclusiveRates)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text('${(rate / 1000).toStringAsFixed(1)} kHz'),
                backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Exclusive Formats Chip Row
        Text(
          'Supported Formats:',
          style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final fmt in caps.exclusiveFormats)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(switch (fmt) {
                  's16' => '16-bit PCM',
                  's24' => '24-bit PCM',
                  's32' => '32-bit PCM',
                  'float' => '32-bit Float',
                  _ => fmt,
                }),
                backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.5),
              ),
          ],
        ),
      ],
    );
  }
}
