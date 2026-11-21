package services

import "context"

// RefreshLockerForTest lets the external test package supply a lock.
type RefreshLockerForTest = refreshLocker

// SetRefreshForTest replaces the sweep and the cross-replica lock.
func (m *DarkWebMonitor) SetRefreshForTest(sweep func(context.Context) error, lock RefreshLockerForTest) {
	m.sweep = sweep
	m.refreshLock = lock
}
