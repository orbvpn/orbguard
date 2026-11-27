package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// An Android bug report as a phone makes it, sent the way the app's Full
// Forensic Scan sends it. Before this, a real bug report failed with 500 at
// its first line over 64 KiB, and once read, the everyday words of a clean
// phone's system logs came back as a high likelihood of spyware.
func TestBugreportUploadOfAPhone(t *testing.T) {
	h := newGuardRouter(t)
	const path = "/api/v1/forensics/android/bugreport/upload"

	report := func(log string) []byte {
		text := "== dumpstate: 2026-11-28 07:30:50\n" +
			"------ DUMPSYS (/system/bin/dumpsys) ------\n" +
			"  Package [com.google.android.networkstack.tethering] (b209bb7):\n" +
			"  " + strings.Repeat("0123456789abcdef", 24*1024) + "\n" +
			"------ SYSTEM LOG (logcat -v threadtime -v printable -v uid -d *:v) ------\n" +
			"--------- beginning of main\n" + log
		return zipOf(t, map[string][]byte{"bugreport-device-2026-11-28.txt": []byte(text)})
	}
	everyday := strings.Join([]string{
		`11-28 07:30:22.512  1000   554   554 I AconfigFlags: Read Aconfig default flag value android.app.admin.flags.headless_single_user_bad_device_admin_state_fix = true`,
		`11-28 07:30:23.020  1000   554   600 I ServiceWatcher: [GeofenceProxy] chose new implementation null`,
		`11-28 07:30:21.204  1000   402   402 E libpsi  : /proc/pressure/memory write failed for psi stall type 'some'; errno=22`,
		`11-28 07:30:25.700 10181   822   822 D WindowManagerShell: Adding command class splitscreen for SplitScreenController`,
		`11-28 07:30:27.400 10150  1500  1500 I FA      : To enable debug logging run: adb shell setprop log.tag.FA VERBOSE`,
	}, "\n") + "\n"

	t.Run("a clean phone is read and comes back clean", func(t *testing.T) {
		assertExaminedClean(t, upload(h, path, "bugreport.zip", report(everyday), asDevice()))
	})

	t.Run("a named stalkerware is found", func(t *testing.T) {
		started := `11-28 07:30:25.799  1000   554   619 I ActivityManager: Start proc 4321:com.mspy.lite/u0a190 for service {com.mspy.lite/com.mspy.lite.CoreService}` + "\n"
		rec := upload(h, path, "bugreport.zip", report(everyday+started), asDevice())
		assertOneFinding(t, rec, "Known stalkerware")
	})
}

func assertOneFinding(t *testing.T, rec *httptest.ResponseRecorder, description string) {
	t.Helper()
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d: %s", rec.Code, rec.Body.String())
	}
	body := decodeJSON(t, rec.Body.Bytes())
	anomalies, _ := body["anomalies"].([]any)
	if len(anomalies) != 1 {
		t.Fatalf("want one finding: %s", rec.Body.String())
	}
	if got := anomalies[0].(map[string]any)["description"]; got != description {
		t.Fatalf("finding %v, want %q", got, description)
	}
}
