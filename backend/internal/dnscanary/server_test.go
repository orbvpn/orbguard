package dnscanary

import (
	"context"
	"net"
	"sync"
	"testing"
	"time"

	"github.com/miekg/dns"

	"orbguard-lab/pkg/logger"
)

// memStore records inserts in memory for tests.
type memStore struct {
	mu      sync.Mutex
	queries []ObservedQuery
	tokens  []string
}

func (m *memStore) InsertQuery(_ context.Context, token, resolverIP, qtype, transport string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.tokens = append(m.tokens, token)
	m.queries = append(m.queries, ObservedQuery{
		ResolverIP: resolverIP,
		QType:      qtype,
		Transport:  transport,
		QueriedAt:  time.Now(),
	})
	return nil
}

func (m *memStore) snapshotTokens() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]string, len(m.tokens))
	copy(out, m.tokens)
	return out
}

// startTestServer runs the canary server on an ephemeral localhost port and
// returns its address.
func startTestServer(t *testing.T, store QueryInserter) (addr string, stop func()) {
	t.Helper()

	// Reserve an ephemeral UDP port; reuse the same port number for TCP.
	pc, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("reserve udp port: %v", err)
	}
	addr = pc.LocalAddr().String()
	_ = pc.Close()

	srv, err := NewServer(ServerConfig{
		Zone:       "dnscheck.example.com",
		ListenAddr: addr,
		NSAddr:     "198.51.100.10",
	}, store, logger.NewDevelopment())
	if err != nil {
		t.Fatalf("NewServer: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		_ = srv.ListenAndServe(ctx)
	}()

	// Wait until the server answers.
	c := &dns.Client{Timeout: time.Second}
	msg := new(dns.Msg)
	msg.SetQuestion("dnscheck.example.com.", dns.TypeSOA)
	deadline := time.Now().Add(5 * time.Second)
	for {
		if _, _, err := c.Exchange(msg, addr); err == nil {
			break
		}
		if time.Now().After(deadline) {
			cancel()
			t.Fatal("canary test server did not come up")
		}
		time.Sleep(50 * time.Millisecond)
	}

	return addr, func() {
		cancel()
		<-done
	}
}

