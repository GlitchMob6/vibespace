import 'package:vibespace/models/settings.dart';
import 'package:vibespace/providers/settings_provider.dart';

class ReEnrichTestSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> syncLyricsSettingsToBackend({AppSettings? settings}) async {}
}
