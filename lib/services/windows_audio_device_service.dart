import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibespace/utils/logger.dart';

final _log = AppLogger('WindowsAudioDeviceService');

/// Represents an active Windows audio output endpoint enumerated via Core Audio.
class WindowsAudioEndpoint {
  const WindowsAudioEndpoint({
    required this.id,
    required this.guid,
    required this.mpvDeviceId,
    required this.name,
    required this.isDefault,
    required this.state,
  });

  factory WindowsAudioEndpoint.fromMap(Map<dynamic, dynamic> map) {
    return WindowsAudioEndpoint(
      id: map['id'] as String? ?? '',
      guid: map['guid'] as String? ?? '',
      mpvDeviceId: map['mpvDeviceId'] as String? ?? 'auto',
      name: map['name'] as String? ?? 'Default Audio Device',
      isDefault: map['isDefault'] as bool? ?? false,
      state: (map['state'] as num?)?.toInt() ?? 1,
    );
  }

  /// The full Windows IMMDevice endpoint ID string.
  final String id;

  /// The extracted device GUID with braces, e.g. `{1e463064-4a08-414f-bd1b-6da70bd88c8a}`.
  final String guid;

  /// The formatted identifier passed to libmpv's audio-device option, e.g. `wasapi/{...}`.
  final String mpvDeviceId;

  /// The friendly Windows display name.
  final String name;

  /// Whether this endpoint is the current system default console audio device.
  final bool isDefault;

  /// Windows DEVICE_STATE (1 = ACTIVE).
  final int state;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowsAudioEndpoint &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'WindowsAudioEndpoint(name: $name, guid: $guid, default: $isDefault)';
}

/// Hardware capabilities queried via IAudioClient::IsFormatSupported.
class WindowsDeviceCapabilities {
  const WindowsDeviceCapabilities({
    required this.deviceId,
    required this.sharedSupported,
    required this.exclusiveSupported,
    required this.sampleRates,
    required this.sampleFormats,
    required this.sharedRates,
    required this.exclusiveRates,
    required this.exclusiveFormats,
    required this.formatsByRate,
  });

  factory WindowsDeviceCapabilities.fromMap(Map<dynamic, dynamic> map) {
    final exclusiveRates = _toIntList(
      map['exclusiveRates'] ?? map['exclusiveSupportedRates'],
    );
    final sharedRates = _toIntList(
      map['sharedRates'] ?? map['sharedSupportedRates'],
    );
    final exclusiveFormats = _toStringList(
      map['exclusiveFormats'] ?? map['exclusiveSupportedFormats'],
    );
    final sampleRates = _toIntList(map['sampleRates']);
    final sampleFormats = _toStringList(map['sampleFormats']);
    final formatsByRate = _toMapOfLists(
      map['formatsByRate'] ?? map['formats_by_rate'],
    );

    final effectiveRates = sampleRates.isNotEmpty
        ? sampleRates
        : ({...sharedRates, ...exclusiveRates}.toList()..sort());
    final effectiveFormats = sampleFormats.isNotEmpty
        ? sampleFormats
        : (exclusiveFormats.isNotEmpty
            ? exclusiveFormats
            : const ['s16', 's24', 's32', 'float']);

    final bool isSharedSupported = map['sharedSupported'] as bool? ??
        map['supportsShared'] as bool? ??
        (sharedRates.isNotEmpty || map['sharedMixFormat'] != null);
    final bool isExclusiveSupported = map['exclusiveSupported'] as bool? ??
        map['supportsExclusive'] as bool? ??
        exclusiveRates.isNotEmpty;

    return WindowsDeviceCapabilities(
      deviceId: map['deviceId'] as String? ?? '',
      sharedSupported: isSharedSupported,
      exclusiveSupported: isExclusiveSupported,
      sampleRates: effectiveRates,
      sampleFormats: effectiveFormats,
      sharedRates: sharedRates,
      exclusiveRates: exclusiveRates,
      exclusiveFormats: exclusiveFormats,
      formatsByRate: formatsByRate,
    );
  }

  final String deviceId;
  final bool sharedSupported;
  final bool exclusiveSupported;
  final List<int> sampleRates;
  final List<String> sampleFormats;
  final List<int> sharedRates;
  final List<int> exclusiveRates;
  final List<String> exclusiveFormats;
  final Map<String, List<String>> formatsByRate;

  static List<int> _toIntList(dynamic val) {
    if (val is! List) return const [];
    return val.whereType<num>().map((e) => e.toInt()).toList();
  }

  static List<String> _toStringList(dynamic val) {
    if (val is! List) return const [];
    return val.map((e) => e.toString()).toList();
  }

