// Registers the `com.orb.guard/system` MethodChannel on Windows.
#ifndef RUNNER_ORBGUARD_SYSTEM_CHANNEL_H_
#define RUNNER_ORBGUARD_SYSTEM_CHANNEL_H_

namespace flutter {
class FlutterEngine;
}

namespace orbguard {

// Call once, after the Flutter engine exists. Methods the Windows scanner does
// not implement deliberately return NotImplemented so the Dart layer raises
// MissingPluginException and reports the check as unavailable, rather than
// treating an empty result as "clean".
void RegisterSystemChannel(flutter::FlutterEngine* engine);

}  // namespace orbguard

#endif  // RUNNER_ORBGUARD_SYSTEM_CHANNEL_H_
