package services

import (
	"context"
	"net/http"
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
