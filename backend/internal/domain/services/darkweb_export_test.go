package services

import (
	"context"
	"net/http"

	"orbguard-lab/internal/domain/models"
)

// RefreshLockerForTest lets the external test package supply a lock.
type RefreshLockerForTest = refreshLocker

// SetRefreshForTest replaces the sweep and the cross-replica lock.
func (m *DarkWebMonitor) SetRefreshForTest(sweep func(context.Context) error, lock RefreshLockerForTest) {
	m.sweep = sweep
	m.refreshLock = lock
}

// PaidLookupStoreForTest lets the external test package supply the budget store.
type PaidLookupStoreForTest = paidLookupStore

// SetPaidLookupsForTest replaces the budget store and the daily total.
func (m *DarkWebMonitor) SetPaidLookupsForTest(store PaidLookupStoreForTest, perDay int64) {
	m.paidLookups = store
	m.paidLookupsPerDay = perDay
}

// SetTransportForTest routes the client's requests through rt.
func (c *HIBPClient) SetTransportForTest(rt http.RoundTripper) {
	c.httpClient = &http.Client{Transport: rt}
}

// SetTransportForTest routes the client's requests through rt.
func (c *LeakCheckClient) SetTransportForTest(rt http.RoundTripper) {
	c.httpClient = &http.Client{Transport: rt}
}

// SetTransportForTest routes the client's requests through rt.
func (c *IntelXClient) SetTransportForTest(rt http.RoundTripper) {
	c.httpClient = &http.Client{Transport: rt}
}

// SweepAssetsForTest runs the refresh loop with the refresh's own caller and
// returns how many assets it stored.
func (m *DarkWebMonitor) SweepAssetsForTest(ctx context.Context, assets []models.MonitoredAsset) (int, error) {
	stored := 0
	ctx = WithPaidLookupCaller(ctx, PaidLookupCaller{Tier: PaidLookupSweep, Identity: paidLookupSweepIdentity})
	err := m.sweepAssets(ctx, assets, func(context.Context, *models.MonitoredAsset, *models.BreachCheckResponse) { stored++ })
	return stored, err
}
