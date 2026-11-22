package digital_footprint

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/models"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/pkg/logger"
)

// scanProviders answers in memory, so the scan never opens a socket. The
// password range service matches whatever hash the test put in rangeBody;
// the breach and paste services have nothing on the address.
type scanProviders struct {
	rangeBody  string
	rangeCalls atomic.Int64
}

func (p *scanProviders) RoundTrip(r *http.Request) (*http.Response, error) {
	status, body := http.StatusNotFound, ""
	if r.URL.Host == "api.pwnedpasswords.com" {
		p.rangeCalls.Add(1)
		status, body = http.StatusOK, p.rangeBody
	}
	return &http.Response{
		Status: strconv.Itoa(status) + " " + http.StatusText(status), StatusCode: status,
		Header: http.Header{}, Request: r, Body: io.NopCloser(strings.NewReader(body)),
	}, nil
}

func scanTestRedis(t *testing.T) *cache.RedisCache {
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

func TestFootprintScanMakesNoPasswordFinding(t *testing.T) {
	const email = "person@example.com"
	sum := sha1.Sum([]byte(email))
	suffix := strings.ToUpper(hex.EncodeToString(sum[:]))[5:]
	providers := &scanProviders{rangeBody: "0000000000000000000000000000000000A:1\r\n" + suffix + ":4242\r\n"}

	scanner := NewDarkWebScanner(scanTestRedis(t), &logger.Logger{Logger: zerolog.Nop()})
	scanner.httpClient = &http.Client{Transport: providers}

	_, exposures, err := scanner.Scan(context.Background(), email, "")
	if err != nil {
		t.Fatal(err)
	}
	for _, exposure := range exposures {
		if exposure.Type == models.ExposureTypePassword {
			t.Errorf("a scan with no password reported: %s", exposure.Context)
		}
	}
	if got := providers.rangeCalls.Load(); got != 0 {
		t.Errorf("the scan queried the password range service %d times", got)
	}
}
