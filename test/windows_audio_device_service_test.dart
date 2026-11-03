import 'package:flutter_test/flutter_test.dart';
import 'package:vibespace/services/music_playback_deck.dart';
import 'package:vibespace/services/windows_audio_device_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(endpoint.endpointId, '');
      expect(endpoint.guid, '');
      expect(endpoint.mpvDeviceId, 'auto');
      expect(endpoint.name, 'Default Audio Device');
      expect(endpoint.isDefault, isFalse);
      expect(endpoint.state, 1);
    });

    test('recovers valid mpvDeviceId when native code omitted it', () {
      final legacyMap = {
        'id': 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        'endpointId': r'{0.0.0.00000000}.{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        'guid': '{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        'name': 'FiiO DAC',
        'isDefault': false,
        'state': 1,
      };

      final endpoint = WindowsAudioEndpoint.fromMap(legacyMap);
      expect(endpoint.endpointId, r'{0.0.0.00000000}.{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(endpoint.guid, '{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(endpoint.mpvDeviceId, 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}');
      expect(endpoint.mpvDeviceId, isNot('auto'));
    });

    test('recovers guid and mpvDeviceId from endpointId string alone', () {
      final minimalMap = {
        'endpointId': r'{0.0.0.00000000}.{a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d}',
        'name': 'Speakers',
      };

      final endpoint = WindowsAudioEndpoint.fromMap(minimalMap);
      expect(endpoint.guid, '{a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d}');
      expect(endpoint.mpvDeviceId, 'wasapi/{a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d}');
      expect(endpoint.endpointId, r'{0.0.0.00000000}.{a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d}');
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

    test('distinguishes active physical device and selected device', () {
      const status = WindowsAudioStatus(
        reason: 'active',
        mode: 'exclusive_event',
        selectedDevice: 'wasapi/{dac-guid}',
        activeDevice: 'wasapi/{dac-guid}',
      );

      expect(status.selectedDevice, 'wasapi/{dac-guid}');
      expect(status.activeDevice, 'wasapi/{dac-guid}');
      expect(status.device, 'wasapi/{dac-guid}');
    });

    test('reports fallback active device distinct from requested selection', () {
      const status = WindowsAudioStatus(
        reason: 'fallback',
        mode: 'shared',
        selectedDevice: 'wasapi/{missing-dac}',
        activeDevice: 'auto (fallback)',
      );

      expect(status.selectedDevice, 'wasapi/{missing-dac}');
      expect(status.activeDevice, 'auto (fallback)');
      expect(status.device, 'auto (fallback)');
    });

    test(
      'configured device does not automatically count as verified active device',
      () {
        const status = WindowsAudioStatus(
          reason: 'active',
          mode: 'exclusive_event',
          selectedDevice: 'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        );

        // Configured selected device is faithfully recorded
        expect(
          status.selectedDevice,
          'wasapi/{1e463064-4a08-414f-bd1b-6da70bd88c8a}',
        );
        // Active device remains null unless independently verified from Core Audio
        expect(status.activeDevice, isNull);
        // Legacy device property does not falsely echo selectedDevice
        expect(status.device, isNull);
      },
    );
  });

  group('WindowsAudioDeviceService endpoint matching', () {
    setUp(() {
      WindowsAudioDeviceService.instance =
          WindowsAudioDeviceService.createForTesting();

      final ep1 = WindowsAudioEndpoint.fromMap({
        'id': r'{0.0.0.00000000}.{11111111-1111-1111-1111-111111111111}',
        'endpointId': r'{0.0.0.00000000}.{11111111-1111-1111-1111-111111111111}',
        'guid': '{11111111-1111-1111-1111-111111111111}',
        'mpvDeviceId': 'wasapi/{11111111-1111-1111-1111-111111111111}',
        'name': 'Primary Speakers',
        'isDefault': true,
      });

      final ep2 = WindowsAudioEndpoint.fromMap({
        'id': r'{0.0.0.00000000}.{22222222-2222-2222-2222-222222222222}',
        'endpointId': r'{0.0.0.00000000}.{22222222-2222-2222-2222-222222222222}',
        'guid': '{22222222-2222-2222-2222-222222222222}',
        'mpvDeviceId': 'wasapi/{22222222-2222-2222-2222-222222222222}',
        'name': 'USB DAC',
        'isDefault': false,
      });

      WindowsAudioDeviceService.instance.debugSetEndpoints([ep1, ep2]);
    });

    test('findEndpoint resolves by mpvDeviceId', () {
      final found = WindowsAudioDeviceService.instance
          .findEndpoint('wasapi/{22222222-2222-2222-2222-222222222222}');
      expect(found, isNotNull);
      expect(found!.name, 'USB DAC');
    });

    test('findEndpoint resolves by endpointId', () {
      final found = WindowsAudioDeviceService.instance
          .findEndpoint(r'{0.0.0.00000000}.{22222222-2222-2222-2222-222222222222}');
      expect(found, isNotNull);
      expect(found!.name, 'USB DAC');
    });

    test('findEndpoint resolves by guid', () {
      final found = WindowsAudioDeviceService.instance
          .findEndpoint('{11111111-1111-1111-1111-111111111111}');
      expect(found, isNotNull);
      expect(found!.name, 'Primary Speakers');
    });

    test('findEndpoint handles null, empty, auto, and nonexistent safely', () {
      expect(WindowsAudioDeviceService.instance.findEndpoint(null), isNull);
      expect(WindowsAudioDeviceService.instance.findEndpoint(''), isNull);
      expect(WindowsAudioDeviceService.instance.findEndpoint('auto'), isNull);
      expect(WindowsAudioDeviceService.instance.findEndpoint('nonexistent'), isNull);
    });

    test('device selection accurately marks exactly one item selected', () {
      final endpoints = WindowsAudioDeviceService.instance.endpoints;

      // When setting is empty or 'auto', System Default is selected and no endpoint is selected
      const savedSettingDefault = '';
      final isDefaultSelected1 = savedSettingDefault.isEmpty || savedSettingDefault == 'auto';
      expect(isDefaultSelected1, isTrue);
      for (final ep in endpoints) {
        final isSelected = !isDefaultSelected1 &&
            (savedSettingDefault == ep.mpvDeviceId ||
                savedSettingDefault == ep.endpointId ||
                savedSettingDefault == ep.guid ||
                savedSettingDefault == ep.id);
        expect(isSelected, isFalse);
      }

      // When setting is an endpoint's mpvDeviceId, only that endpoint is selected
      final targetMpvId = endpoints[1].mpvDeviceId;
      final isDefaultSelected2 = targetMpvId.isEmpty || targetMpvId == 'auto';
      expect(isDefaultSelected2, isFalse);
      final selectedList = endpoints.where((ep) {
        return !isDefaultSelected2 &&
            (targetMpvId == ep.mpvDeviceId ||
                targetMpvId == ep.endpointId ||
                targetMpvId == ep.guid ||
                targetMpvId == ep.id);
      }).toList();
      expect(selectedList.length, 1);
      expect(selectedList.first.name, 'USB DAC');

      // Legacy saved setting with GUID also matches exactly that endpoint
      const legacySavedGuid = '{22222222-2222-2222-2222-222222222222}';
      final legacySelected = endpoints.where((ep) {
        return legacySavedGuid.isNotEmpty &&
            legacySavedGuid != 'auto' &&
            (legacySavedGuid == ep.mpvDeviceId ||
                legacySavedGuid == ep.endpointId ||
                legacySavedGuid == ep.guid ||
                legacySavedGuid == ep.id);
      }).toList();
      expect(legacySelected.length, 1);
      expect(legacySelected.first.name, 'USB DAC');
    });
  });
}

