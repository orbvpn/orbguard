package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"google.golang.org/grpc"

	"orbguard-lab/internal/api"
	"orbguard-lab/internal/api/handlers"
	"orbguard-lab/internal/config"
	"orbguard-lab/internal/domain/services"
	"orbguard-lab/internal/domain/services/ai"
	"orbguard-lab/internal/domain/services/desktop_security"
	"orbguard-lab/internal/domain/services/digital_footprint"
	"orbguard-lab/internal/forensics"
	grpcserver "orbguard-lab/internal/grpc/threatintel"
	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/internal/infrastructure/graph"
	"orbguard-lab/internal/sources"
	"orbguard-lab/internal/sources/free/abusech"
	"orbguard-lab/internal/sources/free/analysis"
	"orbguard-lab/internal/sources/free/blocklists"
	"orbguard-lab/internal/sources/free/government"
	"orbguard-lab/internal/sources/free/ip"
	"orbguard-lab/internal/sources/free/mobile"
	"orbguard-lab/internal/sources/free/phishing"
	"orbguard-lab/internal/sources/misp"
	"orbguard-lab/internal/sources/premium"
	"orbguard-lab/internal/streaming"
	"orbguard-lab/pkg/logger"
)

func main() {
	// Load configuration
	cfg, err := config.LoadDefault()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
		os.Exit(1)
	}

	// Initialize logger
	var log *logger.Logger
	if cfg.App.Environment == "production" {
		log = logger.NewProduction()
	} else {
		log = logger.NewDevelopment()
	}
	logger.SetGlobal(log)

	log.Info().
		Str("app", cfg.App.Name).
		Str("env", cfg.App.Environment).
		Str("version", cfg.App.Version).
		Msg("starting OrbGuard Lab")

	// Create context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Initialize infrastructure
	db, redisCache, err := initInfrastructure(ctx, cfg, log)
	if err != nil {
		log.Fatal().Err(err).Msg("failed to initialize infrastructure")
	}
	defer func() {
		if db != nil {
			db.Close()
		}
		if redisCache != nil {
			redisCache.Close()
		}
	}()

	// Initialize repositories
	var repos *repository.Repositories
	var urlListRepo *repository.URLListRepository
	var deviceSecurityRepo *repository.DeviceSecurityRepository
	if db != nil {
		repos = repository.NewRepositories(db.Pool())
		urlListRepo = repository.NewURLListRepository(db.Pool())
		deviceSecurityRepo = repository.NewDeviceSecurityRepository(db.Pool())
		log.Info().Msg("repositories initialized with database")
	} else {
		log.Warn().Msg("running without database - repositories unavailable")
	}

	// Initialize streaming infrastructure
	var natsPublisher *streaming.NATSPublisher
	if cfg.NATS.Enabled {
		var err error
		natsPublisher, err = streaming.NewNATSPublisher(ctx, cfg.NATS, log)
		if err != nil {
			log.Warn().Err(err).Msg("failed to connect to NATS, continuing without real-time streaming")
		} else {
			log.Info().Str("url", cfg.NATS.URL).Msg("connected to NATS")
		}
	}

	// Create event bus for real-time updates
	eventBus := streaming.NewEventBus(natsPublisher, log)
	log.Info().Bool("nats_enabled", natsPublisher != nil).Msg("event bus initialized")

	// Create WebSocket hub for mobile app real-time updates
	wsHub := streaming.NewWebSocketHub(natsPublisher, log)
	go wsHub.Run(ctx)

	// Initialize services
	normalizer := services.NewNormalizer(log)
	deduplicator := services.NewDeduplicator(redisCache, log)
	scorer := services.NewScorer(cfg.Scoring, log)

	// Create aggregator with repository adapter (if available)
	var aggregatorRepo services.IndicatorRepository
	if repos != nil {
		aggregatorRepo = repos.AggregatorAdapter
	}
	aggregator := services.NewAggregator(cfg.Aggregation, aggregatorRepo, normalizer, deduplicator, scorer, redisCache, log)
	scheduler := services.NewScheduler(aggregator, redisCache, log)

	// Register source connectors
	registry := sources.NewRegistry(log)
	registerConnectors(registry, log)
	registry.ConfigureFromSourcesConfig(cfg.Sources)

	// Register connectors with aggregator
	for _, conn := range registry.List() {
		aggregator.RegisterConnector(conn)
	}

	// Wire event publisher for real-time updates
	eventPublisher := streaming.NewEventBusPublisher(eventBus, wsHub)
	aggregator.SetEventPublisher(eventPublisher)

	// Initialize URL reputation service (Safe Web protection)
	var safeBrowsingClient services.SafeBrowsingClient
	if sbKey := cfg.EffectiveSafeBrowsingKey(); sbKey != "" {
		safeBrowsingClient = services.NewGoogleSafeBrowsingClient(services.SafeBrowsingConfig{
			APIKey: sbKey,
		}, log)
		log.Info().Msg("Google Safe Browsing client initialized for URL reputation")
	} else {
		log.Warn().Msg("Safe Browsing disabled (no API key) - set ORBGUARD_SAFE_BROWSING_API_KEY to enable live URL lookups")
	}
	urlService := services.NewURLReputationService(repos, redisCache, safeBrowsingClient, log)
	if urlListRepo != nil {
		urlService.SetURLListRepository(urlListRepo)
	}
	log.Info().Bool("safe_browsing", safeBrowsingClient != nil).Msg("URL reputation service initialized")

	// Initialize dark web monitoring (HIBP integration)
	if cfg.HIBP.APIKey == "" {
		log.Warn().Msg("HIBP API key not configured - dark web breach lookups degraded (set ORBGUARD_HIBP_API_KEY)")
	}
	hibpClient := services.NewHIBPClient(services.HIBPConfig{
		APIKey: cfg.HIBP.APIKey,
	}, log)
	var leakCheckClient *services.LeakCheckClient
	if cfg.LeakCheck.Enabled && cfg.LeakCheck.APIKey != "" {
		leakCheckClient = services.NewLeakCheckClient(services.LeakCheckClientConfig{
			APIKey: cfg.LeakCheck.APIKey,
		}, log)
		log.Info().Msg("LeakCheck breach provider enabled")
	} else {
		log.Warn().Msg("LeakCheck breach provider disabled (set ORBGUARD_LEAKCHECK_API_KEY and ORBGUARD_LEAKCHECK_ENABLED=true)")
	}
	var intelXClient *services.IntelXClient
	if cfg.IntelX.Enabled && cfg.IntelX.APIKey != "" {
		intelXClient = services.NewIntelXClient(services.IntelXClientConfig{
			APIKey:  cfg.IntelX.APIKey,
			BaseURL: cfg.IntelX.BaseURL,
		}, log)
		log.Info().Msg("Intelligence X breach provider enabled")
	} else {
		log.Warn().Msg("Intelligence X breach provider disabled (set ORBGUARD_INTELX_API_KEY and ORBGUARD_INTELX_ENABLED=true)")
	}
	var darkWebRepo *repository.DarkWebRepository
	if db != nil {
		darkWebRepo = repository.NewDarkWebRepository(db.Pool())
	}
	darkWebMonitor := services.NewDarkWebMonitor(hibpClient, leakCheckClient, intelXClient, darkWebRepo, redisCache, log)
	log.Info().Msg("dark web monitor initialized")

	// Initialize app security analyzer
	appAnalyzer := services.NewAppAnalyzer(repos, redisCache, log)
	if db != nil {
		appAnalyzer.SetAppSecurityRepository(repository.NewAppSecurityRepository(db.Pool()))
	}
	log.Info().Msg("app security analyzer initialized")

	// Initialize network security service
	networkSecurity := services.NewNetworkSecurityService(repos, redisCache, log)
	log.Info().Msg("network security service initialized")

	// Initialize YARA scanning service
	yaraService := services.NewYARAService(cfg.Detection.YARA.RulesDir, redisCache, log)
	log.Info().Int("rules_loaded", len(yaraService.GetRules(nil))).Msg("YARA service initialized")

	// Initialize correlation engine
	correlationEngine := services.NewCorrelationEngine(repos, redisCache, log)
	log.Info().Msg("correlation engine initialized")

	// Initialize MITRE ATT&CK service
	mitreService := services.NewMITREService(cfg.MITRE.DataDir, redisCache, log)
	log.Info().
		Int("tactics", mitreService.GetStats().TotalTactics).
		Int("techniques", mitreService.GetStats().TotalTechniques).
		Msg("MITRE ATT&CK service initialized")

	// Initialize ML service
	mlConfig := services.DefaultMLServiceConfig()
	mlService := services.NewMLService(mlConfig, repos, redisCache, log)
	log.Info().
		Bool("auto_train", mlConfig.AutoTrain).
		Dur("train_interval", mlConfig.TrainInterval).
		Int("min_training_size", mlConfig.MinTrainingSize).
		Msg("ML service initialized")

	// Start ML auto-training loop: waits for enough indicators, runs an
	// initial training pass, then re-trains on a fixed interval.
	if mlConfig.AutoTrain {
		if repos != nil {
			go runMLAutoTrain(ctx, mlService, mlConfig, repos, log)
		} else {
			log.Warn().Msg("ML auto-training disabled: no database connection available")
		}
	}

	// Initialize privacy protection service
	privacyService := services.NewPrivacyService(redisCache, log)
	log.Info().Msg("privacy protection service initialized")

	// Initialize device security service (anti-theft, SIM monitoring, OS vulnerabilities)
	deviceSecurityService := services.NewDeviceSecurityService(deviceSecurityRepo, redisCache, log)
	log.Info().Msg("device security service initialized")

	// Initialize QR security service (quishing protection)
	qrSecurityService := services.NewQRSecurityService(urlService, redisCache, log)
	log.Info().Msg("QR security service initialized")

	// Initialize STIX/TAXII service (enterprise threat intel standard)
	stixTAXIIService := services.NewSTIXTAXIIService(repos, redisCache, log)
	log.Info().Msg("STIX/TAXII 2.1 service initialized")

	// Initialize Enterprise service (MDM, Zero Trust, SIEM, Compliance)
	enterpriseService := services.NewEnterpriseService(repos, redisCache, log)
	enterpriseService.Start(ctx)
	defer enterpriseService.Stop()
	log.Info().Msg("enterprise services initialized (MDM, Zero Trust, SIEM, Compliance)")

	// Initialize OrbNet VPN integration service
	orbnetService := services.NewOrbNetService(repos, redisCache, log)
	log.Info().Msg("OrbNet VPN integration service initialized")

	// Initialize webhook notification service
	webhookService := services.NewWebhookService(redisCache, log, nil)
	log.Info().Msg("webhook notification service initialized")

	// Initialize automated playbook service
	playbookService := services.NewPlaybookService(webhookService, redisCache, log, nil)
	log.Info().Msg("automated playbook service initialized")

	// Initialize analytics and reporting service
	analyticsService := services.NewAnalyticsService(repos, redisCache, log)
	analyticsService.SetMITREService(mitreService)
	log.Info().Msg("analytics and reporting service initialized")

	// Initialize integration hub service (Slack, Teams, PagerDuty)
	integrationService := services.NewIntegrationService()
	defer integrationService.Stop()
	log.Info().Msg("integration hub service initialized (Slack, Teams, PagerDuty)")

	// Initialize AI-powered scam detection service
	scamConfig := buildScamDetectorConfig(cfg, log)
	scamDetector := ai.NewScamDetector(log, scamConfig)
	log.Info().
		Bool("llm", scamConfig.EnableLLM).
		Bool("pattern_db", scamConfig.EnablePatternDB).
		Bool("phone_reputation", scamConfig.EnablePhoneRep).
		Bool("vision", scamConfig.EnableVision).
		Bool("speech", scamConfig.EnableSpeech).
		Str("llm_provider", scamConfig.LLMProvider).
		Str("llm_model", scamConfig.LLMModel).
		Msg("AI scam detection service initialized")

	// Initialize forensics service (Pegasus/Spyware detection)
	forensicsService := forensics.NewServiceWithCache(redisCache, log)
	log.Info().Msg("forensics service initialized")

	// Initialize desktop security services (persistence, code signing,
	// network monitoring, browser extensions, VirusTotal lookups)
	persistenceScanner := desktop_security.NewPersistenceScanner(redisCache, log)
	codeVerifier := desktop_security.NewCodeSigningVerifier(log)
	networkMonitor := desktop_security.NewNetworkMonitor(redisCache, log)
	if repos != nil {
		if err := networkMonitor.SetStore(ctx, repository.NewNetworkSecurityRepositoryFromRepos(repos)); err != nil {
			log.Warn().Err(err).Msg("failed to load persisted firewall state")
		}
	}
	browserScanner := desktop_security.NewBrowserExtensionScanner(log)
	var vtClient *desktop_security.VirusTotalClient
	if vtKey := cfg.Sources.VirusTotal.APIKey; vtKey != "" {
		vtClient = desktop_security.NewVirusTotalClient(vtKey, redisCache, log)
		log.Info().Msg("desktop security VirusTotal client initialized")
	} else {
		log.Warn().Msg("desktop security VirusTotal lookups disabled (no API key) - set ORBGUARD_VIRUSTOTAL_API_KEY to enable")
	}
	log.Info().Msg("desktop security services initialized (persistence, code signing, network monitor, browser extensions)")

	// Initialize Neo4j graph database (if enabled)
	var graphService *services.GraphService
	if cfg.Neo4j.Enabled {
		neo4jClient, err := graph.NewNeo4jClient(ctx, cfg.Neo4j, log)
		if err != nil {
			log.Warn().Err(err).Msg("failed to connect to Neo4j, graph features disabled")
		} else {
			defer neo4jClient.Close(ctx)
			graphRepo := graph.NewGraphRepository(neo4jClient, log)
			graphService = services.NewGraphService(graphRepo, repos, redisCache, log)
			log.Info().Str("uri", cfg.Neo4j.URI).Msg("Neo4j graph database initialized")
		}
	}

	// Initialize digital footprint scanner
	footprintScanner := digital_footprint.NewScanner(redisCache, log, digital_footprint.DefaultScannerConfig())
	if repos != nil {
		footprintScanner.SetRemovalStore(repository.NewFootprintRepositoryFromRepos(repos))
	}
	log.Info().Msg("digital footprint scanner initialized")

	// Initialize handlers
	deps := handlers.Dependencies{
		Aggregator:            aggregator,
		Normalizer:            normalizer,
		Deduplicator:          deduplicator,
		Scorer:                scorer,
		Scheduler:             scheduler,
		Cache:                 redisCache,
		Logger:                log,
		Repos:                 repos,
		JWTSecret:             cfg.JWT.Secret,
		EventBus:              eventBus,
		WSHub:                 wsHub,
		URLService:            urlService,
		DarkWebMonitor:        darkWebMonitor,
		AppAnalyzer:           appAnalyzer,
		NetworkSecurity:       networkSecurity,
		GraphService:          graphService,
		YARAService:           yaraService,
		CorrelationEngine:     correlationEngine,
		MITREService:          mitreService,
		MLService:             mlService,
		PrivacyService:        privacyService,
		DeviceSecurityService: deviceSecurityService,
		QRSecurityService:     qrSecurityService,
		STIXTAXIIService:      stixTAXIIService,
		EnterpriseService:     enterpriseService,
		OrbNetService:         orbnetService,
		WebhookService:        webhookService,
		PlaybookService:       playbookService,
		AnalyticsService:      analyticsService,
		IntegrationService:    integrationService,
		ScamDetector:          scamDetector,
		ForensicsService:      forensicsService,
		PersistenceScanner:    persistenceScanner,
		CodeVerifier:          codeVerifier,
		NetworkMonitor:        networkMonitor,
		BrowserScanner:        browserScanner,
		VTClient:              vtClient,
		FootprintScanner:      footprintScanner,
		OSVBaseURL:            cfg.Detection.SupplyChain.OSVAPURL,
	}
	h := handlers.NewHandlers(deps)
	if repos != nil {
		h.NetworkSecurity.SetRepository(repository.NewNetworkSecurityRepositoryFromRepos(repos))
		h.NetworkSecurity.SetRogueAPRepository(repository.NewRogueAPRepositoryFromRepos(repos))
	}

	// Create router
	router := api.NewRouter(*cfg, h, redisCache, log)
	httpHandler := router.Setup()

	// Start HTTP server
	httpServer := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.HTTPPort),
		Handler:      httpHandler,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
		IdleTimeout:  cfg.Server.IdleTimeout,
	}

	go func() {
		log.Info().
			Str("addr", httpServer.Addr).
			Msg("starting HTTP server")
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal().Err(err).Msg("HTTP server failed")
		}
	}()

	// Start gRPC server
	grpcListener, err := net.Listen("tcp", fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.GRPCPort))
	if err != nil {
		log.Fatal().Err(err).Msg("failed to create gRPC listener")
	}

	grpcServer := grpc.NewServer()
	threatIntelServer := grpcserver.NewServer(aggregator, repos, redisCache, eventBus, log)
	threatIntelServer.Register(grpcServer)
	// NOTE: Register currently delegates to a placeholder (no generated
	// protobuf bindings exist yet), so ThreatIntelligenceService methods are
	// not reachable over gRPC. The health service reports it NOT_SERVING
	// until real protoc-generated registration lands.
	log.Warn().Msg("gRPC ThreatIntelligenceService registration is a placeholder - RPC methods not reachable until protobuf bindings are generated; only the gRPC health service is functional")

	// Register gRPC health check service
	grpcserver.RegisterHealthServer(grpcServer, db, redisCache)

	go func() {
		log.Info().
			Str("addr", grpcListener.Addr().String()).
			Msg("starting gRPC server")
		if err := grpcServer.Serve(grpcListener); err != nil {
			log.Fatal().Err(err).Msg("gRPC server failed")
		}
	}()

	// Start background services
	if cfg.Aggregation.Enabled {
		go func() {
			if err := aggregator.Run(ctx); err != nil && err != context.Canceled {
				log.Error().Err(err).Msg("aggregator stopped with error")
			}
		}()

		go func() {
			if err := scheduler.Start(ctx); err != nil && err != context.Canceled {
				log.Error().Err(err).Msg("scheduler stopped with error")
			}
		}()
	}

	// Wait for shutdown signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Info().Msg("shutting down...")

	// Cancel context to stop background services
	cancel()

	// Graceful shutdown with timeout
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), cfg.Server.ShutdownTimeout)
	defer shutdownCancel()

	// Stop gRPC server
	grpcServer.GracefulStop()

	// Stop HTTP server
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		log.Error().Err(err).Msg("HTTP server shutdown error")
	}

	// Stop scheduler
	scheduler.Stop()

	log.Info().Msg("shutdown complete")
}

