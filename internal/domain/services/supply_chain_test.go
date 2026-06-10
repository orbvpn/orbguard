package services

import "testing"

func TestCompareOSVVersions(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"1.0.0", "1.0.0", 0},
		{"1.2", "1.2.0", 0},
		{"v1.2.3", "1.2.3", 0},
		{"1.0.0", "2.0.0", -1},
		{"2.0.0", "1.0.0", 1},
		{"1.10.0", "1.9.0", 1},     // numeric, not lexical
		{"10.0.0", "9.0.0", 1},     // numeric, not lexical
		{"1.0.0-rc1", "1.0.0", -1}, // pre-release sorts before release
		{"1.0.0", "1.0.0-rc1", 1},
		{"1.0.0-alpha", "1.0.0-beta", -1},
		{"1.0.0-rc", "1.0.0-rc.1", -1},
		{"1.0.0-1", "1.0.0-alpha", -1}, // numeric pre-release < alphanumeric
		{"1.0.0+build5", "1.0.0", 0},   // build metadata ignored
		{"4.9.3", "4.10.0", -1},
	}
	for _, c := range cases {
		if got := compareOSVVersions(c.a, c.b); got != c.want {
			t.Errorf("compareOSVVersions(%q, %q) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

func TestVersionInEvents(t *testing.T) {
	introducedFixed := []OSVEvent{{Introduced: "0"}, {Fixed: "4.9.3"}}
	if !versionInEvents("4.9.2", introducedFixed) {
		t.Error("4.9.2 should be inside [0, 4.9.3)")
	}
	if versionInEvents("4.9.3", introducedFixed) {
		t.Error("4.9.3 (the fixed version) should not be affected")
	}
	if versionInEvents("5.0.0", introducedFixed) {
		t.Error("5.0.0 should not be inside [0, 4.9.3)")
	}

	multiRange := []OSVEvent{
		{Introduced: "1.0.0"}, {Fixed: "1.5.0"},
		{Introduced: "2.0.0"}, {LastAffected: "2.3.1"},
	}
	if !versionInEvents("1.2.0", multiRange) {
		t.Error("1.2.0 should be inside [1.0.0, 1.5.0)")
	}
	if versionInEvents("1.7.0", multiRange) {
		t.Error("1.7.0 should be between the two affected intervals")
	}
	if !versionInEvents("2.3.1", multiRange) {
		t.Error("2.3.1 (last_affected) should be affected (inclusive)")
	}
	if versionInEvents("2.3.2", multiRange) {
		t.Error("2.3.2 should be past last_affected")
	}

	openEnded := []OSVEvent{{Introduced: "3.0.0"}}
	if !versionInEvents("9.9.9", openEnded) {
		t.Error("open-ended introduced range should affect all later versions")
	}
	if versionInEvents("2.0.0", openEnded) {
		t.Error("versions before introduced should not be affected")
	}
}

func TestVersionMatchesAffected(t *testing.T) {
	ranges := []OSVRange{{
		Type:   "SEMVER",
		Events: []OSVEvent{{Introduced: "0"}, {Fixed: "2.9.10"}},
	}}
	if !versionMatchesAffected("2.9.9", ranges, nil) {
		t.Error("2.9.9 should match SEMVER range [0, 2.9.10)")
	}
	if versionMatchesAffected("2.9.10", ranges, nil) {
		t.Error("2.9.10 should not match")
	}
	if !versionMatchesAffected("1.0.0", nil, []string{"1.0.0", "1.0.1"}) {
		t.Error("explicit version list should match")
	}
	gitRanges := []OSVRange{{
		Type:   "GIT",
		Events: []OSVEvent{{Introduced: "abc123"}, {Fixed: "def456"}},
	}}
	if versionMatchesAffected("1.0.0", gitRanges, nil) {
		t.Error("GIT ranges must be skipped (not comparable to release versions)")
	}
}

func TestCVSS3BaseScore(t *testing.T) {
	cases := []struct {
		vector string
		want   float64
	}{
		// Log4Shell (CVE-2021-44228)
		{"CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H", 10.0},
		// Classic network RCE, unchanged scope
		{"CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H", 9.8},
		// Medium severity example
		{"CVSS:3.1/AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:L/A:N", 4.2},
		// No impact at all
		{"CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N", 0.0},
	}
	for _, c := range cases {
		got, ok := cvss3BaseScore(c.vector)
		if !ok {
			t.Errorf("cvss3BaseScore(%q) failed to parse", c.vector)
			continue
		}
		if got != c.want {
			t.Errorf("cvss3BaseScore(%q) = %.1f, want %.1f", c.vector, got, c.want)
		}
	}
	if _, ok := cvss3BaseScore("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N"); ok {
		t.Error("CVSS v4 vectors must not be scored by the v3 calculator")
	}
}

func TestCVSS2BaseScore(t *testing.T) {
	got, ok := cvss2BaseScore("AV:N/AC:L/Au:N/C:P/I:P/A:P")
	if !ok {
		t.Fatal("cvss2BaseScore failed to parse a valid v2 vector")
	}
	if got != 7.5 {
		t.Errorf("cvss2BaseScore(AV:N/AC:L/Au:N/C:P/I:P/A:P) = %.1f, want 7.5", got)
	}
	got, ok = cvss2BaseScore("AV:N/AC:L/Au:N/C:C/I:C/A:C")
	if !ok {
		t.Fatal("cvss2BaseScore failed to parse a valid v2 vector")
	}
	if got != 10.0 {
		t.Errorf("cvss2BaseScore(AV:N/AC:L/Au:N/C:C/I:C/A:C) = %.1f, want 10.0", got)
	}
}

func TestDefaultEcosystem(t *testing.T) {
	cases := []struct {
		name string
		want string
	}{
		{"com.squareup.okhttp3:okhttp", "Maven"},
		{"com.google.firebase.analytics", "Maven"},
		{"@angular/core", "npm"},
		{"lodash/fp", "npm"},
		{"okhttp", "Maven"},
	}
	for _, c := range cases {
		if got := DefaultEcosystem(c.name); got != c.want {
			t.Errorf("DefaultEcosystem(%q) = %q, want %q", c.name, got, c.want)
		}
	}
}
