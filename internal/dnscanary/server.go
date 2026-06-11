package dnscanary

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"

	"github.com/miekg/dns"

	"orbguard-lab/pkg/logger"
)

// QueryInserter records observed canary queries. Implemented by *Store; an
// interface so the responder can be tested without Postgres.
type QueryInserter interface {
	InsertQuery(ctx context.Context, token, resolverIP, qtype, transport string) error
}

// ServerConfig configures the authoritative canary responder.
type ServerConfig struct {
	// Zone is the delegated canary zone (e.g. "dnscheck.example.com").
	// Required; normalized to a lowercase FQDN internally.
	Zone string
	// ListenAddr is the DNS listen address for both UDP and TCP
	// (default ":53").
	ListenAddr string
	// NSHostname is the hostname of this nameserver as published in the NS
	// delegation (default "ns1." + Zone). It is served in NS/SOA answers and
	// must resolve (via glue at the parent) to this server's public IP.
	NSHostname string
	// NSAddr is the public IPv4 of the nameserver, answered for A queries on
	// NSHostname so in-zone glue is self-consistent. Optional.
	NSAddr string
	// AnswerA is the fixed, harmless answer for {token}.Zone A queries
	// (default 192.0.2.53 — TEST-NET-1, never routable).
	AnswerA string
	// TTL for served records in seconds (default 60; tokens are single-use,
	// a low TTL prevents resolvers from masking repeat checks).
	TTL uint32
	// InsertTimeout bounds each query-log database write (default 5s).
	InsertTimeout time.Duration
}

func (c *ServerConfig) withDefaults() error {
	if strings.TrimSpace(c.Zone) == "" {
		return fmt.Errorf("dnscanary: zone is required")
	}
	c.Zone = dns.Fqdn(strings.ToLower(strings.TrimSpace(c.Zone)))
	if c.ListenAddr == "" {
		c.ListenAddr = ":53"
	}
	if c.NSHostname == "" {
		c.NSHostname = "ns1." + c.Zone
	}
	c.NSHostname = dns.Fqdn(strings.ToLower(c.NSHostname))
	if c.AnswerA == "" {
		c.AnswerA = "192.0.2.53"
	}
	if ip := net.ParseIP(c.AnswerA); ip == nil || ip.To4() == nil {
		return fmt.Errorf("dnscanary: answer_a %q is not a valid IPv4 address", c.AnswerA)
	}
	if c.NSAddr != "" {
		if ip := net.ParseIP(c.NSAddr); ip == nil || ip.To4() == nil {
			return fmt.Errorf("dnscanary: ns_addr %q is not a valid IPv4 address", c.NSAddr)
		}
	}
	if c.TTL == 0 {
		c.TTL = 60
	}
	if c.InsertTimeout <= 0 {
		c.InsertTimeout = 5 * time.Second
	}
	return nil
}

// Server is the authoritative DNS responder for the canary zone. It answers
// A queries for {token}.zone with a fixed TEST-NET address, serves correct
// NS/SOA records for the zone apex, and logs every token query (source IP,
// qtype, transport, timestamp) through the QueryInserter.
type Server struct {
	cfg    ServerConfig
	store  QueryInserter
	logger *logger.Logger
	udp    *dns.Server
	tcp    *dns.Server
}

// NewServer creates the responder. store may not be nil: a canary that does
// not record queries is useless.
func NewServer(cfg ServerConfig, store QueryInserter, log *logger.Logger) (*Server, error) {
	if err := cfg.withDefaults(); err != nil {
		return nil, err
	}
	if store == nil {
		return nil, fmt.Errorf("dnscanary: query store is required")
	}
	s := &Server{
		cfg:    cfg,
		store:  store,
		logger: log.WithComponent("dnscanary"),
	}
	mux := dns.NewServeMux()
	mux.HandleFunc(s.cfg.Zone, s.handle)
	// Queries outside the zone are refused: this is an authoritative-only
	// server, never an open resolver.
	mux.HandleFunc(".", s.refuse)
	s.udp = &dns.Server{Addr: cfg.ListenAddr, Net: "udp", Handler: mux}
	s.tcp = &dns.Server{Addr: cfg.ListenAddr, Net: "tcp", Handler: mux}
	return s, nil
}

// Zone returns the normalized FQDN of the served zone.
func (s *Server) Zone() string { return s.cfg.Zone }

// ListenAndServe runs the UDP and TCP listeners until ctx is cancelled or
// either listener fails.
func (s *Server) ListenAndServe(ctx context.Context) error {
	errCh := make(chan error, 2)
	go func() { errCh <- s.udp.ListenAndServe() }()
	go func() { errCh <- s.tcp.ListenAndServe() }()
	s.logger.Info().
		Str("zone", s.cfg.Zone).
		Str("listen", s.cfg.ListenAddr).
		Str("answer_a", s.cfg.AnswerA).
		Msg("authoritative DNS canary serving UDP+TCP")

	select {
	case <-ctx.Done():
		s.shutdown()
		return ctx.Err()
	case err := <-errCh:
		s.shutdown()
		return fmt.Errorf("dnscanary listener failed: %w", err)
	}
}

func (s *Server) shutdown() {
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = s.udp.ShutdownContext(shutdownCtx)
	_ = s.tcp.ShutdownContext(shutdownCtx)
}

// refuse answers REFUSED for anything outside the canary zone.
func (s *Server) refuse(w dns.ResponseWriter, r *dns.Msg) {
	defer s.recoverPanic(w)
	m := new(dns.Msg)
	m.SetRcode(r, dns.RcodeRefused)
	_ = w.WriteMsg(m)
}

