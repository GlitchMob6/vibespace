import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:vibespace/models/equalizer_settings.dart';
import 'package:vibespace/services/media_kit_audio_filters.dart';
import 'package:vibespace/services/music_playback_deck.dart'
    show UsbDsdUnavailable, windowsAudioStatus, WindowsAudioStatus;
import 'package:vibespace/services/playback_deck.dart';
import 'package:vibespace/services/playback_equalizer.dart';
import 'package:vibespace/utils/logger.dart';

final _log = AppLogger('MediaKitDeck');

/// An error-level line from libmpv's log.
typedef MpvLogError = ({String prefix, String text});

/// The libmpv operations [MediaKitPlaybackDeck] uses. [MediaKitEngine] is the
/// media_kit implementation; host tests substitute a fake.
abstract interface class MpvEngine {
  Stream<bool> get completed;
  Stream<Duration> get duration;
  Stream<int> get sampleRate;
  Stream<MpvLogError> get errors;
  Duration get position;

  /// Loads [source] paused.
  Future<void> open(String source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();

  /// mpv's `volume` property, 0 to 100 on a cubic curve.
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);

  /// Returns the mpv error code: negative on failure.
  Future<int> setProperty(String name, String value);
  Future<String> getProperty(String name);
  Future<void> dispose();
}

/// One libmpv instance through media_kit.
class MediaKitEngine implements MpvEngine {
  MediaKitEngine()
    : _player = NativePlayer(
        configuration: const PlayerConfiguration(title: 'VibeSpace'),
      ) {
    _configured = Future.wait([
      // Names the audio client stream across platform mixers
      setProperty('audio-client-name', 'VibeSpace'),
      // media_kit caches streams on disk, which fails where the cache folder
      // is not writable and reports a load error. Memory is enough for audio.
      setProperty('cache-on-disk', 'no'),
      // Room for an equalizer preamp of +12 dB applied through the volume
      // when the libmpv build has no volume filter.
      setProperty('volume-max', '200'),
      // Sidecar .lrc files are handled by the Flutter UI, not mpv subtitle decoder.
      setProperty('sub-auto', 'no'),
      // Prefer high-precision 32-bit float internal audio processing (AIMP-equivalent)
      setProperty('audio-format', 'float'),
      // Keep hardware audio stream open across track boundaries for gapless transitions
      setProperty('gapless-audio', 'yes'),
      // Bypass pitch filter at 1.0x for bit-perfect output
      setProperty('audio-pitch-correction', 'no'),
    ]);
  }

  final NativePlayer _player;
  late final Future<void> _configured;

  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<int> get sampleRate => _player.stream.audioParams
      .map((params) => params.sampleRate)
      .where((rate) => rate != null && rate > 0)
      .cast<int>();
  @override
  Stream<MpvLogError> get errors => _player.stream.log
      .where((log) => log.level == 'error')
      .map((log) => (prefix: log.prefix, text: log.text));
  @override
  Duration get position => _player.state.position;

  @override
  Future<void> open(String source) async {
    await _configured;
    await _player.open(Media(source), play: false);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed);

  @override
  Future<int> setProperty(String name, String value) async {
    await _player.waitForPlayerInitialization;
    if (_player.disposed) return -1;
    final nativeName = name.toNativeUtf8();
    final nativeValue = value.toNativeUtf8();
    try {
      return _player.mpv.mpv_set_property_string(
        _player.ctx,
        nativeName.cast(),
        nativeValue.cast(),
      );
    } finally {
      calloc.free(nativeName);
      calloc.free(nativeValue);
    }
  }

  @override
  Future<String> getProperty(String name) => _player.getProperty(name);

  @override
  Future<void> dispose() => _player.dispose();
}

/// A source libmpv could not open.
class MediaKitSourceException implements Exception {
  const MediaKitSourceException(this.message);
  final String message;

  @override
  String toString() => 'MediaKitSourceException: $message';
}

