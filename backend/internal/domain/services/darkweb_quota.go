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

	"orbguard-lab/internal/domain/models"
)

// Paid breach lookups are bounded per UTC day, reserved atomically in Redis
// before any provider is called:
//
//   - per caller identity;
//   - for a key younger than 24 hours or an account, per client address (as
//     the ingress saw it, IPv6 per /64), at a low number;
//   - for an older key, per network the key was issued on, so keys minted in
//     bulk share one allowance while strangers behind one VPN exit do not;
//   - one service-wide total, with a lower ceiling for each kind of caller.
//
// A refused request consumes nothing, and a failed provider call gives its
// unit back, within a small hourly allowance so that failing lookups cannot
// become free provider calls. If Redis cannot answer, the lookup is refused:
// the paid call is never made without a reservation.

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
	// PaidLookupNewDevice is a device key issued in the last 24 hours, or an
	// OrbNet account whose token does not show a plan paid for with money.
	PaidLookupNewDevice PaidLookupTier = iota
	// PaidLookupEstablished is an older device key.
	PaidLookupEstablished
	// PaidLookupSweep is the monitoring refresh.
	PaidLookupSweep
	// PaidLookupPaid is an OrbNet account on a paid plan.
	PaidLookupPaid
	// PaidLookupService is the service credential.
	PaidLookupService
)

const (
	// defaultPaidLookupsPerDay is the service-wide daily total. One lookup
	// queries each configured provider once; Intelligence X may need several
	// requests for one search. Override it with paidLookupsEnvVar; the
	// variable is optional.
	defaultPaidLookupsPerDay = 500
	paidLookupsEnvVar        = "ORBGUARD_DARKWEB_PAID_LOOKUPS_PER_DAY"

	newDeviceSharePercent   = 30
	sweepSharePercent       = 50
	establishedSharePercent = 80

	paidLookupsPerDevice     = 8
	paidLookupsPerAccount    = 50
	paidLookupsPerNewAddress = 5
	paidLookupsPerIssuer     = 20

	paidLookupKeyTTL     = 48 * time.Hour
	paidLookupRedisLimit = time.Second

	// paidLookupMemoTTL is how long one caller's answer for one email is
	// reused, so an automatic retry makes no new provider call.
	paidLookupMemoTTL = 10 * time.Minute

	refundsPerCallerPerHour = 5
	refundsPerHour          = 60
	refundKeyTTL            = 2 * time.Hour
)

// PaidLookupServiceIdentity is the identity of the service credential.
const PaidLookupServiceIdentity = "service"

const paidLookupSweepIdentity = "sweep"

// PaidLookupCaller identifies who a paid lookup is spent for. It is built by
// the handler from the authenticated context, never from client input.
type PaidLookupCaller struct {
	Tier     PaidLookupTier
	Identity string
	// Address is the trusted client address. Used for PaidLookupNewDevice.
	Address string
	// Issuer tags the network an older key was issued on. Keys issued before
	// the tag existed have none.
	Issuer string
}

type paidLookupCallerKey struct{}

// WithPaidLookupCaller attaches the caller a paid lookup is charged to.
func WithPaidLookupCaller(ctx context.Context, caller PaidLookupCaller) context.Context {
	return context.WithValue(ctx, paidLookupCallerKey{}, caller)
}

// paidLookupStore is the shared state of the budget (*cache.RedisCache).
// ReserveQuota takes one unit on every key or on none, and returns 0 when
// reserved or the 1-based index of the key at its limit.
type paidLookupStore interface {
	ReserveQuota(ctx context.Context, keys []string, limits []int64, ttl time.Duration) (int, error)
	ReleaseQuota(ctx context.Context, keys []string) error
	GetJSON(ctx context.Context, key string, dest any) error
	SetJSON(ctx context.Context, key string, value any, ttl time.Duration) error
}

// paidLookupReservation is what a refund has to give back.
type paidLookupReservation struct {
	caller PaidLookupCaller
	keys   []string
}

// paidLookupMemo is one caller's first answer for one email. It never holds
// the address: the key is a hash and the result is stored without it.
type paidLookupMemo struct {
	Failed bool                        `json:"failed,omitempty"`
	Result *models.BreachCheckResponse `json:"result,omitempty"`
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
	case PaidLookupService, PaidLookupPaid:
		return total
	case PaidLookupEstablished:
		return total * establishedSharePercent / 100
	case PaidLookupSweep:
		return total * sweepSharePercent / 100
	default:
		return total * newDeviceSharePercent / 100
	}
}

func paidLookupKeyPart(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:12])
}

func paidLookupCallerFrom(ctx context.Context) (PaidLookupCaller, bool) {
	caller, ok := ctx.Value(paidLookupCallerKey{}).(PaidLookupCaller)
	return caller, ok && caller.Identity != ""
}