// handle answers queries within the canary zone.
func (s *Server) handle(w dns.ResponseWriter, r *dns.Msg) {
	defer s.recoverPanic(w)

	if len(r.Question) != 1 {
		m := new(dns.Msg)
		m.SetRcode(r, dns.RcodeFormatError)
		_ = w.WriteMsg(m)
		return
	}
	q := r.Question[0]
	qname := strings.ToLower(q.Name)

	m := new(dns.Msg)
	m.SetReply(r)
	m.Authoritative = true

	switch {
	case qname == s.cfg.Zone:
		s.answerApex(m, q)
	case qname == s.cfg.NSHostname && q.Qtype == dns.TypeA && s.cfg.NSAddr != "":
		m.Answer = append(m.Answer, &dns.A{
			Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: s.cfg.TTL},
			A:   net.ParseIP(s.cfg.NSAddr).To4(),
		})
	default:
		s.answerToken(m, q, qname, w)
	}

	if err := w.WriteMsg(m); err != nil {
		s.logger.Warn().Err(err).Str("qname", qname).Msg("failed to write DNS response")
	}
}

// answerApex serves SOA/NS (and NODATA for everything else) at the zone apex.
func (s *Server) answerApex(m *dns.Msg, q dns.Question) {
	switch q.Qtype {
	case dns.TypeSOA:
		m.Answer = append(m.Answer, s.soa())
	case dns.TypeNS:
		m.Answer = append(m.Answer, &dns.NS{
			Hdr: dns.RR_Header{Name: s.cfg.Zone, Rrtype: dns.TypeNS, Class: dns.ClassINET, Ttl: s.cfg.TTL},
			Ns:  s.cfg.NSHostname,
		})
	default:
		// NODATA: NOERROR with the SOA in the authority section.
		m.Ns = append(m.Ns, s.soa())
	}
}

// answerToken handles {token}.zone queries: logs the observation and answers
// A queries with the fixed TEST-NET address. AAAA (and other types) return
// NODATA but are still logged — many resolvers query AAAA first, and the
// observation, not the answer, is the entire point of the canary.
func (s *Server) answerToken(m *dns.Msg, q dns.Question, qname string, w dns.ResponseWriter) {
	rel := strings.TrimSuffix(qname, "."+s.cfg.Zone)
	if rel == qname || strings.Contains(rel, ".") || !ValidToken(rel) {
		// Not a single valid token label under the zone.
		m.Rcode = dns.RcodeNameError
		m.Ns = append(m.Ns, s.soa())
		return
	}

	s.logQuery(rel, q.Qtype, w)

	if q.Qtype == dns.TypeA {
		m.Answer = append(m.Answer, &dns.A{
			Hdr: dns.RR_Header{Name: q.Name, Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: s.cfg.TTL},
			A:   net.ParseIP(s.cfg.AnswerA).To4(),
		})
		return
	}
	// NODATA for non-A types on token names.
	m.Ns = append(m.Ns, s.soa())
}

// logQuery records the observation. The database write runs in a goroutine
// with its own timeout so a slow database never delays the DNS answer;
// failures are logged, never silently dropped.
func (s *Server) logQuery(token string, qtype uint16, w dns.ResponseWriter) {
	resolverIP := remoteIP(w.RemoteAddr())
	transport := "udp"
	if _, ok := w.RemoteAddr().(*net.TCPAddr); ok {
		transport = "tcp"
	}
	qtypeStr := dns.TypeToString[qtype]
	if qtypeStr == "" {
		qtypeStr = fmt.Sprintf("TYPE%d", qtype)
	}

	s.logger.Info().
		Str("token", token).
		Str("resolver_ip", resolverIP).
		Str("qtype", qtypeStr).
		Str("transport", transport).
		Msg("canary query observed")

	go func() {
		defer func() {
			if rec := recover(); rec != nil {
				s.logger.Error().Interface("panic", rec).Msg("panic while persisting canary query")
			}
		}()
		ctx, cancel := context.WithTimeout(context.Background(), s.cfg.InsertTimeout)
		defer cancel()
		if err := s.store.InsertQuery(ctx, token, resolverIP, qtypeStr, transport); err != nil {
			s.logger.Error().Err(err).Str("token", token).Msg("failed to persist canary query")
		}
	}()
}

func (s *Server) soa() *dns.SOA {
	return &dns.SOA{
		Hdr:     dns.RR_Header{Name: s.cfg.Zone, Rrtype: dns.TypeSOA, Class: dns.ClassINET, Ttl: s.cfg.TTL},
		Ns:      s.cfg.NSHostname,
		Mbox:    "hostmaster." + s.cfg.Zone,
		Serial:  2026061100,
		Refresh: 3600,
		Retry:   600,
		Expire:  86400,
		Minttl:  s.cfg.TTL,
	}
}

// recoverPanic answers SERVFAIL instead of letting a panic kill the listener
// goroutine. miekg/dns recovers panics itself, but only with a silent drop;
// answering keeps resolvers from hammering retries.
func (s *Server) recoverPanic(w dns.ResponseWriter) {
	if rec := recover(); rec != nil {
		s.logger.Error().Interface("panic", rec).Msg("panic in DNS handler")
		m := new(dns.Msg)
		m.Rcode = dns.RcodeServerFailure
		_ = w.WriteMsg(m)
	}
}

func remoteIP(addr net.Addr) string {
	switch a := addr.(type) {
	case *net.UDPAddr:
		return a.IP.String()
	case *net.TCPAddr:
		return a.IP.String()
	default:
		host, _, err := net.SplitHostPort(addr.String())
		if err != nil {
			return addr.String()
		}
		return host
	}
}
