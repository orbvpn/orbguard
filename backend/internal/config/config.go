package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Config holds all configuration for the application
type Config struct {
	App          AppConfig          `mapstructure:"app"`
	Server       ServerConfig       `mapstructure:"server"`
	Database     DatabaseConfig     `mapstructure:"database"`
	Redis        RedisConfig        `mapstructure:"redis"`
	Neo4j        Neo4jConfig        `mapstructure:"neo4j"`
	NATS         NATSConfig         `mapstructure:"nats"`
	JWT          JWTConfig          `mapstructure:"jwt"`
	CORS         CORSConfig         `mapstructure:"cors"`
	RateLimit    RateLimitConfig    `mapstructure:"ratelimit"`
	Logger       LoggerConfig       `mapstructure:"logger"`
	Aggregation  AggregationConfig  `mapstructure:"aggregation"`
	Sources      SourcesConfig      `mapstructure:"sources"`
	Scoring      ScoringConfig      `mapstructure:"scoring"`
	Detection    DetectionConfig    `mapstructure:"detection"`
	MITRE        MITREConfig        `mapstructure:"mitre"`
	STIX         STIXConfig         `mapstructure:"stix"`
	ML           MLConfig           `mapstructure:"ml"`
	HIBP         HIBPConfig         `mapstructure:"hibp"`
	LeakCheck    LeakCheckConfig    `mapstructure:"leakcheck"`
	IntelX       IntelXConfig       `mapstructure:"intelx"`
	SafeBrowsing SafeBrowsingConfig `mapstructure:"safe_browsing"`
	ScamDetector ScamDetectorConfig `mapstructure:"scam_detector"`
	DNSCanary    DNSCanaryConfig    `mapstructure:"dns_canary"`
	Push         PushConfig         `mapstructure:"push"`
}

// PushConfig holds Firebase Cloud Messaging (FCM HTTP v1) configuration for
// real-time anti-theft command delivery. When Enabled is false, or either
// FCMProjectID or FCMServiceAccountJSON is empty, the push service runs as an
// explicit no-op (commands are still delivered by device polling).
type PushConfig struct {
	Enabled bool `mapstructure:"enabled"`
	// FCMProjectID is the Firebase/GCP project id used in the FCM v1 send URL.
	FCMProjectID string `mapstructure:"fcm_project_id"`
	// FCMServiceAccountJSON is the service-account credential: either the raw
	// JSON content or a path to a file containing it. Both forms are accepted.
	FCMServiceAccountJSON string `mapstructure:"fcm_service_account_json"`
}

// DNSCanaryConfig holds the DNS leak-check canary settings. Zone is the
// controlled, NS-delegated domain served by cmd/dnscanary (e.g.
// "dnscheck.example.com"). When empty, the API reports the DNS leak check as
// explicitly unavailable instead of fabricating a result.
type DNSCanaryConfig struct {
	Zone string `mapstructure:"zone"`
}

// HIBPConfig holds Have I Been Pwned API configuration
type HIBPConfig struct {
	APIKey  string `mapstructure:"api_key"`
	Enabled bool   `mapstructure:"enabled"`
}

// LeakCheckConfig holds LeakCheck breach-search API configuration
type LeakCheckConfig struct {
	APIKey  string `mapstructure:"api_key"`
	Enabled bool   `mapstructure:"enabled"`
}

// IntelXConfig holds Intelligence X dark-web search API configuration
type IntelXConfig struct {
	APIKey  string `mapstructure:"api_key"`
	BaseURL string `mapstructure:"base_url"`
	Enabled bool   `mapstructure:"enabled"`
}

// SafeBrowsingConfig holds the Google Safe Browsing key used by the URL
// reputation service. When APIKey is empty it falls back to
// sources.google_safebrowsing.api_key (see EffectiveSafeBrowsingKey).
type SafeBrowsingConfig struct {
	APIKey string `mapstructure:"api_key"`
}

