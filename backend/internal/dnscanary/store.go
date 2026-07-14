// Package dnscanary implements the DNS leak-check canary system: a tiny
// authoritative DNS responder for a controlled zone (served by cmd/dnscanary)
// plus the Postgres-backed query log shared between that responder (writes)
// and the API's POST /network/dns/check leak section (reads).
//
// The principle: the only honest way to know which resolver a device's DNS
// queries actually egress through is to control an authoritative nameserver
// and watch who asks it. The client resolves {random-token}.{canary zone}
// through its normal local resolver; whichever recursive resolver contacts
// the authoritative server for that token is, by construction, the resolver
// really handling the device's traffic.
package dnscanary

import (
	"context"
	"fmt"
	"regexp"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// tokenPattern is the accepted canary-token format: a single DNS label of
// lowercase letters, digits and hyphens. Clients generate 32 lowercase hex
// characters; the looser bound keeps the responder tolerant without ever
// accepting junk that could not have been a generated token.
var tokenPattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{7,62}$`)

// ValidToken reports whether s is an acceptable canary token (one DNS label,
// 8..63 chars, lowercase alphanumeric/hyphen, not starting with a hyphen).
func ValidToken(s string) bool {
	return tokenPattern.MatchString(s)
}

// ObservedQuery is one query for a canary token as seen by the authoritative
// canary server.
type ObservedQuery struct {
	// ResolverIP is the source address the query arrived from: the egress IP
	// of the recursive resolver that performed the lookup for the device.
	ResolverIP string `json:"resolver_ip"`
	// ResolverASN is the autonomous system of ResolverIP when enrichment is
	// available; nil otherwise (never guessed).
	ResolverASN *int `json:"resolver_asn,omitempty"`
	// QType is the DNS query type ("A", "AAAA").
	QType string `json:"qtype"`
	// Transport is "udp" or "tcp".
	Transport string `json:"transport"`
	// QueriedAt is when the authoritative server received the query.
	QueriedAt time.Time `json:"queried_at"`
}

// Store is the Postgres-backed canary query log
// (orbguard_lab.dns_canary_queries, migration 021).
type Store struct {
	pool *pgxpool.Pool
}

// NewStore creates a Store on an existing pgx pool.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool}
}

// InsertQuery records one observed canary query.
func (s *Store) InsertQuery(ctx context.Context, token, resolverIP, qtype, transport string) error {
	_, err := s.pool.Exec(ctx,
		`INSERT INTO orbguard_lab.dns_canary_queries (token, resolver_ip, qtype, transport)
		 VALUES ($1, $2, $3, $4)`,
		token, resolverIP, qtype, transport,
	)
	if err != nil {
		return fmt.Errorf("insert dns canary query: %w", err)
	}
	return nil
}

// LookupToken returns all queries observed for a token, oldest first.
// An empty slice with nil error means no query has (yet) reached the
// authoritative server.
func (s *Store) LookupToken(ctx context.Context, token string) ([]ObservedQuery, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT host(resolver_ip), resolver_asn, qtype, transport, queried_at
		 FROM orbguard_lab.dns_canary_queries
		 WHERE token = $1
		 ORDER BY queried_at ASC
		 LIMIT 50`,
		token,
	)
	if err != nil {
		return nil, fmt.Errorf("lookup dns canary token: %w", err)
	}
	defer rows.Close()

	var out []ObservedQuery
	for rows.Next() {
		var q ObservedQuery
		if err := rows.Scan(&q.ResolverIP, &q.ResolverASN, &q.QType, &q.Transport, &q.QueriedAt); err != nil {
			return nil, fmt.Errorf("scan dns canary query: %w", err)
		}
		out = append(out, q)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate dns canary queries: %w", err)
	}
	return out, nil
}
