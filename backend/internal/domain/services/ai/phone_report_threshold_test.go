package ai

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/pkg/logger"
)

const reportedNumber = "+4915112345678"

func newReportService() *PhoneReputationService {
	return NewPhoneReputationService(&logger.Logger{Logger: zerolog.Nop()}, PhoneReputationConfig{CacheTTL: time.Hour})
}

func lookupFlags(t *testing.T, s *PhoneReputationService, number string) (scam, spam bool) {
	t.Helper()
	rep, err := s.Lookup(context.Background(), number)
	if err != nil {
		t.Fatalf("lookup: %v", err)
	}
	return rep.IsScam, rep.IsSpam
}

func TestOneNetworkCannotFlagANumber(t *testing.T) {
	s := newReportService()
	for i := 0; i < 500; i++ {
		s.ReportNumber(reportedNumber, "scam", "198.51.100.0/24")
	}
	if scam, spam := lookupFlags(t, s, reportedNumber); scam || spam {
		t.Fatalf("one network flagged the number: scam=%v spam=%v", scam, spam)
	}
}

func TestDistinctNetworksReachTheReportedStateNeverVerifiedScam(t *testing.T) {
	s := newReportService()
	for i := 0; i < phoneReportThreshold-1; i++ {
		s.ReportNumber(reportedNumber, "scam", fmt.Sprintf("198.51.%d.0/24", i))
		if scam, spam := lookupFlags(t, s, reportedNumber); scam || spam {
			t.Fatalf("%d networks flagged the number", i+1)
		}
	}
	s.ReportNumber(reportedNumber, "scam", "203.0.113.0/24")
	scam, spam := lookupFlags(t, s, reportedNumber)
	if !spam {
		t.Fatalf("%d distinct networks must mark the number as reported", phoneReportThreshold)
	}
	if scam {
		t.Fatal("community reports must never produce a verified-scam result")
	}
}

func TestReportWithoutServerDerivedNetworkIsNotCounted(t *testing.T) {
	s := newReportService()
	// One report short of the threshold, so that a counted empty reporter
	// would be the one that flags the number.
	for i := 0; i < phoneReportThreshold-1; i++ {
		s.ReportNumber(reportedNumber, "scam", fmt.Sprintf("198.51.%d.0/24", i))
	}
	for i := 0; i < phoneReportThreshold*2; i++ {
		s.ReportNumber(reportedNumber, "scam", "")
	}
	if _, spam := lookupFlags(t, s, reportedNumber); spam {
		t.Fatal("reports without a network must not count")
	}
}

func TestExpiredReportsStopCounting(t *testing.T) {
	s := newReportService()
	for i := 0; i < phoneReportThreshold; i++ {
		s.ReportNumber(reportedNumber, "scam", fmt.Sprintf("198.51.%d.0/24", i))
	}
	s.reportsMu.Lock()
	for reporter := range s.communityReports[reportedNumber] {
		s.communityReports[reportedNumber][reporter] = time.Now().Add(-phoneReportWindow - time.Hour)
	}
	s.reportsMu.Unlock()
	if _, spam := lookupFlags(t, s, reportedNumber); spam {
		t.Fatal("reports older than the window must not count")
	}
}

func TestReportCannotHideAKnownScamNumber(t *testing.T) {
	s := newReportService()
	const known = "+18005551234"
	s.ReportNumber(known, "spam", "198.51.100.0/24")
	if scam, _ := lookupFlags(t, s, known); !scam {
		t.Fatal("a report replaced the known-scam result")
	}
}

func TestReportDoesNotChangeTheCachedEntry(t *testing.T) {
	s := newReportService()
	if _, err := s.Lookup(context.Background(), reportedNumber); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < phoneReportThreshold; i++ {
		s.ReportNumber(reportedNumber, "scam", fmt.Sprintf("198.51.%d.0/24", i))
	}
	if scam, spam := lookupFlags(t, s, reportedNumber); scam || !spam {
		t.Fatalf("after the threshold: scam=%v spam=%v", scam, spam)
	}
	if cached := s.getFromCache(reportedNumber); cached == nil || cached.IsSpam || cached.IsScam {
		t.Fatalf("the cached lookup entry must stay unchanged: %+v", cached)
	}
}

func TestReportMemoryIsBounded(t *testing.T) {
	s := newReportService()
	for i := 0; i < maxReportedNumbers+50; i++ {
		s.ReportNumber(fmt.Sprintf("+49151%08d", i), "scam", "198.51.100.0/24")
	}
	if got := len(s.communityReports); got > maxReportedNumbers {
		t.Fatalf("tracked %d numbers, limit %d", got, maxReportedNumbers)
	}
	s.ReportNumber("not-a-number", "scam", "198.51.100.0/24")
	if _, tracked := s.communityReports[s.normalizeNumber("not-a-number")]; tracked {
		t.Fatal("an input that is not a phone number was tracked")
	}
}