// initInfrastructure initializes database and cache connections
func initInfrastructure(ctx context.Context, cfg *config.Config, log *logger.Logger) (*database.PostgresDB, *cache.RedisCache, error) {
	// Connect to PostgreSQL
	db, err := database.NewPostgres(ctx, cfg.Database, log)
	if err != nil {
		log.Warn().Err(err).Msg("failed to connect to PostgreSQL, continuing without database")
		// Don't fail, continue without database for development
	}

	// Connect to Redis
	redisCache, err := cache.NewRedis(ctx, cfg.Redis, log)
	if err != nil {
		return db, nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	return db, redisCache, nil
}

// buildScamDetectorConfig translates the application config into the AI scam
// detector configuration, enabling LLM-backed capabilities only when their
// API keys are present so the service degrades gracefully (never fakes
// results) without external credentials.
func buildScamDetectorConfig(cfg *config.Config, log *logger.Logger) ai.ScamDetectorConfig {
	sc := cfg.ScamDetector

	hasClaude := sc.ClaudeAPIKey != ""
	hasOpenAI := sc.OpenAIAPIKey != ""
	hasDeepSeek := sc.DeepSeekAPIKey != ""
	hasAzure := sc.AzureOpenAIEndpoint != "" && sc.AzureOpenAIKey != "" && sc.AzureOpenAIDeployment != ""

	// providerReady reports whether the credentials required by a given LLM
	// provider are configured.
	providerReady := func(p string) bool {
		switch p {
		case "claude":
			return hasClaude
		case "openai":
			return hasOpenAI
		case "deepseek":
			return hasDeepSeek
		case "azure-openai":
			return hasAzure
		default:
			return false
		}
	}
	providerPriority := []string{"claude", "openai", "deepseek", "azure-openai"}

	provider := sc.LLMProvider
	if !providerReady(provider) {
		for _, p := range providerPriority {
			if providerReady(p) {
				if provider != "" {
					log.Warn().
						Str("configured_provider", provider).
						Str("selected_provider", p).
						Msg("scam detector: configured llm_provider has no credentials, switching to a provider with credentials")
				}
				provider = p
				break
			}
		}
	}
	if provider == "" {
		provider = "claude"
	}

	enableLLM := sc.EnableLLM && providerReady(provider)
	if sc.EnableLLM && !enableLLM {
		log.Warn().Msg("scam detector LLM analysis disabled: no LLM credentials configured (set ORBGUARD_CLAUDE_API_KEY, ORBGUARD_OPENAI_API_KEY, ORBGUARD_DEEPSEEK_API_KEY, or ORBGUARD_AZURE_OPENAI_ENDPOINT + ORBGUARD_AZURE_OPENAI_KEY + ORBGUARD_AZURE_OPENAI_DEPLOYMENT)")
	}

	// Effective model used for the selected provider (deployment implies the
	// model on Azure).
	model := sc.LLMModel
	if model == "" {
		if provider == "azure-openai" {
			model = sc.AzureOpenAIDeployment
		} else {
			model = ai.DefaultModelForProvider(provider)
		}
	}

	enableVision := sc.EnableVision && enableLLM && provider != "deepseek"
	if sc.EnableVision && !enableLLM {
		log.Warn().Msg("scam detector vision analysis disabled: requires an LLM API key")
	} else if sc.EnableVision && provider == "deepseek" {
		log.Warn().Msg("scam detector vision analysis disabled: deepseek chat models do not support image input")
	}

	enableSpeech := sc.EnableSpeech && hasOpenAI
	if sc.EnableSpeech && !hasOpenAI {
		log.Warn().Msg("scam detector speech analysis disabled: requires an OpenAI API key (set ORBGUARD_OPENAI_API_KEY)")
	}

	return ai.ScamDetectorConfig{
		ClaudeAPIKey:          sc.ClaudeAPIKey,
		OpenAIAPIKey:          sc.OpenAIAPIKey,
		DeepSeekAPIKey:        sc.DeepSeekAPIKey,
		LLMProvider:           provider,
		LLMBaseURL:            sc.LLMBaseURL,
		LLMModel:              model,
		AzureOpenAIEndpoint:   sc.AzureOpenAIEndpoint,
		AzureOpenAIKey:        sc.AzureOpenAIKey,
		AzureOpenAIDeployment: sc.AzureOpenAIDeployment,
		AzureOpenAIAPIVersion: sc.AzureOpenAIAPIVersion,
		EnableLLM:             enableLLM,
		EnablePatternDB:       sc.EnablePatternDB,
		EnablePhoneRep:        sc.EnablePhoneRep,
		EnableVision:          enableVision,
		EnableSpeech:          enableSpeech,
		ScamThreshold:         sc.ScamThreshold,
		SuspiciousThresh:      sc.SuspiciousThresh,
	}
}

// runMLAutoTrain waits until the indicator store holds at least
// minTrainingSize records, performs an initial training pass, then re-trains
// every TrainInterval. It exits when the application context is cancelled.
// Trained model state is in-memory only; models are rebuilt after restart.
func runMLAutoTrain(
	ctx context.Context,
	mlService *services.MLService,
	mlConfig services.MLServiceConfig,
	repos *repository.Repositories,
	baseLog *logger.Logger,
) {
	log := baseLog.WithComponent("ml-autotrain")
	const pollInterval = 5 * time.Minute

	// Wait for enough training data before the first run.
	for {
		_, total, err := repos.Indicators.List(ctx, repository.IndicatorFilter{Limit: 1})
		if err != nil {
			log.Warn().Err(err).Msg("failed to count indicators for ML training, will retry")
		} else if total >= int64(mlConfig.MinTrainingSize) {
			log.Info().
				Int64("indicators", total).
				Int("min_required", mlConfig.MinTrainingSize).
				Msg("sufficient training data available, starting initial ML training")
			break
		} else {
			log.Debug().
				Int64("indicators", total).
				Int("min_required", mlConfig.MinTrainingSize).
				Msg("waiting for ML training data")
		}

		select {
		case <-ctx.Done():
			return
		case <-time.After(pollInterval):
		}
	}

	train := func() {
		start := time.Now()
		result, err := mlService.Train(ctx)
		switch {
		case err != nil:
			log.Error().Err(err).Dur("elapsed", time.Since(start)).Msg("ML training failed")
		case result == nil:
			log.Error().Dur("elapsed", time.Since(start)).Msg("ML training returned no result")
		case !result.Success:
			log.Warn().Str("reason", result.Error).Dur("elapsed", time.Since(start)).Msg("ML training did not complete")
		default:
			log.Info().
				Int("training_size", result.TrainingSize).
				Dur("training_time", result.TrainingTime).
				Interface("metrics", result.Metrics).
				Msg("ML training completed")
		}
	}

	train()

	ticker := time.NewTicker(mlConfig.TrainInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			train()
		}
	}
}

