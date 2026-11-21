package ai

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
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

// reportFrom files one report from credential i on network n.
func reportFrom(s *PhoneReputationService, number string, i, n int) {
	s.ReportNumber(context.Background(), number, "scam", fmt.Sprintf("device:%d", i), fmt.Sprintf("198.51.%d.0/24", n))
}

func TestOneNetworkCannotFlagANumber(t *testing.T) {
	s := newReportService()
	for i := 0; i < 500; i++ {
		reportFrom(s, reportedNumber, i, 7)
	}
	if scam, spam := lookupFlags(t, s, reportedNumber); scam || spam {
		t.Fatalf("one network flagged the number: scam=%v spam=%v", scam, spam)
	}
}

func TestOneKeyOnManyNetworksCannotFlagANumber(t *testing.T) {
	s := newReportService()
	for n := 0; n < 50; n++ {
		reportFrom(s, reportedNumber, 1, n)
	}
	if scam, spam := lookupFlags(t, s, reportedNumber); scam || spam {
		t.Fatalf("one key flagged the number: scam=%v spam=%v", scam, spam)
	}
}

func TestDistinctKeysAndNetworksReachTheReportedStateNeverVerifiedScam(t *testing.T) {
	s := newReportService()
	for i := 0; i < phoneReportThreshold-1; i++ {
		reportFrom(s, reportedNumber, i, i)
		if scam, spam := lookupFlags(t, s, reportedNumber); scam || spam {
			t.Fatalf("%d reporters flagged the number", i+1)
		}
	}
	reportFrom(s, reportedNumber, 99, 99)
	scam, spam := lookupFlags(t, s, reportedNumber)
	if !spam {
		t.Fatalf("%d distinct keys and networks must mark the number as reported", phoneReportThreshold)
	}
	if scam {
		t.Fatal("community reports must never produce a verified-scam result")
	}
}

func TestReportWithoutServerDerivedIdentityIsNotCounted(t *testing.T) {
	s := newReportService()
	// One report short of the threshold, so that a counted empty reporter
	// would be the one that flags the number.
	for i := 0; i < phoneReportThreshold-1; i++ {
		reportFrom(s, reportedNumber, i, i)
	}
	ctx := context.Background()
	s.ReportNumber(ctx, reportedNumber, "scam", "device:50", "")
	s.ReportNumber(ctx, reportedNumber, "scam", "", "203.0.113.0/24")
	if _, spam := lookupFlags(t, s, reportedNumber); spam {
		t.Fatal("reports without a key or a network must not count")
	}
}

func TestExpiredReportsStopCounting(t *testing.T) {
	s := newReportService()
	store := newMemPhoneReports()
	s.SetReportStore(store)
	old := time.Now().Add(-phoneReportWindow - time.Hour)
	number := hashReportValue(s.normalizeNumber(reportedNumber))
	for i := 0; i < phoneReportThreshold; i++ {
		if err := store.RecordPhoneReport(context.Background(), number, strconv.Itoa(i), strconv.Itoa(i), old); err != nil {
			t.Fatal(err)
		}
	}
	if _, spam := lookupFlags(t, s, reportedNumber); spam {
		t.Fatal("reports older than the window must not count")
	}
}

func TestReportCannotHideAKnownScamNumber(t *testing.T) {
	s := newReportService()
	const known = "+18005551234"
	for i := 0; i < phoneReportThreshold; i++ {
		reportFrom(s, known, i, i)
	}
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
		reportFrom(s, reportedNumber, i, i)
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
	store := newMemPhoneReports()
	s.SetReportStore(store)
	for i := 0; i < maxReportedNumbers+50; i++ {
		reportFrom(s, fmt.Sprintf("+49151%08d", i), 1, 1)
	}
	if got := len(store.numbers); got > maxReportedNumbers {
		t.Fatalf("tracked %d numbers, limit %d", got, maxReportedNumbers)
	}
	before := len(store.numbers)
	reportFrom(s, "not-a-number", 1, 1)
	if len(store.numbers) > before {
		t.Fatal("an input that is not a phone number was tracked")
	}
}

// phoneVerdict is what the scam route answers for a number.
func phoneVerdict(t *testing.T, d *ScamDetector, number string) (float64, bool) {
	t.Helper()
	result, err := d.Analyze(context.Background(), &models.ScamAnalysisRequest{
		ContentType: models.ContentTypePhone,
		Content:     number,
		PhoneNumber: number,
	})
	if err != nil {
		t.Fatal(err)
	}
	return result.RiskScore, result.IsScam
}

func newReportDetector() *ScamDetector {
	return NewScamDetector(&logger.Logger{Logger: zerolog.Nop()}, ScamDetectorConfig{EnablePhoneRep: true})
}

func TestReportsOnlyEverRaiseTheVerdict(t *testing.T) {
	for _, number := range []string{
		"+2348012345678",   // high-risk country
		"+919812345678",    // high-risk country
		"+491511234567890", // invalid length
		"+18445551234",     // toll-free VoIP
		"+18005551234",     // known scam
		"+19005551234",     // premium rate
		reportedNumber,     // ordinary
	} {
		t.Run(number, func(t *testing.T) {
			d := newReportDetector()
			risk, scam := phoneVerdict(t, d, number)
			for i := 0; i < phoneReportThreshold; i++ {
				reportFrom(d.phoneReputation, number, i, i)
			}
			after, scamAfter := phoneVerdict(t, d, number)
			if after < risk {
				t.Fatalf("reports lowered the risk: %.2f to %.2f", risk, after)
			}
			if scam && !scamAfter {
				t.Fatal("reports cleared the scam verdict")
			}
			if !scam && scamAfter {
				t.Fatal("reports alone produced a scam verdict")
			}
		})
	}
}

