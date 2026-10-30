#include "include/flutter_local_notifications_windows/flutter_local_notifications_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

namespace {

class FlutterLocalNotificationsWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  FlutterLocalNotificationsWindowsPlugin();

  virtual ~FlutterLocalNotificationsWindowsPlugin();

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

// static
void FlutterLocalNotificationsWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  // This plugin uses FFI directly from Dart, so there's no MethodChannel to set up.
  // We just need to register an empty plugin so it's included in the build.
  // The actual functionality is provided via the flutter_local_notifications_windows.dll
  // that Dart loads via FFI.
  auto plugin = std::make_unique<FlutterLocalNotificationsWindowsPlugin>();
  registrar->AddPlugin(std::move(plugin));
}

FlutterLocalNotificationsWindowsPlugin::FlutterLocalNotificationsWindowsPlugin() {}

FlutterLocalNotificationsWindowsPlugin::~FlutterLocalNotificationsWindowsPlugin() {}

void FlutterLocalNotificationsWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  result->NotImplemented();
}

}  // namespace

void FlutterLocalNotificationsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  if (!registrar) {
    return;
  }

  auto* plugin_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);

  if (plugin_registrar) {
    FlutterLocalNotificationsWindowsPlugin::RegisterWithRegistrar(plugin_registrar);
  }
}