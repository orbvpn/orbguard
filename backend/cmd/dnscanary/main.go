// Command dnscanary is the authoritative DNS responder for the OrbGuard DNS
// leak-check canary zone.
//
// It serves the zone $CANARY_ZONE (e.g. dnscheck.example.com): every
// A/AAAA query for {token}.$CANARY_ZONE is answered with a fixed, harmless
// TEST-NET address and logged (token, resolver source IP, qtype, transport,
// timestamp) to Postgres table orbguard_lab.dns_canary_queries, where the
// OrbGuard API's POST /network/dns/check leak section looks tokens up.
// NS/SOA records for the zone apex are answered correctly so the NS
// delegation from the parent zone validates.
//
// Configuration is environment-only (the container runs standalone, no
// config.yaml required):
//
//	CANARY_ZONE                (required; ORBGUARD_DNS_CANARY_ZONE also accepted)
//	CANARY_LISTEN_ADDR         DNS listen address, UDP+TCP (default ":53")
//	CANARY_HEALTH_ADDR         HTTP health listen address (default ":8053")
//	CANARY_NS_HOSTNAME         published nameserver hostname (default "ns1.{zone}")
//	CANARY_NS_ADDR             public IPv4 of this server, served as the glue
//	                           A record for CANARY_NS_HOSTNAME (optional)
//	CANARY_ANSWER_A            fixed A answer for tokens (default "192.0.2.53")
//	ORBGUARD_DATABASE_HOST     Postgres host (default "localhost")
//	ORBGUARD_DATABASE_PORT     Postgres port (default 5432)
//	ORBGUARD_DATABASE_USER     Postgres user (default "orbguard")
//	ORBGUARD_DATABASE_PASSWORD Postgres password
//	ORBGUARD_DATABASE_DBNAME   Postgres database (default "orbguard_lab")
//	ORBGUARD_DATABASE_SSLMODE  Postgres sslmode (default "require")
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"orbguard-lab/internal/config"
	"orbguard-lab/internal/dnscanary"
	"orbguard-lab/internal/infrastructure/database"
	"orbguard-lab/pkg/logger"
)

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envIntOr(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func main() {
	log := logger.NewProduction()
	if envOr("ORBGUARD_APP_ENVIRONMENT", "production") != "production" {
		log = logger.NewDevelopment()
	}
	logger.SetGlobal(log)
	log = log.WithComponent("dnscanary-main")

	zone := envOr("CANARY_ZONE", os.Getenv("ORBGUARD_DNS_CANARY_ZONE"))
	if zone == "" {
		log.Fatal().Msg("CANARY_ZONE (or ORBGUARD_DNS_CANARY_ZONE) is required")
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	// Postgres via the same ORBGUARD_DATABASE_* envs as the API.
	dbCfg := config.DatabaseConfig{
		Host:            envOr("ORBGUARD_DATABASE_HOST", "localhost"),
		Port:            envIntOr("ORBGUARD_DATABASE_PORT", 5432),
		User:            envOr("ORBGUARD_DATABASE_USER", "orbguard"),
		Password:        os.Getenv("ORBGUARD_DATABASE_PASSWORD"),
		DBName:          envOr("ORBGUARD_DATABASE_DBNAME", "orbguard_lab"),
		SSLMode:         envOr("ORBGUARD_DATABASE_SSLMODE", "require"),
		Schema:          envOr("ORBGUARD_DATABASE_SCHEMA", "orbguard_lab"),
		MaxOpenConns:    envIntOr("ORBGUARD_DATABASE_MAX_OPEN_CONNS", 5),
		MaxIdleConns:    envIntOr("ORBGUARD_DATABASE_MAX_IDLE_CONNS", 1),
		ConnMaxLifetime: 30 * time.Minute,
	}
	db, err := database.NewPostgres(ctx, dbCfg, log)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to connect to Postgres")
	}
	defer db.Close()

	srv, err := dnscanary.NewServer(dnscanary.ServerConfig{
		Zone:       zone,
		ListenAddr: envOr("CANARY_LISTEN_ADDR", ":53"),
		NSHostname: os.Getenv("CANARY_NS_HOSTNAME"),
		NSAddr:     os.Getenv("CANARY_NS_ADDR"),
		AnswerA:    os.Getenv("CANARY_ANSWER_A"),
	}, dnscanary.NewStore(db.Pool()), log)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to create canary DNS server")
	}

	// Health endpoint: 200 only while the database (the canary's entire
	// purpose is logging to it) is reachable.
	healthAddr := envOr("CANARY_HEALTH_ADDR", ":8053")
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		pingCtx, pingCancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer pingCancel()
		status := "ok"
		code := http.StatusOK
		if err := db.Ping(pingCtx); err != nil {
			status = fmt.Sprintf("database unreachable: %v", err)
			code = http.StatusServiceUnavailable
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(code)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"status": status,
			"zone":   srv.Zone(),
		})
	})
	healthSrv := &http.Server{
		Addr:              healthAddr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		log.Info().Str("addr", healthAddr).Msg("health endpoint listening")
		if err := healthSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error().Err(err).Msg("health endpoint failed")
			cancel()
		}
	}()
	defer func() {
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutdownCancel()
		_ = healthSrv.Shutdown(shutdownCtx)
	}()

	log.Info().Str("zone", srv.Zone()).Msg("starting authoritative DNS canary")
	if err := srv.ListenAndServe(ctx); err != nil && ctx.Err() == nil {
		log.Fatal().Err(err).Msg("DNS canary server failed")
	}
	log.Info().Msg("DNS canary stopped")
}