// reservePaidLookup takes one unit of today's budget for the caller in ctx.
func (m *DarkWebMonitor) reservePaidLookup(ctx context.Context) (*paidLookupReservation, error) {
	caller, ok := paidLookupCallerFrom(ctx)
	if !ok || m.paidLookups == nil {
		return nil, ErrPaidLookupUnavailable
	}

	total := m.paidLookupsPerDay
	// The braces are a Redis hash tag: all of one day's keys share a slot, so
	// the reservation script also works on a clustered Redis.
	prefix := "darkweb:paid:{" + time.Now().UTC().Format("20060102") + "}:"

	identityLimit := int64(paidLookupsPerDevice)
	switch caller.Tier {
	case PaidLookupService, PaidLookupSweep:
		identityLimit = total
	case PaidLookupPaid:
		identityLimit = paidLookupsPerAccount
	}
	keys := []string{prefix + "id:" + paidLookupKeyPart(caller.Identity)}
	limits := []int64{identityLimit}
	switch caller.Tier {
	case PaidLookupNewDevice:
		if caller.Address == "" {
			return nil, ErrPaidLookupUnavailable
		}
		keys = append(keys, prefix+"addr:"+paidLookupKeyPart(caller.Address))
		limits = append(limits, paidLookupsPerNewAddress)
	case PaidLookupEstablished:
		if caller.Issuer != "" {
			keys = append(keys, prefix+"issuer:"+paidLookupKeyPart(caller.Issuer))
			limits = append(limits, paidLookupsPerIssuer)
		}
	}
	keys = append(keys, prefix+"total")
	limits = append(limits, paidLookupCeiling(total, caller.Tier))

	reserveCtx, cancel := context.WithTimeout(ctx, paidLookupRedisLimit)
	defer cancel()
	exhausted, err := m.paidLookups.ReserveQuota(reserveCtx, keys, limits, paidLookupKeyTTL)
	if err != nil {
		m.logger.Warn().Err(err).Msg("paid lookup budget unavailable; refusing the lookup")
		return nil, ErrPaidLookupUnavailable
	}
	if exhausted != 0 {
		return nil, ErrPaidLookupLimited
	}
	return &paidLookupReservation{caller: caller, keys: keys}, nil
}

// refundPaidLookup gives back the unit of a lookup no provider answered. Past
// the hourly allowance the charge stands, so failures stay bounded.
func (m *DarkWebMonitor) refundPaidLookup(ctx context.Context, reservation *paidLookupReservation) {
	refundCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), paidLookupRedisLimit)
	defer cancel()

	perCaller := int64(refundsPerCallerPerHour)
	if reservation.caller.Tier == PaidLookupSweep || reservation.caller.Tier == PaidLookupService {
		perCaller = refundsPerHour
	}
	prefix := "darkweb:paid:refund:{" + time.Now().UTC().Format("2006010215") + "}:"
	exhausted, err := m.paidLookups.ReserveQuota(refundCtx,
		[]string{prefix + "id:" + paidLookupKeyPart(reservation.caller.Identity), prefix + "total"},
		[]int64{perCaller, refundsPerHour}, refundKeyTTL)
	if err != nil || exhausted != 0 {
		return
	}
	if err := m.paidLookups.ReleaseQuota(refundCtx, reservation.keys); err != nil {
		m.logger.Warn().Err(err).Msg("failed to return a paid lookup unit")
	}
}

func paidLookupMemoKey(caller PaidLookupCaller, email string) string {
	return "darkweb:paid:memo:" + paidLookupKeyPart(caller.Identity+"\x00"+strings.ToLower(strings.TrimSpace(email)))
}

// recallPaidLookup returns this caller's earlier answer for this email.
func (m *DarkWebMonitor) recallPaidLookup(ctx context.Context, email string) (result *models.BreachCheckResponse, found bool, err error) {
	caller, ok := paidLookupCallerFrom(ctx)
	if !ok || m.paidLookups == nil {
		return nil, false, nil
	}
	readCtx, cancel := context.WithTimeout(ctx, paidLookupRedisLimit)
	defer cancel()
	var memo paidLookupMemo
	if err := m.paidLookups.GetJSON(readCtx, paidLookupMemoKey(caller, email), &memo); err != nil {
		return nil, false, nil
	}
	if memo.Failed {
		return nil, true, ErrBreachProvidersFailed
	}
	if memo.Result == nil {
		return nil, false, nil
	}
	memo.Result.Email = email
	return memo.Result, true, nil
}

// rememberPaidLookup stores this caller's answer; a nil result is a failure.
func (m *DarkWebMonitor) rememberPaidLookup(ctx context.Context, email string, result *models.BreachCheckResponse) {
	caller, ok := paidLookupCallerFrom(ctx)
	if !ok || m.paidLookups == nil {
		return
	}
	memo := paidLookupMemo{Failed: result == nil, Result: breachResultWithoutEmail(result)}
	writeCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), paidLookupRedisLimit)
	defer cancel()
	if err := m.paidLookups.SetJSON(writeCtx, paidLookupMemoKey(caller, email), memo, paidLookupMemoTTL); err != nil {
		m.logger.Warn().Err(err).Msg("failed to remember a paid lookup")
	}
}

// breachResultWithoutEmail is the form of a result that may be stored.
func breachResultWithoutEmail(result *models.BreachCheckResponse) *models.BreachCheckResponse {
	if result == nil {
		return nil
	}
	stored := *result
	stored.Email = ""
	return &stored
}

// PaidLookupRetryAfter is the time until the daily counters roll over.
func PaidLookupRetryAfter(now time.Time) time.Duration {
	now = now.UTC()
	next := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, time.UTC)
	return next.Sub(now)
}