  static Map<String, List<String>> _toMapOfLists(dynamic val) {
    if (val is! Map) return const {};
    final result = <String, List<String>>{};
    val.forEach((k, v) {
      if (k != null && v is List) {
        result[k.toString()] = v.map((e) => e.toString()).toList();
      }
    });
    return result;
  }
}

/// Windows Core Audio mix format reported via IAudioClient::GetMixFormat.
class WindowsMixFormat {
  const WindowsMixFormat({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.validBits,
    required this.isFloat,
    required this.formatTag,
  });

  factory WindowsMixFormat.fromMap(Map<dynamic, dynamic> map) {
    return WindowsMixFormat(
      sampleRate: (map['sampleRate'] as num?)?.toInt() ?? 48000,
      channels: (map['channels'] as num?)?.toInt() ?? 2,
      bitsPerSample: (map['bitsPerSample'] as num?)?.toInt() ?? 32,
      validBits: (map['validBits'] as num?)?.toInt() ?? 32,
      isFloat: map['isFloat'] as bool? ?? true,
      formatTag: (map['formatTag'] as num?)?.toInt() ?? 0xFFFE,
    );
  }

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int validBits;
  final bool isFloat;
  final int formatTag;
}

/// Service providing Windows Core Audio endpoint discovery and hardware format capabilities.
class WindowsAudioDeviceService extends ChangeNotifier {
  WindowsAudioDeviceService._() {
    if (Platform.isWindows) {
      _initEventChannel();
      refreshEndpoints();
    }
  }

  static final WindowsAudioDeviceService instance =
      WindowsAudioDeviceService._();

  static const MethodChannel _methodChannel =
      MethodChannel('com.zarz.mornye/windows_audio');
  static const EventChannel _eventChannel =
      EventChannel('com.zarz.mornye/windows_audio_events');

  StreamSubscription<dynamic>? _eventSubscription;
  List<WindowsAudioEndpoint> _endpoints = const [];
  final Map<String, WindowsDeviceCapabilities> _capabilitiesCache = {};
  final Map<String, WindowsMixFormat> _mixFormatCache = {};
  bool _isLoading = false;

  List<WindowsAudioEndpoint> get endpoints => _endpoints;
  bool get isLoading => _isLoading;

  void _initEventChannel() {
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          _log.d('Received native audio event: $event');
          refreshEndpoints();
        },
        onError: (dynamic error) {
          _log.w('Audio event channel error: $error');
        },
      );
    } catch (e) {
      _log.w('Could not initialize audio event stream: $e');
    }
  }

  /// Enumerate active Windows audio endpoints via Core Audio.
  Future<List<WindowsAudioEndpoint>> refreshEndpoints() async {
    if (!Platform.isWindows) return const [];
    _isLoading = true;
    notifyListeners();

    try {
      final result =
          await _methodChannel.invokeListMethod<dynamic>('getAudioEndpoints');
      if (result != null) {
        _endpoints = result
            .whereType<Map<dynamic, dynamic>>()
            .map(WindowsAudioEndpoint.fromMap)
            .toList();
      }
    } catch (e) {
      _log.w('Failed to enumerate audio endpoints: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return _endpoints;
  }

  /// Query real hardware capabilities for an endpoint.
  Future<WindowsDeviceCapabilities?> getDeviceCapabilities(
      String deviceId) async {
    if (!Platform.isWindows) return null;
    if (_capabilitiesCache.containsKey(deviceId)) {
      return _capabilitiesCache[deviceId];
    }

    try {
      final result = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
        'getDeviceCapabilities',
        {'deviceId': deviceId},
      );
      if (result != null) {
        final caps = WindowsDeviceCapabilities.fromMap(result);
        _capabilitiesCache[deviceId] = caps;
        return caps;
      }
    } catch (e) {
      _log.w('Failed to query device capabilities for $deviceId: $e');
    }
    return null;
  }

  /// Query default Windows shared mix format for an endpoint.
  Future<WindowsMixFormat?> getDeviceMixFormat(String deviceId) async {
    if (!Platform.isWindows) return null;
    if (_mixFormatCache.containsKey(deviceId)) {
      return _mixFormatCache[deviceId];
    }

    try {
      final result = await _methodChannel.invokeMapMethod<dynamic, dynamic>(
        'getDeviceMixFormat',
        deviceId,
      );
      if (result != null) {
        final mix = WindowsMixFormat.fromMap(result);
        _mixFormatCache[deviceId] = mix;
        return mix;
      }
    } catch (e) {
      _log.w('Failed to query device mix format for $deviceId: $e');
    }
    return null;
  }

  /// Invalidate cached capabilities, allowing fresh hardware queries.
  void invalidateCapabilities([String? deviceId]) {
    if (deviceId != null) {
      _capabilitiesCache.remove(deviceId);
      _mixFormatCache.remove(deviceId);
    } else {
      _capabilitiesCache.clear();
      _mixFormatCache.clear();
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