/// The Windows and Linux deck: one libmpv player through media_kit, with the
/// equalizer as an mpv audio filter chain.
///
/// Gapless playback across tracks needs mpv's own playlist
/// (`gapless-audio`), but the runtime gives each deck one source at a time
/// and prepares the next song on a separate deck for AutoMix. Tracks are
/// therefore joined like on the audioplayers deck.
class MediaKitPlaybackDeck implements PlaybackDeck {
  MediaKitPlaybackDeck({
    required this.playerId,
    MpvEngine? engine,
    this.exclusiveOutput = false,
    this.wasapiDeviceId,
  }) : _engine = engine ?? debugEngineFactory?.call() ?? MediaKitEngine() {
    playbackEqualizer.addListener(_equalizerChanged);
    playbackOutputVolume.addListener(_outputVolumeChanged);
    _subscriptions.addAll([
      _engine.completed.listen((done) {
        if (!done || _disposed || _state != PlaybackDeckState.playing) return;
        _setState(PlaybackDeckState.completed);
        _completions.add(null);
      }),
      _engine.duration.listen((value) {
        if (_disposed || value <= Duration.zero) return;
        _duration = value;
        _durations.add(value);
        _finishLoad(null);
      }),
      _engine.sampleRate.listen((rate) {
        if (_disposed || rate == _sampleRate) return;
        _sampleRate = rate;
        // Band frequencies are limited to 45% of the rate.
        _equalizerChanged();
      }),
      _engine.errors.listen(_onError),
    ]);
    _equalizerChanged();
  }

  /// Exclusive output (WASAPI exclusive, CoreAudio hog mode). A later output
  /// setting enables it; until then every deck shares the system mixer.
  final bool exclusiveOutput;

  /// Specific WASAPI device ID to use for output. If null, uses system default.
  final String? wasapiDeviceId;

  final String playerId;
  final MpvEngine _engine;

  /// Getter to expose the current exclusiveOutput value for status reporting.
  bool get isExclusive => exclusiveOutput;

  static bool? _available;

  /// Overrides [isAvailable] in tests.
  @visibleForTesting
  static bool? debugAvailableOverride;

  /// Supplies the engine of decks created without one, in tests.
  @visibleForTesting
  static MpvEngine Function()? debugEngineFactory;

  /// True once libmpv is loaded. A missing library (for example no libmpv
  /// package on Linux) leaves the app on the audioplayers deck.
  static bool get isAvailable {
    final override = debugAvailableOverride;
    if (override != null) return override;
    return _available ??= () {
      try {
        MediaKit.ensureInitialized();
        return true;
      } catch (error) {
        _log.e('libmpv is unavailable, playing through audioplayers: $error');
        return false;
      }
    }();
  }

  static final _unbracedWasapiGuidRegex = RegExp(
    r'^wasapi/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$',
  );

  /// Normalizes a WASAPI device ID, restoring braces if they were stripped previously.
  /// E.g. "wasapi/1e463064-4a08-414f-bd1b-6da70bd88c8a" -> "wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}"
  static String normalizeWasapiDeviceId(String deviceId) {
    final trimmed = deviceId.trim();
    final match = _unbracedWasapiGuidRegex.firstMatch(trimmed);
    if (match != null) {
      return 'wasapi/{${match.group(1)}}';
    }
    return trimmed;
  }