func TestReportedNumberRisesToJustBelowTheScamThreshold(t *testing.T) {
	d := newReportDetector()
	before, _ := phoneVerdict(t, d, reportedNumber)
	for i := 0; i < phoneReportThreshold; i++ {
		reportFrom(d.phoneReputation, reportedNumber, i, i)
	}
	after, scam := phoneVerdict(t, d, reportedNumber)
	if after <= before || after != 0.6 || scam {
		t.Fatalf("risk %.2f to %.2f, scam=%v", before, after, scam)
	}
}

type failingReportStore struct{}

func (failingReportStore) RecordPhoneReport(context.Context, string, string, string, time.Time) error {
	return errors.New("store down")
}

func (failingReportStore) PhoneReporterCounts(context.Context, string, time.Time) (int, int, error) {
	return phoneReportThreshold, phoneReportThreshold, errors.New("store down")
}

func TestReportStoreDownLeavesTheLookupAsItWas(t *testing.T) {
	d := newReportDetector()
	before, scamBefore := phoneVerdict(t, d, reportedNumber)
	d.SetPhoneReportStore(failingReportStore{})
	reportFrom(d.phoneReputation, reportedNumber, 1, 1)
	after, scamAfter := phoneVerdict(t, d, reportedNumber)
	if after != before || scamAfter != scamBefore {
		t.Fatalf("store down changed the verdict: %.2f/%v to %.2f/%v", before, scamBefore, after, scamAfter)
	}
}

func testReportRedis(t *testing.T) *cache.RedisCache {
	t.Helper()
	addr := os.Getenv("ORBGUARD_TEST_REDIS_ADDR")
	if addr == "" {
		t.Skip("ORBGUARD_TEST_REDIS_ADDR not set; skipping Redis-backed test")
	}
	host, portText, _ := strings.Cut(addr, ":")
	port, err := strconv.Atoi(portText)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	redisCache, err := cache.NewRedis(ctx, config.RedisConfig{
		Host: host, Port: port, KeyPrefix: fmt.Sprintf("orbguard-test:%d:", time.Now().UnixNano()),
	}, &logger.Logger{Logger: zerolog.Nop()})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = redisCache.Close() })
	return redisCache
}

func TestReportsAreSharedAcrossReplicasAndRestarts(t *testing.T) {
	redisCache := testReportRedis(t)
	replicaA, replicaB := newReportService(), newReportService()
	replicaA.SetReportStore(NewRedisPhoneReportStore(redisCache))
	replicaB.SetReportStore(NewRedisPhoneReportStore(redisCache))

	for i := 0; i < 3; i++ {
		reportFrom(replicaA, reportedNumber, i, i)
	}
	for i := 3; i < phoneReportThreshold; i++ {
		reportFrom(replicaB, reportedNumber, i, i)
	}
	for name, s := range map[string]*PhoneReputationService{"A": replicaA, "B": replicaB} {
		if _, spam := lookupFlags(t, s, reportedNumber); !spam {
			t.Fatalf("replica %s does not see the shared count", name)
		}
	}
	restarted := newReportService()
	restarted.SetReportStore(NewRedisPhoneReportStore(redisCache))
	if _, spam := lookupFlags(t, restarted, reportedNumber); !spam {
		t.Fatal("the count did not survive a restart")
	}
}

func TestRedisReportsNeedKeysAndNetworksAndKeepNoClearValue(t *testing.T) {
	redisCache := testReportRedis(t)
	s := newReportService()
	s.SetReportStore(NewRedisPhoneReportStore(redisCache))

	for n := 0; n < 10; n++ {
		reportFrom(s, reportedNumber, 1, n)
	}
	for i := 0; i < 10; i++ {
		reportFrom(s, reportedNumber, i, 3)
	}
	// Ten keys and ten networks were seen, in two sets that each satisfy the
	// rule on one axis only; the rule counts distinct values per axis.
	if _, spam := lookupFlags(t, s, reportedNumber); !spam {
		t.Fatal("five keys and five networks must flag the number")
	}

	ctx := context.Background()
	keys, err := redisCache.Client().Keys(ctx, "*").Result()
	if err != nil {
		t.Fatal(err)
	}
	digits := strings.TrimPrefix(reportedNumber, "+")
	for _, key := range keys {
		if strings.Contains(key, digits) {
			t.Fatalf("clear number in key %s", key)
		}
	}
}

func TestRedisReportsStopAtTheDailyCapOfNewNumbers(t *testing.T) {
	redisCache := testReportRedis(t)
	store := NewRedisPhoneReportStore(redisCache)
	ctx := context.Background()
	now := time.Now()
	for i := 0; i < maxNewReportedNumbersPerDay+5; i++ {
		if err := store.RecordPhoneReport(ctx, fmt.Sprintf("n%d", i), "k", "n", now); err != nil {
			t.Fatal(err)
		}
	}
	if keys, _, err := store.PhoneReporterCounts(ctx, fmt.Sprintf("n%d", maxNewReportedNumbersPerDay+1), now); err != nil || keys != 0 {
		t.Fatalf("a number past the daily cap was stored: keys=%d err=%v", keys, err)
	}
	if keys, _, err := store.PhoneReporterCounts(ctx, "n0", now); err != nil || keys != 1 {
		t.Fatalf("a number inside the cap: keys=%d err=%v", keys, err)
	}
}