// EffectiveSafeBrowsingKey returns the Safe Browsing API key for URL
// reputation lookups, falling back to the source connector key so a single
// key can drive both the feed connector and live lookups.
func (c *Config) EffectiveSafeBrowsingKey() string {
	if c.SafeBrowsing.APIKey != "" {
		return c.SafeBrowsing.APIKey
	}
	return c.Sources.GoogleSafeBrowsing.APIKey
}

// ScamDetectorConfig holds AI-powered scam detection configuration.
// LLM, vision and speech capabilities are only activated at startup when the
// corresponding API keys are configured; pattern and phone reputation
// databases are local and have no external dependency.
type ScamDetectorConfig struct {
	EnableLLM        bool    `mapstructure:"enable_llm"`
	EnablePatternDB  bool    `mapstructure:"enable_pattern_db"`
	EnablePhoneRep   bool    `mapstructure:"enable_phone_rep"`
	EnableVision     bool    `mapstructure:"enable_vision"`
	EnableSpeech     bool    `mapstructure:"enable_speech"`
	LLMProvider      string  `mapstructure:"llm_provider"`
	LLMBaseURL       string  `mapstructure:"llm_base_url"`
	LLMModel         string  `mapstructure:"llm_model"`
	// LLMReasoningEffort is sent as reasoning_effort to reasoning-capable
	// OpenAI/Azure OpenAI deployments (GPT-5.x, o-series); classification at
	// "low" effort is fast and high quality. Empty omits the parameter.
	LLMReasoningEffort string `mapstructure:"llm_reasoning_effort"`
	ClaudeAPIKey     string  `mapstructure:"claude_api_key"`
	OpenAIAPIKey     string  `mapstructure:"openai_api_key"`
	DeepSeekAPIKey   string  `mapstructure:"deepseek_api_key"`
	ScamThreshold    float64 `mapstructure:"scam_threshold"`
	SuspiciousThresh float64 `mapstructure:"suspicious_threshold"`

	// Azure OpenAI (used only when llm_provider == "azure-openai")
	AzureOpenAIEndpoint   string `mapstructure:"azure_openai_endpoint"`
	AzureOpenAIKey        string `mapstructure:"azure_openai_key"`
	AzureOpenAIDeployment string `mapstructure:"azure_openai_deployment"`
	AzureOpenAIAPIVersion string `mapstructure:"azure_openai_api_version"`
	// AzureOpenAITranscribeDeployment enables Azure OpenAI audio transcription
	// (e.g. gpt-4o-transcribe) for speech analysis; works together with
	// azure_openai_endpoint and azure_openai_key.
	AzureOpenAITranscribeDeployment string `mapstructure:"azure_openai_transcribe_deployment"`
}

type AppConfig struct {
	Name        string `mapstructure:"name"`
	Environment string `mapstructure:"environment"`
	Version     string `mapstructure:"version"`
	Debug       bool   `mapstructure:"debug"`
}

type ServerConfig struct {
	Host            string        `mapstructure:"host"`
	HTTPPort        int           `mapstructure:"http_port"`
	GRPCPort        int           `mapstructure:"grpc_port"`
	ReadTimeout     time.Duration `mapstructure:"read_timeout"`
	WriteTimeout    time.Duration `mapstructure:"write_timeout"`
	IdleTimeout     time.Duration `mapstructure:"idle_timeout"`
	ShutdownTimeout time.Duration `mapstructure:"shutdown_timeout"`
}

type DatabaseConfig struct {
	Host            string        `mapstructure:"host"`
	Port            int           `mapstructure:"port"`
	User            string        `mapstructure:"user"`
	Password        string        `mapstructure:"password"`
	DBName          string        `mapstructure:"dbname"`
	SSLMode         string        `mapstructure:"sslmode"`
	MaxOpenConns    int           `mapstructure:"max_open_conns"`
	MaxIdleConns    int           `mapstructure:"max_idle_conns"`
	ConnMaxLifetime time.Duration `mapstructure:"conn_max_lifetime"`
	Schema          string        `mapstructure:"schema"`
}

func (c DatabaseConfig) DSN() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%d/%s?sslmode=%s&search_path=%s",
		c.User, c.Password, c.Host, c.Port, c.DBName, c.SSLMode, c.Schema,
	)
}