  /// Parses mpv's audio-device-list output safely using jsonDecode.
  /// mpv returns a JSON array: [{"name": "wasapi/{...}", "description": "..."}, ...]
  static List<Map<String, dynamic>> parseAudioDeviceList(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '[]') return [];

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        final result = <Map<String, dynamic>>[];
        for (final item in decoded) {
          if (item is Map) {
            final name = item['name']?.toString() ?? '';
            final description = item['description']?.toString() ?? name;
            if (name.isNotEmpty) {
              result.add({'name': name, 'description': description});
            }
          }
        }
        return result;
      }
    } catch (_) {
      // Fallback below if not valid JSON
    }

    // Fallback for non-JSON comma-separated device names
    return trimmed
        .split(',')
        .map((name) => {'name': name.trim(), 'description': name.trim()})
        .where((d) => (d['name'] as String).isNotEmpty)
        .toList();
  }

  /// Queries available WASAPI audio devices and their capabilities.
  /// Returns a list of device info maps, or empty list on non-Windows platforms.
  static Future<List<Map<String, dynamic>>> queryWASAPIDevices() async {
    if (!Platform.isWindows) return [];

    // Create a temporary engine to query devices
    final tempEngine = MediaKitEngine();
    try {
      await tempEngine.setProperty('ao', 'wasapi');
      final deviceListStr = await tempEngine.getProperty('audio-device-list');
      _log.i('WASAPI device list: $deviceListStr');
      return parseAudioDeviceList(deviceListStr);
    } catch (e) {
      _log.w('Failed to query WASAPI devices: $e');
      return [];
    } finally {
      await tempEngine.dispose();
    }
  }

  static const _loadTimeout = Duration(seconds: 20);

  final _states = StreamController<PlaybackDeckState>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _completions = StreamController<void>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  PlaybackDeckState _state = PlaybackDeckState.stopped;
  AsyncError? _failure;
  Completer<String?>? _pendingLoad;
  Duration? _duration;
  Timer? _positionTimer;
  int _token = 0;
  bool _disposed = false;
  double _gain = 1;
  int? _sampleRate;

  String? _requestedDeviceId;
  String? _activeDeviceId;
  bool _isFallbackDevice = false;
  bool _hasRetriedDeviceFallback = false;

  @visibleForTesting
  String? get debugActiveDeviceId => _activeDeviceId;

  @visibleForTesting
  bool get debugIsFallbackDevice => _isFallbackDevice;

  /// The `af` value libmpv accepted last, null when unknown.
  String? _appliedSpec;
  double _chainGainDb = 0;

  /// Optional filters this process's libmpv lacks, found by probing once.
  static final _missingFilters = <String>{};
  static Future<void>? _probe;

  @visibleForTesting
  static void debugResetMissingFilters() {
    _missingFilters.clear();
    _probe = null;
  }

  Timer? _equalizerTimer;
  Future<void> _equalizerWrite = Future.value();

  /// Reads an mpv property of this deck's player, for integration tests.
  @visibleForTesting
  Future<String> debugProperty(String name) => _engine.getProperty(name);

  @override
  PlaybackDeckState get state => _state;
  @override
  bool get isDirect => false;
  @override
  bool get needsSourceReload => false;
  @override
  Stream<PlaybackDeckState> get onPlayerStateChanged => _states.stream;
  @override
  Stream<Duration> get onDurationChanged => _durations.stream;
  @override
  Stream<Duration> get onPositionChanged => _positions.stream;
  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  void _setState(PlaybackDeckState value) {
    _state = value;
    if (!_disposed) _states.add(value);
  }

  // "Option af: lavfi-x doesn't exist." and "Error parsing option af".
  static bool _isRejectedFilterValue(MpvLogError error) =>
      error.text.toLowerCase().contains('option af');

  static bool _isFilterError(MpvLogError error) =>
      _isRejectedFilterValue(error) ||
      error.prefix.contains('lavfi') ||
      error.prefix.startsWith('af') ||
      error.prefix.contains('Parsed_') ||
      error.text.toLowerCase().contains('filter');

  // Errors that stop the current source. Decoder errors are often a single
  // damaged frame and playback continues.
  static bool _isSourceError(MpvLogError error) {
    // External .lrc or subtitle parsing failures must never abort audio playback
    final lower = error.text.toLowerCase();
    if (lower.contains('.lrc') ||
        lower.contains('subtitle') ||
        lower.contains('sub-file')) {
      return false;
    }
    return const {'file', 'stream', 'ao', 'cplayer'}.contains(error.prefix) ||
        error.prefix.startsWith('ao') ||
        error.prefix.startsWith('demux') ||
        error.prefix.startsWith('stream');
  }

  void _onError(MpvLogError error) {
    if (_disposed) return;
    if (_isFilterError(error)) {
      // A rejected `af` value is handled through the property's result,
      // including the filter probes of _probeFilters.
      if (_isRejectedFilterValue(error)) return;
      _log.w('mpv ${error.prefix}: ${error.text}');
      // mpv disabled the filter; the next change sets the chain again.
      _appliedSpec = null;
      if (playbackEqualizer.value.enabled) {
        reportEqualizerError(
          playerId,
          'Equalizer is unavailable on this output: ${error.text}',
        );
      }
      return;
    }
    // FFmpeg can reject an ID3 text field while the audio still opens.
    // Apply the same source-error policy during preparation and playback.
    if (!_isSourceError(error)) {
      _log.w('mpv ${error.prefix}: ${error.text}');
      return;
    }
    if (_pendingLoad != null) {
      _finishLoad('${error.prefix}: ${error.text}');
      return;
    }
    if (_state == PlaybackDeckState.stopped) {
      _log.w('mpv ${error.prefix}: ${error.text}');
      return;
    }
    final failure = MediaKitSourceException(error.text);
    _failure = AsyncError(failure, StackTrace.current);
    _states.addError(failure, _failure!.stackTrace);
  }

  void _finishLoad(String? error) {
    final pending = _pendingLoad;
    if (pending != null && !pending.isCompleted) pending.complete(error);
  }

  @override
  void startPositionUpdates(Duration interval) {
    _positionTimer?.cancel();
    // A timer rather than frames: AutoMix runs with the display asleep.
    _positionTimer = Timer.periodic(interval, (_) {
      if (!_disposed && _state == PlaybackDeckState.playing) {
        _positions.add(_engine.position);
      }
    });
  }

  @override
  Future<void> configureOutput() async {
    _hasRetriedDeviceFallback = false;
    _requestedDeviceId = (wasapiDeviceId != null && wasapiDeviceId!.isNotEmpty)
        ? normalizeWasapiDeviceId(wasapiDeviceId!)
        : null;
    _activeDeviceId = null;
    _isFallbackDevice = false;

    if (_requestedDeviceId != null) {
      _log.i('Configuring output for requested WASAPI device: $_requestedDeviceId');
      bool isAvailable = false;
      try {
        final deviceListStr = await _engine.getProperty('audio-device-list');
        final devices = parseAudioDeviceList(deviceListStr);
        if (devices.isNotEmpty) {
          isAvailable = devices.any(
            (d) =>
                (d['name'] as String).toLowerCase() ==
                _requestedDeviceId!.toLowerCase(),
          );
        } else {
          // If the list is empty (e.g. before initial probe), attempt setting requested device
          isAvailable = true;
        }
      } catch (e) {
        _log.w('Could not query audio-device-list: $e');
        isAvailable = true;
      }

      if (isAvailable) {
        final deviceResult = await _engine.setProperty('audio-device', _requestedDeviceId!);
        if (deviceResult >= 0) {
          _activeDeviceId = _requestedDeviceId;
          _isFallbackDevice = false;
        } else {
          _log.w('Setting audio-device=$_requestedDeviceId failed ($deviceResult), falling back to auto');
          await _engine.setProperty('audio-device', 'auto');
          _activeDeviceId = 'auto';
          _isFallbackDevice = true;
        }
      } else {
        _log.w('Requested WASAPI device "$_requestedDeviceId" is not currently present. Falling back to auto.');
        await _engine.setProperty('audio-device', 'auto');
        _activeDeviceId = 'auto';
        _isFallbackDevice = true;
      }
    } else {
      await _engine.setProperty('audio-device', 'auto');
      _activeDeviceId = 'auto';
      _isFallbackDevice = false;
    }

    final effectiveDevice = _isFallbackDevice
        ? 'auto (requested: $_requestedDeviceId)'
        : (_activeDeviceId ?? wasapiDeviceId);

    if (!exclusiveOutput) {
      _log.i('Using WASAPI shared mode (device: $effectiveDevice)');
      windowsAudioStatus.value = WindowsAudioStatus(
        reason: _isFallbackDevice ? 'fallback' : 'active',
        mode: 'shared',
        device: effectiveDevice,
      );
      return;
    }

    _log.i('Enabling WASAPI exclusive mode (device: $effectiveDevice)');
    windowsAudioStatus.value = WindowsAudioStatus(
      reason: _isFallbackDevice ? 'fallback' : 'pending',
      mode: 'exclusive',
      device: effectiveDevice,
    );

    // Try to enable exclusive mode
    final result = await _engine.setProperty('audio-exclusive', 'yes');
    if (result < 0) {
      _log.w('Failed to set audio-exclusive=yes (mpv error $result)');
      windowsAudioStatus.value = WindowsAudioStatus(
        reason: 'failed',
        mode: 'exclusive',
        device: effectiveDevice,
      );
      // Fallback to shared mode will be handled in _load
      return;
    }

    // Verify exclusive mode was actually achieved by checking the property
    try {
      final exclusiveStatus = await _engine.getProperty('audio-exclusive');
      _log.i('audio-exclusive property: $exclusiveStatus');
      if (exclusiveStatus != 'yes') {
        _log.w('Exclusive mode not active, got: $exclusiveStatus');
        windowsAudioStatus.value = WindowsAudioStatus(
          reason: 'fallback',
          mode: 'shared',
          device: effectiveDevice,
        );
        return;
      }
    } catch (e) {
      _log.w('Failed to verify exclusive mode: $e');
    }

    windowsAudioStatus.value = WindowsAudioStatus(
      reason: _isFallbackDevice ? 'fallback' : 'active',
      mode: 'exclusive',
      device: effectiveDevice,
    );
  }

  // mpv's volume is cubic: 100 * cbrt(linear gain). The equalizer gain may
  // add up to +12 dB, within the volume-max the engine sets.
  double get _mpvVolume {
    final linear =
        _gain.clamp(0.0, 1.0) *
        playbackOutputVolume.value *
        math.pow(10, _chainGainDb / 20);
    return 100 * math.pow(linear.clamp(0.0, 4.0), 1 / 3).toDouble();
  }

  @override
  Future<void> setVolume(double volume) async {
    _gain = volume;
    await _engine.setVolume(_mpvVolume);
  }

  void _outputVolumeChanged() {
    if (_disposed) return;
    unawaited(
      _engine
          .setVolume(_mpvVolume)
          .catchError((Object error) => _log.w('Output volume: $error')),
    );
  }

  @override
  Future<void> setPlaybackRate(double rate) => _engine.setSpeed(rate);

  @override
  Future<void> setNetworkSource(String url) => _load(url);

  @override
  Future<void> setFileSource(
    String path, {
    bool preferBitPerfect = false,
    bool directUsb = false,
    bool allowDop = false,
    bool requiresDsd = false,
    bool allowFixedVolume = false,
    bool dapExclusive = false,
  }) => _load(path, requiresDsd: requiresDsd);

  Future<void> _load(String source, {bool requiresDsd = false}) async {
    await stop();
    final token = ++_token;
    final loaded = Completer<String?>();
    _pendingLoad = loaded;
    _failure = null;
    _duration = null;
    String? error;
    try {
      await _engine.open(source);
      error = await loaded.future.timeout(
        _loadTimeout,
        onTimeout: () => 'Timed out opening the source',
      );
    } finally {
      if (identical(_pendingLoad, loaded)) _pendingLoad = null;
    }
    if (_disposed || token != _token) return;

    if (error != null) {
      final isAudioError = error.contains('ao') ||
          error.toLowerCase().contains('audio') ||
          error.toLowerCase().contains('wasapi');

      if (isAudioError && _activeDeviceId != 'auto' && !_hasRetriedDeviceFallback) {
        _hasRetriedDeviceFallback = true;
        _isFallbackDevice = true;
        _activeDeviceId = 'auto';
        _log.w(
          'Audio driver initialization failed on device "$_requestedDeviceId" ($error). '
          'Retrying once with audio-device=auto fallback...',
        );
        await _engine.stop();
        await _engine.setProperty('audio-device', 'auto');

        final retryLoaded = Completer<String?>();
        _pendingLoad = retryLoaded;
        try {
          await _engine.open(source);
          error = await retryLoaded.future.timeout(
            _loadTimeout,
            onTimeout: () => 'Timed out retrying with fallback audio device',
          );
        } finally {
          if (identical(_pendingLoad, retryLoaded)) _pendingLoad = null;
        }
        if (_disposed || token != _token) return;
      }
    }

    if (error != null) {
      await _engine.stop();
      // libmpv converts DSD to PCM when its FFmpeg build has the decoder.
      if (requiresDsd) throw UsbDsdUnavailable();
      final effectiveDevice = _isFallbackDevice
          ? 'auto (requested: $_requestedDeviceId)'
          : (_activeDeviceId ?? wasapiDeviceId);
      windowsAudioStatus.value = WindowsAudioStatus(
        reason: 'failed',
        mode: exclusiveOutput ? 'exclusive' : 'shared',
        device: effectiveDevice,
      );
      throw MediaKitSourceException(error);
    }
    // Source loaded successfully, check if exclusive mode is actually active
    if (exclusiveOutput) {
      await _verifyExclusiveMode();
    }
    // Query actual audio parameters
    await _updateAudioStatus();
  }

  /// Verifies if exclusive mode is actually active after source load.
  /// If exclusive mode failed, explicitly falls back to shared mode and reports it.
  Future<void> _verifyExclusiveMode() async {
    if (_disposed) return;
    try {
      final exclusiveStatus = await _engine.getProperty('audio-exclusive');
      _log.i('Exclusive mode verification: audio-exclusive=$exclusiveStatus');
      if (exclusiveStatus != 'yes') {
        _log.w('Exclusive mode was requested but not achieved; falling back to shared mode');
        final effectiveDevice = _isFallbackDevice
            ? 'auto (requested: $_requestedDeviceId)'
            : (_activeDeviceId ?? wasapiDeviceId);
        windowsAudioStatus.value = WindowsAudioStatus(
          reason: 'fallback',
          mode: 'shared',
          device: effectiveDevice,
        );
        // Don't throw - playback continues in shared mode, but status reflects actual mode
      }
    } catch (e) {
      _log.w('Failed to verify exclusive mode: $e');
    }
  }

  Future<void> _updateAudioStatus() async {
    if (_disposed) return;
    try {
      final sampleRateStr = await _engine.getProperty('audio-params/samplerate');
      final formatStr = await _engine.getProperty('audio-params/format');
      final sampleRate = int.tryParse(sampleRateStr);
      // Parse format string like "s16le", "f32le" to bit depth
      int? bitDepth;
      if (formatStr.contains('16')) {
        bitDepth = 16;
      } else if (formatStr.contains('24')) {
        bitDepth = 24;
      } else if (formatStr.contains('32')) {
        bitDepth = 32;
      } else if (formatStr.contains('64')) {
        bitDepth = 64;
      }

      // Determine actual mode: check if exclusive mode was requested but not achieved
      String actualMode;
      String reason;
      if (exclusiveOutput) {
        try {
          final exclusiveStatus = await _engine.getProperty('audio-exclusive');
          if (exclusiveStatus == 'yes') {
            actualMode = 'exclusive';
            reason = 'active';
          } else {
            actualMode = 'shared';
            reason = 'fallback';
          }
        } catch (_) {
          actualMode = 'shared';
          reason = 'fallback';
        }
      } else {
        actualMode = 'shared';
        reason = 'active';
      }

      final effectiveDevice = _isFallbackDevice
          ? 'auto (requested: $_requestedDeviceId)'
          : (_activeDeviceId ?? wasapiDeviceId);

      windowsAudioStatus.value = WindowsAudioStatus(
        reason: _isFallbackDevice ? 'fallback' : reason,
        mode: actualMode,
        device: effectiveDevice,
        sampleRate: sampleRate,
        bitDepth: bitDepth,
        transport: formatStr,
      );
    } catch (e) {
      _log.w('Failed to query audio parameters: $e');
      final effectiveDevice = _isFallbackDevice
          ? 'auto (requested: $_requestedDeviceId)'
          : (_activeDeviceId ?? wasapiDeviceId);
      windowsAudioStatus.value = WindowsAudioStatus(
        reason: _isFallbackDevice ? 'fallback' : 'active',
        mode: exclusiveOutput ? 'exclusive' : 'shared',
        device: effectiveDevice,
      );
    }
  }

  @override
  Future<void> cancelPreparation() async {
    if (_pendingLoad != null) await stop();
  }

  @override
  Future<void> resume() async {
    final failure = _failure;
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
    await _engine.play();
    _setState(PlaybackDeckState.playing);
  }

  @override
  Future<void> pause() async {
    await _engine.pause();
    _setState(PlaybackDeckState.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    await _engine.seek(position);
    if (!_disposed) _positions.add(position);
  }

  @override
  Future<void> stop() async {
    _token++;
    _finishLoad(null);
    await _engine.stop();
    _duration = null;
    _setState(PlaybackDeckState.stopped);
    windowsAudioStatus.value = const WindowsAudioStatus();
  }

  @override
  Future<Duration?> getCurrentPosition() async {
    // Asked directly: media_kit's cached position trails a pause or seek.
    final seconds = double.tryParse(await _engine.getProperty('time-pos'));
    if (seconds == null || !seconds.isFinite) return _engine.position;
    return Duration(microseconds: (seconds * 1000000).round());
  }

  @override
  Future<Duration?> getDuration() async => _duration;

  void _equalizerChanged() {
    // Every change sets the chain again, so slider drags coalesce.
    _equalizerTimer ??= Timer(const Duration(milliseconds: 80), () {
      _equalizerTimer = null;
      _equalizerWrite = _equalizerWrite.then((_) => _syncEqualizer());
    });
  }

  MpvAudioFilterChain _chainFor(EqualizerSettings settings) =>
      MpvAudioFilterChain.fromEqualizer(
        settings,
        sampleRate: _sampleRate,
        unavailable: _missingFilters,
      );

  /// Learns which optional filters libmpv lacks. mpv checks `lavfi-NAME`
  /// when the property is set, before any audio flows through it, so the
  /// first deck probes once while it has no source.
  Future<void> _probeFilters() => _probe ??= () async {
    for (final name in MpvAudioFilterChain.optionalFilters) {
      if (await _engine.setProperty('af', '@mornye_probe:lavfi-$name') < 0) {
        _missingFilters.add(name);
      }
    }
    await _engine.setProperty('af', '');
    if (_missingFilters.isNotEmpty) {
      _log.i('libmpv lacks the audio filters $_missingFilters');
    }
  }();

  // Features the listener turned on that this libmpv cannot apply.
  String? _missingFeatures(EqualizerSettings settings) {
    final missing = [
      if (settings.balance != 0 && _missingFilters.contains('stereotools'))
        'balance',
      if (settings.compressor && _missingFilters.contains('acompressor'))
        'compressor',
    ];
    if (missing.isEmpty) return null;
    return 'The ${missing.join(' and ')} is not available in this system '
        'audio library';
  }

  Future<void> _applyChainGain(MpvAudioFilterChain chain) async {
    if (chain.volumeGainDb == _chainGainDb) return;
    _chainGainDb = chain.volumeGainDb;
    await _engine.setVolume(_mpvVolume);
  }

  Future<void> _syncEqualizer() async {
    if (_disposed) return;
    final settings = playbackEqualizer.value;
    try {
      if (settings.enabled) await _probeFilters();
      if (_disposed) return;
      final chain = _chainFor(settings);
      // mpv keeps filters whose settings did not change and recreates the
      // graph, which also applies changes during playback.
      if (chain.spec != _appliedSpec) {
        final code = await _engine.setProperty('af', chain.spec);
        if (_disposed) return;
        if (code < 0) {
          _appliedSpec = null;
          reportEqualizerError(
            playerId,
            settings.enabled
                ? 'Equalizer is unavailable on this output (mpv error $code)'
                : null,
          );
          return;
        }
        _appliedSpec = chain.spec;
      }
      await _applyChainGain(chain);
      reportEqualizerError(playerId, _missingFeatures(settings));
    } catch (error) {
      _appliedSpec = null;
      if (!_disposed && settings.enabled) {
        reportEqualizerError(
          playerId,
          'Equalizer is unavailable on this output: $error',
        );
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    playbackEqualizer.removeListener(_equalizerChanged);
    playbackOutputVolume.removeListener(_outputVolumeChanged);
    _equalizerTimer?.cancel();
    _positionTimer?.cancel();
    reportEqualizerError(playerId, null);
    await stop();
    _setState(PlaybackDeckState.disposed);
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _equalizerWrite;
    await _engine.dispose();
    await _states.close();
    await _durations.close();
    await _positions.close();
    await _completions.close();
  }
}