func TestValidToken(t *testing.T) {
	valid := []string{"abcdef12", "a1b2c3d4e5f60718", "token-with-hyphen1"}
	for _, tok := range valid {
		if !ValidToken(tok) {
			t.Errorf("ValidToken(%q) = false, want true", tok)
		}
	}
	invalid := []string{"", "short", "UPPERCASE0", "has.dot8", "-leadinghyphen", "tok en123",
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"} // 64 chars
	for _, tok := range invalid {
		if ValidToken(tok) {
			t.Errorf("ValidToken(%q) = true, want false", tok)
		}
	}
}

func TestServerAnswersTokenAAndLogsQuery(t *testing.T) {
	store := &memStore{}
	addr, stop := startTestServer(t, store)
	defer stop()

	c := &dns.Client{Timeout: 2 * time.Second}
	msg := new(dns.Msg)
	msg.SetQuestion("deadbeef00112233.dnscheck.example.com.", dns.TypeA)

	resp, _, err := c.Exchange(msg, addr)
	if err != nil {
		t.Fatalf("exchange: %v", err)
	}
	if resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("rcode = %s, want NOERROR", dns.RcodeToString[resp.Rcode])
	}
	if !resp.Authoritative {
		t.Error("response not authoritative")
	}
	if len(resp.Answer) != 1 {
		t.Fatalf("answers = %d, want 1", len(resp.Answer))
	}
	a, ok := resp.Answer[0].(*dns.A)
	if !ok {
		t.Fatalf("answer is %T, want *dns.A", resp.Answer[0])
	}
	if a.A.String() != "192.0.2.53" {
		t.Errorf("answer A = %s, want 192.0.2.53", a.A)
	}

	// The insert is async; wait for it.
	deadline := time.Now().Add(3 * time.Second)
	for {
		toks := store.snapshotTokens()
		if len(toks) == 1 {
			if toks[0] != "deadbeef00112233" {
				t.Fatalf("logged token = %q, want deadbeef00112233", toks[0])
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("canary query was not logged")
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestServerLogsAAAAButAnswersNodata(t *testing.T) {
	store := &memStore{}
	addr, stop := startTestServer(t, store)
	defer stop()

	c := &dns.Client{Timeout: 2 * time.Second}
	msg := new(dns.Msg)
	msg.SetQuestion("cafebabe11223344.dnscheck.example.com.", dns.TypeAAAA)

	resp, _, err := c.Exchange(msg, addr)
	if err != nil {
		t.Fatalf("exchange: %v", err)
	}
	if resp.Rcode != dns.RcodeSuccess {
		t.Fatalf("rcode = %s, want NOERROR (NODATA)", dns.RcodeToString[resp.Rcode])
	}
	if len(resp.Answer) != 0 {
		t.Fatalf("answers = %d, want 0 (NODATA)", len(resp.Answer))
	}
	if len(resp.Ns) != 1 {
		t.Fatalf("authority records = %d, want 1 (SOA)", len(resp.Ns))
	}
	if _, ok := resp.Ns[0].(*dns.SOA); !ok {
		t.Fatalf("authority record is %T, want *dns.SOA", resp.Ns[0])
	}

	deadline := time.Now().Add(3 * time.Second)
	for {
		if len(store.snapshotTokens()) == 1 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("AAAA canary query was not logged")
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestServerApexSOAAndNS(t *testing.T) {
	store := &memStore{}
	addr, stop := startTestServer(t, store)
	defer stop()

	c := &dns.Client{Timeout: 2 * time.Second}

	soaMsg := new(dns.Msg)
	soaMsg.SetQuestion("dnscheck.example.com.", dns.TypeSOA)
	resp, _, err := c.Exchange(soaMsg, addr)
	if err != nil {
		t.Fatalf("SOA exchange: %v", err)
	}
	if len(resp.Answer) != 1 {
		t.Fatalf("SOA answers = %d, want 1", len(resp.Answer))
	}
	soa, ok := resp.Answer[0].(*dns.SOA)
	if !ok {
		t.Fatalf("answer is %T, want *dns.SOA", resp.Answer[0])
	}
	if soa.Ns != "ns1.dnscheck.example.com." {
		t.Errorf("SOA mname = %s, want ns1.dnscheck.example.com.", soa.Ns)
	}

	nsMsg := new(dns.Msg)
	nsMsg.SetQuestion("dnscheck.example.com.", dns.TypeNS)
	resp, _, err = c.Exchange(nsMsg, addr)
	if err != nil {
		t.Fatalf("NS exchange: %v", err)
	}
	if len(resp.Answer) != 1 {
		t.Fatalf("NS answers = %d, want 1", len(resp.Answer))
	}
	ns, ok := resp.Answer[0].(*dns.NS)
	if !ok {
		t.Fatalf("answer is %T, want *dns.NS", resp.Answer[0])
	}
	if ns.Ns != "ns1.dnscheck.example.com." {
		t.Errorf("NS = %s, want ns1.dnscheck.example.com.", ns.Ns)
	}

	// Glue A record for the nameserver.
	glueMsg := new(dns.Msg)
	glueMsg.SetQuestion("ns1.dnscheck.example.com.", dns.TypeA)
	resp, _, err = c.Exchange(glueMsg, addr)
	if err != nil {
		t.Fatalf("glue exchange: %v", err)
	}
	if len(resp.Answer) != 1 {
		t.Fatalf("glue answers = %d, want 1", len(resp.Answer))
	}
	if a := resp.Answer[0].(*dns.A); a.A.String() != "198.51.100.10" {
		t.Errorf("glue A = %s, want 198.51.100.10", a.A)
	}

	// Apex queries must not be logged as tokens.
	if got := store.snapshotTokens(); len(got) != 0 {
		t.Errorf("apex/glue queries were logged as tokens: %v", got)
	}
}

func TestServerRejectsInvalidNamesAndOutOfZone(t *testing.T) {
	store := &memStore{}
	addr, stop := startTestServer(t, store)
	defer stop()

	c := &dns.Client{Timeout: 2 * time.Second}

	// Multi-label / invalid token under the zone -> NXDOMAIN, not logged.
	badMsg := new(dns.Msg)
	badMsg.SetQuestion("a.b.dnscheck.example.com.", dns.TypeA)
	resp, _, err := c.Exchange(badMsg, addr)
	if err != nil {
		t.Fatalf("exchange: %v", err)
	}
	if resp.Rcode != dns.RcodeNameError {
		t.Errorf("multi-label rcode = %s, want NXDOMAIN", dns.RcodeToString[resp.Rcode])
	}

	// Out-of-zone -> REFUSED (never an open resolver).
	outMsg := new(dns.Msg)
	outMsg.SetQuestion("www.google.com.", dns.TypeA)
	resp, _, err = c.Exchange(outMsg, addr)
	if err != nil {
		t.Fatalf("exchange: %v", err)
	}
	if resp.Rcode != dns.RcodeRefused {
		t.Errorf("out-of-zone rcode = %s, want REFUSED", dns.RcodeToString[resp.Rcode])
	}

	if got := store.snapshotTokens(); len(got) != 0 {
		t.Errorf("invalid queries were logged as tokens: %v", got)
	}
}

func TestServerAnswersOverTCP(t *testing.T) {
	store := &memStore{}
	addr, stop := startTestServer(t, store)
	defer stop()

	c := &dns.Client{Net: "tcp", Timeout: 2 * time.Second}
	msg := new(dns.Msg)
	msg.SetQuestion("0123456789abcdef.dnscheck.example.com.", dns.TypeA)
	resp, _, err := c.Exchange(msg, addr)
	if err != nil {
		t.Fatalf("tcp exchange: %v", err)
	}
	if resp.Rcode != dns.RcodeSuccess || len(resp.Answer) != 1 {
		t.Fatalf("tcp answer: rcode=%s answers=%d", dns.RcodeToString[resp.Rcode], len(resp.Answer))
	}

	deadline := time.Now().Add(3 * time.Second)
	for {
		store.mu.Lock()
		n := len(store.queries)
		var transport string
		if n > 0 {
			transport = store.queries[0].Transport
		}
		store.mu.Unlock()
		if n == 1 {
			if transport != "tcp" {
				t.Fatalf("logged transport = %q, want tcp", transport)
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("tcp canary query was not logged")
		}
		time.Sleep(20 * time.Millisecond)
	}
}