type RedisConfig struct {
	Host      string `mapstructure:"host"`
	Port      int    `mapstructure:"port"`
	Password  string `mapstructure:"password"`
	DB        int    `mapstructure:"db"`
	KeyPrefix string `mapstructure:"key_prefix"`
	TLS       bool   `mapstructure:"tls"`
}

func (c RedisConfig) Addr() string {
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

type Neo4jConfig struct {
	Enabled            bool   `mapstructure:"enabled"`
	URI                string `mapstructure:"uri"`
	Username           string `mapstructure:"username"`
	Password           string `mapstructure:"password"`
	Database           string `mapstructure:"database"`
	MaxConnections     int    `mapstructure:"max_connections"`
	MaxLifetimeMinutes int    `mapstructure:"max_lifetime_minutes"`
}

type NATSConfig struct {
	Enabled    bool               `mapstructure:"enabled"`
	URL        string             `mapstructure:"url"`
	StreamName string             `mapstructure:"stream_name"`
	Subjects   NATSSubjectsConfig `mapstructure:"subjects"`
}

type NATSSubjectsConfig struct {
	NewThreat        string `mapstructure:"new_threat"`
	UpdatedThreat    string `mapstructure:"updated_threat"`
	CampaignDetected string `mapstructure:"campaign_detected"`
}

type JWTConfig struct {
	Secret     string        `mapstructure:"secret"`
	Expiration time.Duration `mapstructure:"expiration"`
	Issuer     string        `mapstructure:"issuer"`
}

type CORSConfig struct {
	AllowedOrigins   []string `mapstructure:"allowed_origins"`
	AllowedMethods   []string `mapstructure:"allowed_methods"`
	AllowedHeaders   []string `mapstructure:"allowed_headers"`
	AllowCredentials bool     `mapstructure:"allow_credentials"`
	MaxAge           int      `mapstructure:"max_age"`
}

type RateLimitConfig struct {
	Enabled           bool `mapstructure:"enabled"`
	RequestsPerMinute int  `mapstructure:"requests_per_minute"`
	RequestsPerHour   int  `mapstructure:"requests_per_hour"`
}

type LoggerConfig struct {
	Level      string `mapstructure:"level"`
	Format     string `mapstructure:"format"`
	TimeFormat string `mapstructure:"time_format"`
}

type AggregationConfig struct {
	Enabled        bool          `mapstructure:"enabled"`
	InitialDelay   time.Duration `mapstructure:"initial_delay"`
	WorkerPoolSize int           `mapstructure:"worker_pool_size"`
}

type SourcesConfig struct {
	URLhaus            SourceConfig `mapstructure:"urlhaus"`
	ThreatFox          SourceConfig `mapstructure:"threatfox"`
	MalwareBazaar      SourceConfig `mapstructure:"malwarebazaar"`
	FeodoTracker       SourceConfig `mapstructure:"feodotracker"`
	SSLBlacklist       SourceConfig `mapstructure:"sslblacklist"`
	OpenPhish          SourceConfig `mapstructure:"openphish"`
	PhishTank          SourceConfig `mapstructure:"phishtank"`
	GoogleSafeBrowsing SourceConfig `mapstructure:"google_safebrowsing"`
	AbuseIPDB          SourceConfig `mapstructure:"abuseipdb"`
	GreyNoise          SourceConfig `mapstructure:"greynoise"`
	CitizenLab         SourceConfig `mapstructure:"citizenlab"`
	AmnestyMVT         SourceConfig `mapstructure:"amnesty_mvt"`
	Koodous            SourceConfig `mapstructure:"koodous"`
	AlienVaultOTX      SourceConfig `mapstructure:"alienvault_otx"`
	VirusTotal         SourceConfig `mapstructure:"virustotal"`
	CISAKEV            SourceConfig `mapstructure:"cisa_kev"`
	// Phase 23 - Additional Threat Sources
	Spamhaus       SourceConfig `mapstructure:"spamhaus"`
	URLScan        SourceConfig `mapstructure:"urlscan"`
	HybridAnalysis SourceConfig `mapstructure:"hybrid_analysis"`
	MISPFeeds      SourceConfig `mapstructure:"misp_feeds"`
	Shodan         SourceConfig `mapstructure:"shodan"`
}

type SourceConfig struct {
	Enabled        bool          `mapstructure:"enabled"`
	UpdateInterval time.Duration `mapstructure:"update_interval"`
	APIURL         string        `mapstructure:"api_url"`
	FeedURL        string        `mapstructure:"feed_url"`
	APIKey         string        `mapstructure:"api_key"`
	GithubURLs     []string      `mapstructure:"github_urls"`
}

type ScoringConfig struct {
	Weights           ScoringWeights     `mapstructure:"weights"`
	Bonuses           ScoringBonuses     `mapstructure:"bonuses"`
	SourceReliability map[string]float64 `mapstructure:"source_reliability"`
}

type ScoringWeights struct {
	SourceReliability float64 `mapstructure:"source_reliability"`
	SourceCount       float64 `mapstructure:"source_count"`
	Recency           float64 `mapstructure:"recency"`
	ReportCount       float64 `mapstructure:"report_count"`
	SourceConfidence  float64 `mapstructure:"source_confidence"`
}

type ScoringBonuses struct {
	Pegasus     float64 `mapstructure:"pegasus"`
	CVELinked   float64 `mapstructure:"cve_linked"`
	KnownFamily float64 `mapstructure:"known_family"`
}

type DetectionConfig struct {
	YARA        YARAConfig        `mapstructure:"yara"`
	Behavioral  BehavioralConfig  `mapstructure:"behavioral"`
	SupplyChain SupplyChainConfig `mapstructure:"supply_chain"`
}

type YARAConfig struct {
	Enabled  bool   `mapstructure:"enabled"`
	RulesDir string `mapstructure:"rules_dir"`
}

type BehavioralConfig struct {
	Enabled          bool          `mapstructure:"enabled"`
	BaselineDuration time.Duration `mapstructure:"baseline_duration"`
}

type SupplyChainConfig struct {
	Enabled  bool   `mapstructure:"enabled"`
	OSVAPURL string `mapstructure:"osv_api_url"`
}

type MITREConfig struct {
	DataDir              string `mapstructure:"data_dir"`
	MobileAttackFile     string `mapstructure:"mobile_attack_file"`
	EnterpriseAttackFile string `mapstructure:"enterprise_attack_file"`
}

type STIXConfig struct {
	Enabled     bool              `mapstructure:"enabled"`
	TAXIIServer TAXIIServerConfig `mapstructure:"taxii_server"`
}

type TAXIIServerConfig struct {
	Enabled bool `mapstructure:"enabled"`
	Port    int  `mapstructure:"port"`
}

type MLConfig struct {
	AnomalyDetection AnomalyDetectionConfig `mapstructure:"anomaly_detection"`
	Clustering       ClusteringConfig       `mapstructure:"clustering"`
}

type AnomalyDetectionConfig struct {
	Enabled    bool    `mapstructure:"enabled"`
	NumTrees   int     `mapstructure:"num_trees"`
	SampleSize int     `mapstructure:"sample_size"`
	Threshold  float64 `mapstructure:"threshold"`
}

type ClusteringConfig struct {
	Enabled    bool    `mapstructure:"enabled"`
	MinSamples int     `mapstructure:"min_samples"`
	Eps        float64 `mapstructure:"eps"`
}

// Load reads configuration from file and environment variables
func Load(configPath string) (*Config, error) {
	v := viper.New()

	// Set config file
	if configPath != "" {
		v.SetConfigFile(configPath)
	} else {
		v.SetConfigName("config")
		v.SetConfigType("yaml")
		v.AddConfigPath(".")
		v.AddConfigPath("./config")
		v.AddConfigPath("/etc/orbguard-lab")
	}

	// Environment variables
	v.SetEnvPrefix("ORBGUARD")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	// Bind nested env vars explicitly (viper doesn't auto-bind nested struct fields)
	v.BindEnv("redis.tls", "ORBGUARD_REDIS_TLS")
	v.BindEnv("redis.host", "ORBGUARD_REDIS_HOST")
	v.BindEnv("redis.port", "ORBGUARD_REDIS_PORT")
	v.BindEnv("redis.password", "ORBGUARD_REDIS_PASSWORD")
	v.BindEnv("database.host", "ORBGUARD_DATABASE_HOST")
	v.BindEnv("database.port", "ORBGUARD_DATABASE_PORT")
	v.BindEnv("database.user", "ORBGUARD_DATABASE_USER")
	v.BindEnv("database.password", "ORBGUARD_DATABASE_PASSWORD")
	v.BindEnv("database.dbname", "ORBGUARD_DATABASE_DBNAME")
	v.BindEnv("database.sslmode", "ORBGUARD_DATABASE_SSLMODE")
	v.BindEnv("neo4j.enabled", "ORBGUARD_NEO4J_ENABLED")
	v.BindEnv("neo4j.uri", "ORBGUARD_NEO4J_URI")
	v.BindEnv("neo4j.username", "ORBGUARD_NEO4J_USERNAME")
	v.BindEnv("neo4j.password", "ORBGUARD_NEO4J_PASSWORD")
	v.BindEnv("neo4j.database", "ORBGUARD_NEO4J_DATABASE")
	v.BindEnv("nats.enabled", "ORBGUARD_NATS_ENABLED")
	v.BindEnv("app.environment", "ORBGUARD_APP_ENVIRONMENT")

	// Dark web / breach intelligence API keys
	v.BindEnv("hibp.api_key", "ORBGUARD_HIBP_API_KEY")
	v.BindEnv("hibp.enabled", "ORBGUARD_HIBP_ENABLED")
	v.BindEnv("leakcheck.api_key", "ORBGUARD_LEAKCHECK_API_KEY")
	v.BindEnv("leakcheck.enabled", "ORBGUARD_LEAKCHECK_ENABLED")
	v.BindEnv("intelx.api_key", "ORBGUARD_INTELX_API_KEY")
	v.BindEnv("intelx.base_url", "ORBGUARD_INTELX_BASE_URL")
	v.BindEnv("intelx.enabled", "ORBGUARD_INTELX_ENABLED")

	// URL reputation Safe Browsing key (falls back to sources.google_safebrowsing.api_key)
	v.BindEnv("safe_browsing.api_key", "ORBGUARD_SAFE_BROWSING_API_KEY")

	// AI scam detector
	v.BindEnv("scam_detector.enable_llm", "ORBGUARD_SCAM_DETECTOR_ENABLE_LLM")
	v.BindEnv("scam_detector.enable_pattern_db", "ORBGUARD_SCAM_DETECTOR_ENABLE_PATTERN_DB")
	v.BindEnv("scam_detector.enable_phone_rep", "ORBGUARD_SCAM_DETECTOR_ENABLE_PHONE_REP")
	v.BindEnv("scam_detector.enable_vision", "ORBGUARD_SCAM_DETECTOR_ENABLE_VISION")
	v.BindEnv("scam_detector.enable_speech", "ORBGUARD_SCAM_DETECTOR_ENABLE_SPEECH")
	v.BindEnv("scam_detector.llm_provider", "ORBGUARD_SCAM_DETECTOR_LLM_PROVIDER")
	v.BindEnv("scam_detector.llm_base_url", "ORBGUARD_SCAM_DETECTOR_LLM_BASE_URL")
	v.BindEnv("scam_detector.llm_model", "ORBGUARD_SCAM_DETECTOR_LLM_MODEL")
	v.BindEnv("scam_detector.llm_reasoning_effort", "ORBGUARD_SCAM_DETECTOR_LLM_REASONING_EFFORT")
	v.BindEnv("scam_detector.claude_api_key", "ORBGUARD_CLAUDE_API_KEY")
	v.BindEnv("scam_detector.openai_api_key", "ORBGUARD_OPENAI_API_KEY")
	v.BindEnv("scam_detector.deepseek_api_key", "ORBGUARD_DEEPSEEK_API_KEY")
	v.BindEnv("scam_detector.azure_openai_endpoint", "ORBGUARD_AZURE_OPENAI_ENDPOINT")
	v.BindEnv("scam_detector.azure_openai_key", "ORBGUARD_AZURE_OPENAI_KEY")
	v.BindEnv("scam_detector.azure_openai_deployment", "ORBGUARD_AZURE_OPENAI_DEPLOYMENT")
	v.BindEnv("scam_detector.azure_openai_api_version", "ORBGUARD_AZURE_OPENAI_API_VERSION")
	v.BindEnv("scam_detector.azure_openai_transcribe_deployment", "ORBGUARD_AZURE_OPENAI_TRANSCRIBE_DEPLOYMENT")

	// DNS leak-check canary zone (served by cmd/dnscanary; empty = leak
	// check reported unavailable)
	v.BindEnv("dns_canary.zone", "ORBGUARD_DNS_CANARY_ZONE")

	// FCM push (real-time anti-theft command delivery). Empty project id /
	// service-account JSON keeps push as an explicit no-op (polling only).
	v.BindEnv("push.enabled", "ORBGUARD_PUSH_ENABLED")
	v.BindEnv("push.fcm_project_id", "ORBGUARD_FCM_PROJECT_ID")
	v.BindEnv("push.fcm_service_account_json", "ORBGUARD_FCM_SERVICE_ACCOUNT_JSON")

	// Defaults for sections that may be absent from older config files.
	// PatternDB and PhoneRep are local databases with no external dependency,
	// so they default to enabled. LLM/vision/speech default to enabled but
	// are gated at startup on the presence of their API keys.
	v.SetDefault("scam_detector.enable_pattern_db", true)
	v.SetDefault("scam_detector.enable_phone_rep", true)
	v.SetDefault("scam_detector.enable_llm", true)
	v.SetDefault("scam_detector.enable_vision", true)
	v.SetDefault("scam_detector.enable_speech", true)
	v.SetDefault("scam_detector.llm_provider", "claude")
	v.SetDefault("scam_detector.llm_reasoning_effort", "low")
	v.SetDefault("scam_detector.azure_openai_api_version", "2024-02-15-preview")
	v.SetDefault("scam_detector.scam_threshold", 0.7)
	v.SetDefault("scam_detector.suspicious_threshold", 0.4)
	v.SetDefault("hibp.enabled", true)
	v.SetDefault("leakcheck.enabled", true)
	v.SetDefault("intelx.enabled", true)
	v.SetDefault("intelx.base_url", "https://2.intelx.io")
	v.SetDefault("dns_canary.zone", "")

	// Push defaults: master switch on, but effective only when FCM credentials
	// are configured (gated at startup on project id + service-account JSON).
	v.SetDefault("push.enabled", true)
	v.SetDefault("push.fcm_project_id", "")
	v.SetDefault("push.fcm_service_account_json", "")

	// Source API keys
	v.BindEnv("sources.threatfox.api_key", "ORBGUARD_THREATFOX_API_KEY")
	v.BindEnv("sources.google_safebrowsing.api_key", "ORBGUARD_SAFEBROWSING_API_KEY")
	v.BindEnv("sources.abuseipdb.api_key", "ORBGUARD_ABUSEIPDB_API_KEY")
	v.BindEnv("sources.greynoise.api_key", "ORBGUARD_GREYNOISE_API_KEY")
	v.BindEnv("sources.virustotal.api_key", "ORBGUARD_VIRUSTOTAL_API_KEY")
	v.BindEnv("sources.alienvault_otx.api_key", "ORBGUARD_ALIENVAULT_OTX_API_KEY")
	v.BindEnv("sources.koodous.api_key", "ORBGUARD_KOODOUS_API_KEY")
	// Phase 23 - Additional source API keys
	v.BindEnv("sources.urlscan.api_key", "ORBGUARD_URLSCAN_API_KEY")
	v.BindEnv("sources.hybrid_analysis.api_key", "ORBGUARD_HYBRID_ANALYSIS_API_KEY")
	v.BindEnv("sources.shodan.api_key", "ORBGUARD_SHODAN_API_KEY")

	// Read config file
	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	// Unmarshal config
	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &cfg, nil
}

// LoadDefault loads configuration with default path
func LoadDefault() (*Config, error) {
	return Load("")
}
