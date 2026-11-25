package models

import "testing"

func TestHasHighFinding(t *testing.T) {
	for _, c := range []struct {
		severity ForensicSeverity
		want     bool
	}{
		{ForensicSeverityCritical, true},
		{ForensicSeverityHigh, true},
		{ForensicSeverityMedium, false},
	} {
		anomaly := &ForensicResult{Anomalies: []Anomaly{{Severity: c.severity}}}
		if got := anomaly.HasHighFinding(); got != c.want {
			t.Errorf("anomaly %s: got %v", c.severity, got)
		}
		threat := &ForensicResult{DetectedThreats: []DetectedThreat{{Severity: c.severity}}}
		if got := threat.HasHighFinding(); got != c.want {
			t.Errorf("threat %s: got %v", c.severity, got)
		}
	}
	if (&ForensicResult{}).HasHighFinding() {
		t.Error("an empty result has no high finding")
	}
}