// registerConnectors registers all available source connectors
func registerConnectors(registry *sources.Registry, log *logger.Logger) {
	// Abuse.ch connectors
	if err := registry.Register(abusech.NewURLhausConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register URLhaus connector")
	}
	if err := registry.Register(abusech.NewThreatFoxConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register ThreatFox connector")
	}
	if err := registry.Register(abusech.NewMalwareBazaarConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register MalwareBazaar connector")
	}
	if err := registry.Register(abusech.NewFeodoTrackerConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register FeodoTracker connector")
	}
	// SSLBlacklist disabled - feed was deprecated by abuse.ch on 2025-01-03
	// if err := registry.Register(abusech.NewSSLBlacklistConnector(log)); err != nil {
	// 	log.Warn().Err(err).Msg("failed to register SSLBlacklist connector")
	// }

	// IP Reputation connectors
	if err := registry.Register(ip.NewAbuseIPDBConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register AbuseIPDB connector")
	}
	// GreyNoise: Auto-detects API tier - Enterprise enables bulk GNQL, Community enables single IP lookups
	if err := registry.Register(ip.NewGreyNoiseConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register GreyNoise connector")
	}

	// Phishing connectors
	if err := registry.Register(phishing.NewOpenPhishConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register OpenPhish connector")
	}
	if err := registry.Register(phishing.NewSafeBrowsingConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register Google Safe Browsing connector")
	}

	// Government connectors
	if err := registry.Register(government.NewCISAKEVConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register CISA KEV connector")
	}

	// Mobile/Spyware connectors (HIGH PRIORITY)
	if err := registry.Register(mobile.NewCitizenLabConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register CitizenLab connector")
	}
	if err := registry.Register(mobile.NewAmnestyMVTConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register AmnestyMVT connector")
	}

	// Premium connectors (require API keys)
	if err := registry.Register(premium.NewVirusTotalConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register VirusTotal connector")
	}
	if err := registry.Register(premium.NewAlienVaultOTXConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register AlienVault OTX connector")
	}
	if err := registry.Register(premium.NewKoodousConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register Koodous connector")
	}
	if err := registry.Register(premium.NewShodanConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register Shodan connector")
	}

	// Blocklist connectors
	if err := registry.Register(blocklists.NewSpamhausConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register Spamhaus connector")
	}

	// Analysis connectors
	if err := registry.Register(analysis.NewURLScanConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register URLScan connector")
	}
	if err := registry.Register(analysis.NewHybridAnalysisConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register HybridAnalysis connector")
	}

	// MISP feed connector
	if err := registry.Register(misp.NewMISPFeedsConnector(log)); err != nil {
		log.Warn().Err(err).Msg("failed to register MISP feeds connector")
	}

	log.Info().
		Int("total", registry.Count()).
		Int("enabled", registry.CountEnabled()).
		Msg("registered source connectors")
}
