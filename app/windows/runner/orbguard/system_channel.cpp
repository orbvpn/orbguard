#include "orbguard/system_channel.h"

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <string>
#include <variant>

#include "orbguard/scanner.h"

namespace orbguard {
namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kChannelName[] = "com.orb.guard/system";

// Pulls a named int argument out of the standard-codec argument map.
int IntArgument(const EncodableValue* arguments,
                const char* name,
                int fallback) {
  if (!arguments) return fallback;
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (!map) return fallback;
  auto it = map->find(EncodableValue(name));
  if (it == map->end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

}  // namespace

void RegisterSystemChannel(flutter::FlutterEngine* engine) {
  if (!engine) return;

  auto channel = std::make_shared<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();

        // The Dart pipeline calls this before the native stages; there is no
        // per-scan state to build on Windows, so acknowledge and continue.
        if (method == "initializeScan") {
          result->Success(EncodableValue(true));
        } else if (method == "checkRootAccess") {
          result->Success(CheckElevatedAccess());
        } else if (method == "scanNetwork") {
          result->Success(ScanNetwork());
        } else if (method == "scanProcesses") {
          result->Success(ScanProcesses());
        } else if (method == "scanFileSystem") {
          result->Success(ScanFileSystem());
        } else if (method == "scanDatabases") {
          result->Success(ScanDatabases());
        } else if (method == "scanMemory") {
          result->Success(ScanMemory());
        } else if (method == "getInstalledCertificates") {
          result->Success(GetInstalledCertificates());
        } else if (method == "getInstalledApps") {
          result->Success(GetInstalledApps());
        } else if (method == "getEnabledAccessibilityServices") {
          result->Success(GetAccessibilityServices());
        } else if (method == "getInstalledKeyboards") {
          result->Success(GetInstalledKeyboards());
        } else if (method == "getLocationAccessHistory") {
          result->Success(
              GetLocationAccessHistory(IntArgument(call.arguments(), "hours", 24)));
        } else {
          // Everything else genuinely has no Windows implementation. Returning
          // NotImplemented raises MissingPluginException in Dart, which the
          // scan pipeline reports as an unavailable check — never as "clean".
          result->NotImplemented();
        }
      });

  // Keep the channel alive for the process lifetime; the handler owns no state.
  static std::shared_ptr<flutter::MethodChannel<EncodableValue>> retained;
  retained = channel;
}

}  // namespace orbguard
