import 'package:flutter_test/flutter_test.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/services/windows_audio_device_service.dart';

void main() {
  group('WindowsAudioEndpoint', () {
    test('parses full IMMDevice endpoint map correctly', () {
      final map = {
        'id': r'{0.0.0.00000000}.{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        'guid': '{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        'mpvDeviceId': 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        'name': 'IEMs (KT02H20 HIFI Audio)',
        'isDefault': true,
        'state': 1,
      };

      final endpoint = WindowsAudioEndpoint.fromMap(map);
      expect(endpoint.id, r'{0.0.0.00000000}.{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(endpoint.guid, '{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(endpoint.mpvDeviceId, 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(endpoint.name, 'IEMs (KT02H20 HIFI Audio)');
      expect(endpoint.isDefault, isTrue);
      expect(endpoint.state, 1);
    });

    test('handles missing or malformed map fields safely', () {
      final endpoint = WindowsAudioEndpoint.fromMap({});
      expect(endpoint.id, '');
      expect(endpoint.guid, '');
      expect(endpoint.mpvDeviceId, 'auto');
      expect(endpoint.name, 'Default Audio Device');
      expect(endpoint.isDefault, isFalse);
      expect(endpoint.state, 1);
    });
  });

  group('WindowsDeviceCapabilities', () {
    test('parses hardware capability probe data correctly', () {
      final map = {
        'deviceId': 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        'sharedSupported': true,
        'exclusiveSupported': true,
        'sampleRates': [44100, 48000, 96000, 192000, 384000],
        'sampleFormats': ['s16', 's24', 's32', 'float'],
        'sharedRates': [48000],
        'exclusiveRates': [44100, 48000, 96000, 192000, 384000],
        'exclusiveFormats': ['s16', 's24', 's32', 'float'],
        'formatsByRate': {
          '96000_exclusive': ['s16', 's24', 's32', 'float'],
        },
      };

      final caps = WindowsDeviceCapabilities.fromMap(map);
      expect(caps.deviceId, 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(caps.sharedSupported, isTrue);
      expect(caps.exclusiveSupported, isTrue);
      expect(caps.exclusiveRates, contains(96000));
      expect(caps.exclusiveFormats, contains('s32'));
      expect(caps.formatsByRate['96000_exclusive'], contains('float'));
    });
  });

  group('WindowsMixFormat', () {
    test('parses mix format map correctly', () {
      final map = {
        'sampleRate': 384000,
        'channels': 2,
        'bitsPerSample': 32,
        'validBits': 32,
        'isFloat': true,
        'formatTag': 0xFFFE,
      };

      final mix = WindowsMixFormat.fromMap(map);
      expect(mix.sampleRate, 384000);
      expect(mix.channels, 2);
      expect(mix.validBits, 32);
      expect(mix.isFloat, isTrue);
    });
  });

  group('WindowsAudioStatus Bit-Perfect reporting', () {
    test('reports bit-perfect correctly with full facts', () {
      const status = WindowsAudioStatus(
        mode: 'exclusive',
        device: 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        sampleRate: 96000,
        bitDepth: 32,
        format: 's32',
        sourceSampleRate: 96000,
        sourceBitDepth: 24,
        isBitPerfect: true,
        bitPerfectReason: 'Bit-perfect direct output: WASAPI Exclusive active',
      );

      expect(status.isBitPerfect, isTrue);
      expect(status.mode, 'exclusive');
      expect(status.sampleRate, 96000);
      expect(status.bitPerfectReason, contains('Bit-perfect'));
    });

    test('reports processed stream when shared mode is active', () {
      const status = WindowsAudioStatus(
        mode: 'shared',
        device: 'auto',
        sampleRate: 48000,
        bitDepth: 32,
        sourceSampleRate: 96000,
        isBitPerfect: false,
        bitPerfectReason: 'WASAPI Shared mixer active • Sample rate conversion: 96000Hz -> 48000Hz',
      );

      expect(status.isBitPerfect, isFalse);
      expect(status.bitPerfectReason, contains('WASAPI Shared mixer active'));
      expect(status.bitPerfectReason, contains('Sample rate conversion'));
    });
  });
}

