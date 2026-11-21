package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"strconv"
	"strings"
	"time"
)

// Paid breach lookups are bounded per UTC day at three levels, all reserved
// atomically in Redis before any provider is called:
//
//   - per caller identity;
//   - per client address (as the ingress saw it, IPv6 per /64), because device
//     keys are free and one client can hold any number of them;
//   - one service-wide total, with a lower ceiling for keys issued in the last
//     24 hours, so a stranger minting fresh keys cannot spend the part of the
//     budget that existing devices and paying accounts rely on.
//
// A refused request consumes nothing. If Redis cannot answer, the lookup is
// refused: the paid call is never made without a reservation.

var (
	// ErrPaidLookupLimited means a daily limit on paid lookups was reached.
	ErrPaidLookupLimited = errors.New("daily breach lookup limit reached")
	// ErrPaidLookupUnavailable means the budget could not be checked, so no
	// paid lookup was made.
	ErrPaidLookupUnavailable = errors.New("breach lookup budget unavailable")
)

// PaidLookupTier is how much of the service-wide budget a caller may reach.
type PaidLookupTier int

const (
	// PaidLookupNewDevice is a device key issued in the last 24 hours.
	PaidLookupNewDevice PaidLookupTier = iota
	// PaidLookupEstablished is an older device key or a free account.
	PaidLookupEstablished
	// PaidLookupPaid is a verified paying account or the service credential.
	PaidLookupPaid
)

const (
	// defaultPaidLookupsPerDay is the service-wide daily total. One lookup is
	// at most one call to each configured provider. Override it with
	// paidLookupsEnvVar; the variable is optional.
	defaultPaidLookupsPerDay = 500
	paidLookupsEnvVar        = "ORBGUARD_DARKWEB_PAID_LOOKUPS_PER_DAY"

	newDeviceSharePercent   = 30
	establishedSharePercent = 80

	paidLookupsPerDevice  = 10
	paidLookupsPerAccount = 50
	paidLookupsPerAddress = 30

	paidLookupKeyTTL     = 48 * time.Hour
	paidLookupRedisLimit = time.Second
)

// PaidLookupCaller identifies who a paid lookup is spent for. It is built by
// the handler from the authenticated context, never from client input.
type PaidLookupCaller struct {
	Tier     PaidLookupTier
	Identity string
	// Address is the trusted client address. Paid-tier callers have none.
	Address string
}

type paidLookupCallerKey struct{}

// WithPaidLookupCaller attaches the caller a paid lookup is charged to.
func WithPaidLookupCaller(ctx context.Context, caller PaidLookupCaller) context.Context {
	return context.WithValue(ctx, paidLookupCallerKey{}, caller)
}

// paidLookupStore reserves one unit on every key, or on none (*cache.RedisCache).
// It returns 0 when reserved, or the 1-based index of the key at its limit.
type paidLookupStore interface {
	ReserveQuota(ctx context.Context, keys []string, limits []int64, ttl time.Duration) (int, error)
}

// paidLookupsPerDay reads the optional override; anything but a positive
// integer keeps the default.
func paidLookupsPerDay() int64 {
	if raw := strings.TrimSpace(os.Getenv(paidLookupsEnvVar)); raw != "" {
		if value, err := strconv.ParseInt(raw, 10, 64); err == nil && value > 0 {
			return value
		}
	}
	return defaultPaidLookupsPerDay
}

// paidLookupCeiling is how far the service-wide counter may be for this tier.
func paidLookupCeiling(total int64, tier PaidLookupTier) int64 {
	switch tier {
	case PaidLookupPaid:
		return total
	case PaidLookupEstablished:
		return total * establishedSharePercent / 100
	default:
		return total * newDeviceSharePercent / 100
	}
}

func paidLookupKeyPart(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:12])
}

// reservePaidLookup takes one unit of today's budget for the caller in ctx.
func (m *DarkWebMonitor) reservePaidLookup(ctx context.Context) error {
	caller, ok := ctx.Value(paidLookupCallerKey{}).(PaidLookupCaller)
	if !ok || caller.Identity == "" || m.paidLookups == nil {
		return ErrPaidLookupUnavailable
	}

	total := m.paidLookupsPerDay
	// The braces are a Redis hash tag: all of one day's keys share a slot, so
	// the reservation script also works on a clustered Redis.
	prefix := "darkweb:paid:{" + time.Now().UTC().Format("20060102") + "}:"

	identityLimit := int64(paidLookupsPerDevice)
	switch caller.Tier {
	case PaidLookupPaid:
		identityLimit = paidLookupsPerAccount
		if caller.Identity == PaidLookupServiceIdentity {
			identityLimit = total
		}
	}
	keys := []string{prefix + "id:" + paidLookupKeyPart(caller.Identity)}
	limits := []int64{identityLimit}
	if caller.Tier != PaidLookupPaid {
		if caller.Address == "" {
			return ErrPaidLookupUnavailable
		}
		keys = append(keys, prefix+"addr:"+paidLookupKeyPart(caller.Address))
		limits = append(limits, paidLookupsPerAddress)
	}
	keys = append(keys, prefix+"total")
	limits = append(limits, paidLookupCeiling(total, caller.Tier))

	reserveCtx, cancel := context.WithTimeout(ctx, paidLookupRedisLimit)
	defer cancel()
	exhausted, err := m.paidLookups.ReserveQuota(reserveCtx, keys, limits, paidLookupKeyTTL)
	if err != nil {
		m.logger.Warn().Err(err).Msg("paid lookup budget unavailable; refusing the lookup")
		return ErrPaidLookupUnavailable
	}
	if exhausted != 0 {
		return ErrPaidLookupLimited
	}
	return nil
}

// PaidLookupServiceIdentity is the identity of the service credential.
const PaidLookupServiceIdentity = "service"

// PaidLookupRetryAfter is the time until the daily counters roll over.
func PaidLookupRetryAfter(now time.Time) time.Duration {
	now = now.UTC()
	next := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, time.UTC)
	return next.Sub(now)
}
