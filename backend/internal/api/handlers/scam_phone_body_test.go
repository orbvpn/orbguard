package handlers

import (
	"testing"

	"orbguard-lab/internal/domain/models"
)

func TestPhoneReputationBodyNamesAnUnavailableSource(t *testing.T) {
	body := phoneReputationBody("+4915112340066", &models.ScamAnalysisResult{
		UnavailableSources: []string{"numverify"},
	})
	sources, ok := body["unavailable_sources"].([]string)
	if !ok || len(sources) != 1 || sources[0] != "numverify" {
		t.Fatalf("unavailable_sources = %v", body["unavailable_sources"])
	}
	if clean := phoneReputationBody("+4915112340066", &models.ScamAnalysisResult{}); clean["unavailable_sources"] != nil {
		t.Fatalf("a full answer reports an unavailable source: %v", clean["unavailable_sources"])
	}
}
