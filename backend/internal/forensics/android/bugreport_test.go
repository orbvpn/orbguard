package android

import (
	"context"
	"strings"
	"testing"

	"orbguard-lab/internal/forensics/models"
)

// Lines from the bug report of a clean, just-booted Android 15 emulator, as
// they were logged. Each matched one of the behaviour rules, and together
// with the rest of that report they made 184 findings, 113 of them high, and
// an infection likelihood of 0.97, for a phone with nothing on it.
var everydayBugreportLines = []string{
	`11-28 07:30:20.388     0     1     1 W init    : type=1400 audit(0.0:5): avc:  denied  { write } for  name="error_report_end" dev="tracefs" ino=6433 scontext=u:r:init:s0 tcontext=u:object_r:debugfs_bootreceiver_tracing:s0 tclass=dir permissive=0`,
	`11-28 07:30:21.101  1000   554   554 W GCH_Utils: FindLibraryPaths: Unable to open directory /vendor/lib64/camera/capture_sessions/ (No such file or directory)`,
	`11-28 07:30:21.204  1000   402   402 E libpsi  : /proc/pressure/memory write failed for psi stall type 'some'; errno=22`,
	`11-28 07:30:22.310  1000   554   554 W PackageSettings: Missing permission state for package com.google.android.overlay.permissioncontroller on user 0`,
	`11-28 07:30:22.512  1000   554   554 I AconfigFlags: Read Aconfig default flag value android.app.admin.flags.headless_single_user_bad_device_admin_state_fix = true`,
	`11-28 07:30:22.513  1000   554   554 I AconfigFlags: Read Aconfig default flag value com.android.internal.telephony.flags.hide_roaming_icon = true`,
	`11-28 07:30:23.020  1000   554   600 I ServiceWatcher: [GeofenceProxy] chose new implementation null`,
	`11-28 07:30:25.700 10181   822   822 D WindowManagerShell: Adding command class splitscreen for SplitScreenController`,
	`11-28 07:30:26.001  1002  1200  1200 I bluetooth: system/btif/src/btif_keystore.cc:61 ConvertEncryptOrDecryptKeyIfNeeded: callback isn't ready.`,
	`11-28 07:30:27.400 10150  1500  1500 I FA      : To enable debug logging run: adb shell setprop log.tag.FA VERBOSE`,
}

func bugreportOf(logLines ...string) string {
	var b strings.Builder
	b.WriteString("== dumpstate: 2026-11-28 07:30:50\n")
	b.WriteString("------ DUMPSYS (dumpsys -t 10 package) ------\n")
	b.WriteString("  Package [com.google.android.networkstack.tethering] (b209bb7):\n")
	// A long line of another section, as real bug reports have.
	b.WriteString("  " + strings.Repeat("0123456789abcdef", 8*1024) + "\n")
	b.WriteString("------ SYSTEM LOG (logcat -v threadtime -v printable -v uid -d *:v) ------\n")
	b.WriteString("--------- beginning of main\n")
	for _, line := range logLines {
		b.WriteString(line + "\n")
	}
	return b.String()
}

func TestBugreportEverydayLinesAreNotFindings(t *testing.T) {
	report := bugreportOf(everydayBugreportLines...)
	result, err := streamParser().ParseBugreportStream(context.Background(), strings.NewReader(report), 0)
	if err != nil {
		t.Fatalf("a clean bug report must be read: %v", err)
	}
	if len(result.Anomalies) != 0 || result.InfectionLikelihood != 0 {
		t.Fatalf("a clean bug report has %d findings, likelihood %v", len(result.Anomalies), result.InfectionLikelihood)
	}

	// The same lines as a pasted log still go through every rule.
	logged, err := streamParser().ParseStream(context.Background(), strings.NewReader(strings.Join(everydayBugreportLines, "\n")), 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(logged.Anomalies) == 0 {
		t.Fatal("the pasted-log rules are unchanged, so these lines still match there")
	}
}

func TestBugreportNamedStalkerwareIsAFinding(t *testing.T) {
	started := `11-28 07:30:25.799  1000   554   619 I ActivityManager: Start proc 4321:com.mspy.lite/u0a190 for service {com.mspy.lite/com.mspy.lite.CoreService}`
	report := bugreportOf(append(append([]string{}, everydayBugreportLines...), started)...)
	result, err := streamParser().ParseBugreportStream(context.Background(), strings.NewReader(report), 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Anomalies) != 1 || result.Anomalies[0].Description != "Known stalkerware" {
		t.Fatalf("want the one named finding, got %+v", result.Anomalies)
	}
	if !result.HasHighFinding() {
		t.Fatal("a named stalkerware is a high finding")
	}
}

// The legitimate patterns quiet the behaviour rules. They do not hide a named
// stalkerware that logs through Firebase.
func TestBugreportNamedSpywareInAFirebaseLineStillCounts(t *testing.T) {
	line := `11-28 07:31:02.100 10190  4321  4400 I FirebaseMessaging: Received command for com.flexispy.agent`
	report := bugreportOf(append(append([]string{}, everydayBugreportLines...), line)...)
	result, err := streamParser().ParseBugreportStream(context.Background(), strings.NewReader(report), 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Anomalies) != 1 {
		t.Fatalf("want the named finding, got %d", len(result.Anomalies))
	}
}

func TestBugreportWithNoLogIsNothingExamined(t *testing.T) {
	report := "== dumpstate: 2026-11-28 07:30:50\n------ DUMPSYS (dumpsys -t 10 package) ------\n  Package [com.example] (1):\n"
	_, err := streamParser().ParseBugreportStream(context.Background(), strings.NewReader(report), 0)
	if err != models.ErrNothingExamined {
		t.Fatalf("want nothing examined, got %v", err)
	}
}
