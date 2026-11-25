package ai

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"sync"
	"time"
)

const (
	// phoneReportThreshold is how many distinct device keys, and also how many
	// distinct client networks, must report a number before other users see
	// it as reported. Keys are free and a client can move between networks,
	// so neither one alone counts as independent reporters.
	phoneReportThreshold = 5
	// phoneReportWindow is how long one report keeps counting.
	phoneReportWindow = 30 * 24 * time.Hour
	// maxReportedNumbers bounds the memory of the in-process store.
	maxReportedNumbers = 20000
	// maxNewReportedNumbersPerDay bounds what reports can add to Redis.
	maxNewReportedNumbersPerDay = 500
	// phoneReportReadLimit keeps a slow Redis from delaying a lookup or report.
	phoneReportReadLimit = 300 * time.Millisecond
)

// PhoneReportStore keeps who reported which number. Every value it receives
// is already hashed, so it holds no phone number, key or address.
type PhoneReportStore interface {
	RecordPhoneReport(ctx context.Context, number, reporterKey, network string, now time.Time) error
	PhoneReporterCounts(ctx context.Context, number string, now time.Time) (keys, networks int, err error)
}

func hashReportValue(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:12])
}

// phoneReportBackend is the Redis side (*cache.RedisCache).
type phoneReportBackend interface {
	RecordDistinctReport(ctx context.Context, keysKey, networksKey, dayKey, reporter, network string, now time.Time, window time.Duration, maxPerSet, maxNewPerDay int64) error
	CountDistinctReporters(ctx context.Context, keysKey, networksKey string, since time.Time) (int64, int64, error)
}

// redisPhoneReports shares report counts across replicas and restarts.
type redisPhoneReports struct {
	backend phoneReportBackend
}

// NewRedisPhoneReportStore returns a store backed by the shared Redis.
func NewRedisPhoneReportStore(backend phoneReportBackend) PhoneReportStore {
	return &redisPhoneReports{backend: backend}
}

// The hash tag keeps every key of the record script in one Redis slot.
const phoneReportKeyPrefix = "phone:reports:{phone-reports}:"

func (s *redisPhoneReports) RecordPhoneReport(ctx context.Context, number, reporterKey, network string, now time.Time) error {
	return s.backend.RecordDistinctReport(ctx,
		phoneReportKeyPrefix+"keys:"+number,
		phoneReportKeyPrefix+"nets:"+number,
		phoneReportKeyPrefix+"new:"+now.UTC().Format("20060102"),
		reporterKey, network, now, phoneReportWindow, phoneReportThreshold, maxNewReportedNumbersPerDay)
}

func (s *redisPhoneReports) PhoneReporterCounts(ctx context.Context, number string, now time.Time) (int, int, error) {
	keys, networks, err := s.backend.CountDistinctReporters(ctx,
		phoneReportKeyPrefix+"keys:"+number,
		phoneReportKeyPrefix+"nets:"+number,
		now.Add(-phoneReportWindow))
	return int(keys), int(networks), err
}

// memPhoneReports is the store when no Redis is configured. Its counts belong
// to one process.
type memPhoneReports struct {
	mu      sync.Mutex
	numbers map[string]*phoneReporters
}

type phoneReporters struct {
	keys     map[string]time.Time
	networks map[string]time.Time
}

func newMemPhoneReports() *memPhoneReports {
	return &memPhoneReports{numbers: make(map[string]*phoneReporters)}
}

func (s *memPhoneReports) RecordPhoneReport(_ context.Context, number, reporterKey, network string, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	reporters, tracked := s.numbers[number]
	if !tracked {
		if len(s.numbers) >= maxReportedNumbers {
			s.evict(now)
		}
		reporters = &phoneReporters{keys: make(map[string]time.Time, 1), networks: make(map[string]time.Time, 1)}
		s.numbers[number] = reporters
	}
	reporters.prune(now)
	addReporter(reporters.keys, reporterKey, now)
	addReporter(reporters.networks, network, now)
	return nil
}

func (s *memPhoneReports) PhoneReporterCounts(_ context.Context, number string, now time.Time) (int, int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	reporters, tracked := s.numbers[number]
	if !tracked {
		return 0, 0, nil
	}
	reporters.prune(now)
	return len(reporters.keys), len(reporters.networks), nil
}

// evict makes room for a new number, preferring one below the threshold, so a
// flood of invented numbers cannot push out a number many clients reported.
func (s *memPhoneReports) evict(now time.Time) {
	for number, reporters := range s.numbers {
		reporters.prune(now)
		if len(reporters.keys) < phoneReportThreshold || len(reporters.networks) < phoneReportThreshold {
			delete(s.numbers, number)
			return
		}
	}
	for number := range s.numbers {
		delete(s.numbers, number)
		return
	}
}

func addReporter(set map[string]time.Time, reporter string, now time.Time) {
	if _, known := set[reporter]; known || len(set) < phoneReportThreshold {
		set[reporter] = now
	}
}

func (r *phoneReporters) prune(now time.Time) {
	for _, set := range []map[string]time.Time{r.keys, r.networks} {
		for reporter, at := range set {
			if now.Sub(at) > phoneReportWindow {
				delete(set, reporter)
			}
		}
	}
}
