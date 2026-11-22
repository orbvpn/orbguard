package ios

import (
	"archive/tar"
	"bufio"
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync/atomic"
	"time"

	"github.com/google/uuid"

	"orbguard-lab/internal/forensics/models"
	"orbguard-lab/internal/forensics/safezip"
	"orbguard-lab/pkg/logger"
)

// SysdiagnoseParser parses iOS sysdiagnose archives for forensic analysis
type SysdiagnoseParser struct {
	logger            *logger.Logger
	shutdownLogParser *ShutdownLogParser
	dataUsageParser   *DataUsageParser
}

// NewSysdiagnoseParser creates a new sysdiagnose parser
func NewSysdiagnoseParser(log *logger.Logger) *SysdiagnoseParser {
	return &SysdiagnoseParser{
		logger:            log.WithComponent("sysdiagnose-parser"),
		shutdownLogParser: NewShutdownLogParser(log),
		dataUsageParser:   NewDataUsageParser(log),
	}
}

// Key files within sysdiagnose that are forensically relevant
var sysdiagnoseFiles = map[string]string{
	"shutdown.log":                    "logs/shutdown/shutdown.log",
	"system.log":                      "system_logs.logarchive",
	"powerlogs":                       "logs/powerlogs",
	"mobileactivation":                "logs/MobileActivation",
	"mobile_container_manager":        "logs/MobileContainerManager",
	"wifi":                            "WiFi",
	"lockdownd":                       "logs/lockdownd",
	"datausage":                       "logs/Networking/netusage.sqlite",
	"network_usage":                   "logs/Networking",
	"crashes":                         "crashes_and_spins",
	"itunesstore":                     "logs/itunesstored",
	"accessibility_tcc":               "logs/Accessibility/TCC.db",
	"locationd":                       "logs/locationd",
	"springboard":                     "logs/SpringBoard",
	"aggregated":                      "logs/aggregated",
	"mobile_installation":             "logs/MobileInstallation",
	"appinstallation":                 "logs/AppInstallation",
}

// Suspicious patterns in sysdiagnose logs
var sysdiagnoseSuspiciousPatterns = []struct {
	FilePattern string
	Pattern     *regexp.Regexp
	Reason      string
	Score       float64
}{
	// Process injection/hooking
	{"system_logs", regexp.MustCompile(`(?i)dlopen.*private/var/`), "Dynamic library loading from suspicious path", 0.8},
	{"system_logs", regexp.MustCompile(`(?i)ptrace|process_inject`), "Process injection attempt", 0.9},

	// Pegasus/Predator specific
	{"*", regexp.MustCompile(`(?i)/private/var/db/[a-f0-9]{32,}`), "Suspicious path pattern (Pegasus)", 0.9},
	{"*", regexp.MustCompile(`(?i)/private/var/tmp/[a-f0-9]{32,}`), "Suspicious path pattern (Predator)", 0.9},
	// bh and pcsd count only as a whole process name: the last path component
	// (JSON may escape its slashes), name[pid], a process field, a crash report
	// process field, the last column of a process list, or a launch daemon
	// file name. Short names otherwise occur in binary data.
	{"*", regexp.MustCompile(`(?im)(?:\\?/[a-z0-9._-]+)+\\?/(?:bh|pcsd)(?:[\s)\]:,;"'<]|$)|\b(?:bh|pcsd)\[\d+\]|\bprocess(?:[ _]?name)?\s*[:=]\s*"?(?:bh|pcsd)(?:[\s\[\]():,"]|$)|"(?:procname|app_name|parentproc|responsibleproc)"\s*:\s*"(?:bh|pcsd)"|^[ \t]*(?:[a-z_][a-z0-9_-]*[ \t]+)?\d+[ \t]+(?:\S+[ \t]+)*(?:bh|pcsd)[ \t]*\r?$|\\?/launch(?:daemons|agents)\\?/[^\s"'<>]*\b(?:bh|pcsd)\b[^\s"'<>]*|roleaccount`), "Known spyware process name", 0.95},

	// Exploitation indicators
	{"crashes", regexp.MustCompile(`(?i)SIGABRT|SIGSEGV|EXC_BAD_ACCESS`), "Crash possibly indicating exploit", 0.5},
	{"crashes", regexp.MustCompile(`(?i)JavaScriptCore|WebKit.*crash`), "WebKit crash (potential exploit vector)", 0.7},
	{"crashes", regexp.MustCompile(`(?i)iMessage|imagent.*crash`), "iMessage crash (potential zero-click)", 0.8},

	// Persistence mechanisms
	{"springboard", regexp.MustCompile(`(?i)launchd.*suspicious|daemon.*unknown`), "Unknown daemon registered", 0.7},
	{"mobile_installation", regexp.MustCompile(`(?i)install.*failed.*signature`), "Failed signature check", 0.6},

	// Data access patterns
	{"locationd", regexp.MustCompile(`(?i)unauthorized.*location|location.*denied.*override`), "Location access anomaly", 0.6},
	{"accessibility_tcc", regexp.MustCompile(`(?i)kTCCService.*Microphone|kTCCService.*Camera`), "Sensitive permission granted", 0.4},

	// Network anomalies
	{"wifi", regexp.MustCompile(`(?i)captive.*portal.*bypass|ssl.*error.*ignore`), "Network security bypass", 0.7},
	{"network_usage", regexp.MustCompile(`(?i)high.*data.*unknown|exfiltration`), "Unusual network activity", 0.6},
}

// Parse analyzes a sysdiagnose archive and returns forensic results
func (p *SysdiagnoseParser) Parse(archivePath string) (*models.ForensicResult, error) {
	return p.ParseContext(context.Background(), archivePath)
}

// ParseContext is Parse that stops when ctx ends. What it did not reach then
// counts as not examined.
func (p *SysdiagnoseParser) ParseContext(ctx context.Context, archivePath string) (*models.ForensicResult, error) {
	result := models.NewForensicResult("", "ios", models.ForensicScanTypeSysdiagnose)

	p.logger.Info().Str("path", archivePath).Msg("analyzing sysdiagnose archive")

	timeline := models.NewTimeline()

	// Each entry is analysed once, as it is read, and its bytes are then
	// released, so memory follows the largest entry and not the archive.
	extraction := &sysdiagnoseExtraction{ctx: ctx, unread: make(map[string]bool)}
	extraction.visit = func(e sysdiagnoseEntry) bool {
		p.examineEntry(e, extraction, result, timeline)
		if len(result.Anomalies) >= maxSysdiagnoseFindings {
			extraction.stopReading(sysdiagnoseRestOfArchive)
			return false
		}
		return true
	}

	tempDir, err := p.extractArchive(archivePath, extraction)
	if err != nil {
		return nil, fmt.Errorf("failed to extract archive: %w", err)
	}
	defer os.RemoveAll(tempDir)

	// Detect coordinated suspicious activity patterns
	p.detectCoordinatedActivity(result, timeline)

	// Refused for capacity, so the artifact itself may be fine.
	if extraction.busy && !result.HasHighFinding() {
		return nil, models.ErrAnalysisBusy
	}

	notExamined := extraction.notExamined()
	if !extraction.stoppedEarly && !extraction.recognised && len(result.Anomalies) == 0 {
		return nil, models.ErrNothingExamined
	}

	// Never clean while something supplied went unexamined. Only a high or
	// critical finding may stand, and the result lists what was skipped.
	if len(notExamined) > 0 {
		if !result.HasHighFinding() {
			return nil, &models.PartlyExaminedError{NotExamined: notExamined}
		}
		result.RawData["not_examined"] = notExamined
	}

	timeline.Sort()
	result.Timeline = timeline.ToEvents()

	result.RawData["files_analyzed"] = extraction.entries
	result.RawData["archive_path"] = archivePath

	result.Complete()

	p.logger.Info().
		Int("anomalies", result.TotalAnomalies).
		Int("threats", len(result.DetectedThreats)).
		Float64("infection_likelihood", result.InfectionLikelihood).
		Msg("sysdiagnose analysis complete")

	return result, nil
}

// Limits on what one sysdiagnose may cost. The lowest memory limit in this
// repository's manifests is 512 MiB (backend/kubernetes.yaml).
const (
	// maxSysdiagnoseEntryBytes caps one entry, before it is read.
	maxSysdiagnoseEntryBytes = 50 * 1024 * 1024
	// maxSysdiagnoseTotalBytes caps the decompressed total of one archive. It
	// matches the bugreport limit and is about what fits the 60 s request limit.
	maxSysdiagnoseTotalBytes = 256 * 1024 * 1024
	// maxSysdiagnoseEntries caps the number of file entries in one archive.
	maxSysdiagnoseEntries = 20000
	// maxSysdiagnoseInFlightBytes caps entry bytes held at once across all
	// uploads. Go's heap can reach twice its live size, so this keeps the peak
	// near 256 MiB, under the 512 MiB limit.
	maxSysdiagnoseInFlightBytes = 128 * 1024 * 1024
	// maxSysdiagnoseFindings and maxRuleMatchesPerEntry bound the findings a
	// crafted file can create.
	maxSysdiagnoseFindings = 1000
	maxRuleMatchesPerEntry = 20
	// maxListedNotExamined caps the names echoed back in a response.
	maxListedNotExamined = 100

	// ruleScanChunk is how much one rule scans before the time budget is
	// checked. ruleScanOverlap keeps a match that crosses a chunk boundary.
	ruleScanChunk   = 256 * 1024
	ruleScanOverlap = 4 * 1024

	sysdiagnoseRestOfArchive = "rest of the archive: over the size, entry or findings limit"
	sysdiagnoseOutOfTime     = "rest of the archive: over the time limit"
)

var (
	errSysdiagnoseEntryTooLarge = errors.New("sysdiagnose entry exceeds the size cap")

	// sysdiagnoseInFlight counts entry bytes held right now, across uploads.
	sysdiagnoseInFlight atomic.Int64
)

// sysdiagnoseEntry is one file of an archive. Keys are the sysdiagnoseFiles
// artifacts its path belongs to; a path can belong to two.
type sysdiagnoseEntry struct {
	name    string
	keys    []string
	content []byte
}

// matchesRule reports whether a rule's file pattern applies to this entry.
func (e sysdiagnoseEntry) matchesRule(rule string) bool {
	if rule == "*" {
		return true
	}
	for _, key := range e.keys {
		if key == rule {
			return true
		}
	}
	return strings.Contains(filepath.Base(e.name), rule)
}

// kindLabel is what the kind checks for crash and network files read.
func (e sysdiagnoseEntry) kindLabel() string {
	return strings.ToLower(strings.Join(e.keys, " ") + " " + filepath.Base(e.name))
}

// sysdiagnoseExtraction tracks one archive as its entries are read.
type sysdiagnoseExtraction struct {
	ctx        context.Context
	visit      func(sysdiagnoseEntry) bool
	entries    int
	totalBytes int64
	// recognised is set once a known artifact or a shutdown log was read.
	recognised bool
	// busy is set when reading stopped for capacity shared with other uploads.
	busy bool
	// stoppedEarly is set when entries were left unread at a limit.
	stoppedEarly bool
	// unread holds entries that could not be examined.
	unread     map[string]bool
	unreadMore int
}

// expired reports whether the time budget or the request has ended.
func (x *sysdiagnoseExtraction) expired() bool {
	return x.ctx != nil && x.ctx.Err() != nil
}

// context is the context the analysis of one entry runs under.
func (x *sysdiagnoseExtraction) context() context.Context {
	if x.ctx == nil {
		return context.Background()
	}
	return x.ctx
}

// budgetReader stops decompression when the time budget ends.
type budgetReader struct {
	r io.Reader
	x *sysdiagnoseExtraction
}

func (b budgetReader) Read(p []byte) (int, error) {
	if b.x.expired() {
		return 0, b.x.ctx.Err()
	}
	return b.r.Read(p)
}

// skip records something supplied that was not examined.
func (x *sysdiagnoseExtraction) skip(name string) {
	if len(name) > 256 {
		name = name[:256]
	}
	if x.unread[name] {
		return
	}
	if len(x.unread) >= maxListedNotExamined {
		x.unreadMore++
		return
	}
	x.unread[name] = true
}

// stopReading records that the rest of the archive was left unread.
func (x *sysdiagnoseExtraction) stopReading(reason string) {
	x.stoppedEarly = true
	x.skip(reason)
}

// notExamined lists what was skipped, in a stable order.
func (x *sysdiagnoseExtraction) notExamined() []string {
	names := make([]string, 0, len(x.unread)+1)
	for name := range x.unread {
		names = append(names, name)
	}
	sort.Strings(names)
	if x.unreadMore > 0 {
		names = append(names, fmt.Sprintf("and %d more", x.unreadMore))
	}
	return names
}

// add reads one entry once, under every limit, and hands it to visit. It
// returns false when reading must stop.
func (x *sysdiagnoseExtraction) add(name string, size int64, open func() (io.ReadCloser, error)) bool {
	if x.expired() {
		x.stopReading(sysdiagnoseOutOfTime)
		return false
	}
	x.entries++
	if x.entries > maxSysdiagnoseEntries || size > maxSysdiagnoseTotalBytes-x.totalBytes {
		x.stopReading(sysdiagnoseRestOfArchive)
		return false
	}
	x.totalBytes += size

	basename := filepath.Base(name)
	keys := make([]string, 0, 2)
	for key, pattern := range sysdiagnoseFiles {
		if strings.Contains(name, pattern) || basename == pattern {
			keys = append(keys, key)
		}
	}

	if size > maxSysdiagnoseEntryBytes {
		x.skip(name)
		return true
	}
	if sysdiagnoseInFlight.Add(size) > maxSysdiagnoseInFlightBytes {
		sysdiagnoseInFlight.Add(-size)
		x.busy = true
		x.stopReading(sysdiagnoseRestOfArchive)
		return false
	}
	defer sysdiagnoseInFlight.Add(-size)

	content, err := readSysdiagnoseEntry(size, open)
	if err != nil {
		x.skip(name)
		return true
	}
	return x.visit(sysdiagnoseEntry{name: name, keys: keys, content: content})
}

// readSysdiagnoseEntry reads exactly the declared size and refuses an entry
// that holds more or less, so the bytes held always match the reservation.
func readSysdiagnoseEntry(size int64, open func() (io.ReadCloser, error)) ([]byte, error) {
	rc, err := open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()

	content := make([]byte, size)
	if _, err := io.ReadFull(rc, content); err != nil {
		return nil, err
	}
	var extra [1]byte
	if _, err := io.ReadFull(rc, extra[:]); err != io.EOF {
		return nil, errSysdiagnoseEntryTooLarge
	}
	return content, nil
}

// examineEntry runs every analysis on one entry, once.
func (p *SysdiagnoseParser) examineEntry(e sysdiagnoseEntry, x *sysdiagnoseExtraction, result *models.ForensicResult, timeline *models.Timeline) {
	if len(e.content) > 0 {
		for _, key := range e.keys {
			// shutdown.log counts only if its parser recognises it, below.
			if key != "shutdown.log" {
				x.recognised = true
			}
		}
	}

	p.analyzeFile(x.context(), e, result, timeline)
	if x.expired() {
		x.skip(e.name)
		return
	}

	if len(e.content) > 0 && strings.HasPrefix(filepath.Base(e.name), "shutdown.log") {
		shutdownResult, err := p.shutdownLogParser.ParseContext(x.context(), e.content)
		if err != nil {
			x.skip(e.name)
		} else {
			x.recognised = true
			if _, partial := shutdownResult.RawData["not_examined"]; partial {
				x.skip(e.name)
			}
			// Merge shutdown.log results
			for _, a := range shutdownResult.Anomalies {
				if len(result.Anomalies) >= maxSysdiagnoseFindings {
					x.skip(e.name)
					break
				}
				a.ID = uuid.New().String() // Ensure unique IDs
				result.AddAnomaly(a)
			}
			for _, t := range shutdownResult.DetectedThreats {
				result.AddThreat(t)
			}
			for _, event := range shutdownResult.Timeline {
				if len(timeline.Events) >= maxSysdiagnoseFindings {
					break
				}
				timeline.AddEvent(event)
			}
		}
	}

	// Analyze crash logs for exploitation indicators
	p.analyzeCrashLogs(e, result, timeline)

	// Analyze network data
	p.analyzeNetworkData(e, result, timeline)

	// Extract device info from sysdiagnose
	p.extractDeviceInfo(e, result)
}

// extractArchive extracts a sysdiagnose archive (tar.gz or zip)
func (p *SysdiagnoseParser) extractArchive(archivePath string, x *sysdiagnoseExtraction) (string, error) {
	// Create temp directory
	tempDir, err := os.MkdirTemp("", "sysdiagnose-*")
	if err != nil {
		return "", fmt.Errorf("failed to create temp dir: %w", err)
	}

	// Determine archive type
	ext := strings.ToLower(filepath.Ext(archivePath))
	if ext == ".gz" || strings.HasSuffix(archivePath, ".tar.gz") {
		err = p.extractTarGz(archivePath, x)
	} else if ext == ".zip" {
		err = p.extractZip(archivePath, x)
	} else {
		// Try reading as directory
		err = p.readDirectory(archivePath, x)
	}

	if err != nil {
		os.RemoveAll(tempDir)
		return "", err
	}

	return tempDir, nil
}

// extractTarGz extracts a tar.gz archive
func (p *SysdiagnoseParser) extractTarGz(archivePath string, x *sysdiagnoseExtraction) error {
	f, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer f.Close()

	gzr, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	defer gzr.Close()

	tr := tar.NewReader(budgetReader{r: gzr, x: x})

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			if x.expired() {
				x.stopReading(sysdiagnoseOutOfTime)
				return nil
			}
			return err
		}

		switch header.Typeflag {
		case tar.TypeReg:
		case tar.TypeDir, tar.TypeSymlink, tar.TypeLink, tar.TypeChar, tar.TypeBlock, tar.TypeFifo, tar.TypeXGlobalHeader:
			continue // holds no file data of its own
		default:
			x.skip(header.Name)
			continue
		}

		if !x.add(header.Name, header.Size, func() (io.ReadCloser, error) {
			return io.NopCloser(tr), nil
		}) {
			break
		}
	}

	return nil
}

// extractZip extracts a zip archive
func (p *SysdiagnoseParser) extractZip(archivePath string, x *sysdiagnoseExtraction) error {
	r, err := safezip.Open(archivePath, safezip.MaxDirectoryBytes)
	if errors.Is(err, models.ErrAnalysisBusy) || errors.Is(err, safezip.ErrDirectoryTooLarge) {
		x.busy = errors.Is(err, models.ErrAnalysisBusy)
		x.stopReading(sysdiagnoseRestOfArchive)
		return nil
	}
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		if f.FileInfo().IsDir() {
			continue
		}

		size := int64(maxSysdiagnoseTotalBytes + 1)
		if f.UncompressedSize64 <= maxSysdiagnoseTotalBytes {
			size = int64(f.UncompressedSize64)
		}
		if !x.add(f.Name, size, f.Open) {
			break
		}
	}

	return nil
}

// readDirectory reads files from an extracted directory
func (p *SysdiagnoseParser) readDirectory(dirPath string, x *sysdiagnoseExtraction) error {
	return filepath.Walk(dirPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			if path != dirPath {
				x.skip(filepath.Base(path))
			}
			return nil
		}
		if !info.Mode().IsRegular() {
			return nil
		}

		relPath, err := filepath.Rel(dirPath, path)
		if err != nil {
			relPath = filepath.Base(path)
		}
		if !x.add(relPath, info.Size(), func() (io.ReadCloser, error) {
			return os.Open(path)
		}) {
			return filepath.SkipAll
		}
		return nil
	})
}

// findRuleMatches finds up to limit matches one chunk at a time, so a large
// entry can stop at the time budget. Chunks end at a line where they can and
// overlap, so a match across a boundary is found once. It stops when ctx ends.
func findRuleMatches(ctx context.Context, re *regexp.Regexp, content []byte, limit int) [][]int {
	var found [][]int
	floor := 0
	for start := 0; start < len(content); {
		if ctx.Err() != nil {
			return found
		}
		end := start + ruleScanChunk
		if end >= len(content) {
			end = len(content)
		} else if nl := bytes.LastIndexByte(content[start:end], '\n'); nl >= ruleScanChunk/2 {
			end = start + nl + 1
		}
		for _, m := range re.FindAllIndex(content[start:end], limit) {
			// At a cut, ^ $ and \b would see a false edge. The next or the
			// previous chunk holds the same bytes with their real neighbours.
			if end < len(content) && m[1] == end-start {
				continue
			}
			if m[0] == 0 && start > 0 && content[start-1] != '\n' {
				continue
			}
			if m[0]+start < floor {
				continue
			}
			found = append(found, []int{m[0] + start, m[1] + start})
			floor = m[1] + start
			if len(found) == limit {
				return found
			}
		}
		if end == len(content) {
			break
		}
		next := end - ruleScanOverlap
		if nl := bytes.IndexByte(content[next:end], '\n'); nl >= 0 {
			next += nl + 1
		}
		start = next
	}
	return found
}

// analyzeFile analyzes a single file for suspicious patterns until ctx ends.
func (p *SysdiagnoseParser) analyzeFile(ctx context.Context, e sysdiagnoseEntry, result *models.ForensicResult, timeline *models.Timeline) {
	filename, content := e.name, e.content

	for _, pattern := range sysdiagnoseSuspiciousPatterns {
		// Check if pattern applies to this file
		if !e.matchesRule(pattern.FilePattern) {
			continue
		}

		matches := findRuleMatches(ctx, pattern.Pattern, content, maxRuleMatchesPerEntry)
		for _, match := range matches {
			// Extract context around match
			start := match[0] - 100
			if start < 0 {
				start = 0
			}
			end := match[1] + 100
			if end > len(content) {
				end = len(content)
			}
			context := string(content[start:end])

			anomaly := models.Anomaly{
				ID:          uuid.New().String(),
				Type:        models.AnomalyTypeFileAnomaly,
				Severity:    p.getSeverity(pattern.Score),
				Confidence:  pattern.Score,
				Title:       "Suspicious Pattern in Sysdiagnose",
				Description: pattern.Reason,
				Path:        filename,
				Evidence: map[string]any{
					"pattern":    pattern.Pattern.String(),
					"context":    context,
					"match_pos":  match[0],
				},
			}

			result.AddAnomaly(anomaly)

			// Add to timeline with approximate time
			now := time.Now()
			timeline.AddEvent(models.TimelineEvent{
				ID:           uuid.New().String(),
				Timestamp:    now, // Could be extracted from log line if available
				Type:         models.TimelineEventTypeAnomaly,
				Source:       "sysdiagnose:" + filename,
				Title:        pattern.Reason,
				Description:  fmt.Sprintf("Found in %s", filename),
				Path:         filename,
				IsSuspicious: true,
				Severity:     p.getSeverity(pattern.Score),
				AnomalyID:    anomaly.ID,
			})
		}
	}
}

// analyzeCrashLogs analyzes crash logs for exploitation indicators
func (p *SysdiagnoseParser) analyzeCrashLogs(e sysdiagnoseEntry, result *models.ForensicResult, timeline *models.Timeline) {
	// Look for crash logs
	filename, content, label := e.name, e.content, e.kindLabel()

	if !strings.Contains(label, "crash") &&
		!strings.Contains(label, "spin") &&
		!strings.HasSuffix(filename, ".ips") {
		return
	}

	// Check for WebKit/JavaScriptCore crashes (common exploit vector)
	if bytes.Contains(content, []byte("JavaScriptCore")) ||
		bytes.Contains(content, []byte("WebKit")) {

		// Look for specific exploit indicators
		exploitIndicators := []string{
			"JIT",
			"ArrayBuffer",
			"TypedArray",
			"Use-after-free",
			"heap corruption",
			"out of bounds",
		}

		for _, indicator := range exploitIndicators {
			if bytes.Contains(content, []byte(indicator)) {
				anomaly := models.Anomaly{
					ID:          uuid.New().String(),
					Type:        models.AnomalyTypeCrashAnomaly,
					Severity:    models.ForensicSeverityHigh,
					Confidence:  0.75,
					Title:       "Potential Exploit Crash Detected",
					Description: fmt.Sprintf("WebKit/JSC crash with %s indicator", indicator),
					Path:        filename,
					MITRETechniques: []string{
						"T1203", // Exploitation for Client Execution
						"T1059.007", // JavaScript
					},
				}
				result.AddAnomaly(anomaly)
				break
			}
		}
	}

	// Check for iMessage/imagent crashes (zero-click vector)
	if bytes.Contains(content, []byte("imagent")) ||
		bytes.Contains(content, []byte("IMTransferAgent")) ||
		bytes.Contains(content, []byte("MessagesBlastDoor")) {

		anomaly := models.Anomaly{
			ID:          uuid.New().String(),
			Type:        models.AnomalyTypeCrashAnomaly,
			Severity:    models.ForensicSeverityCritical,
			Confidence:  0.80,
			Title:       "iMessage Component Crash",
			Description: "Crash in iMessage processing - potential zero-click exploit indicator",
			Path:        filename,
			MITRETechniques: []string{
				"T1203", // Exploitation for Client Execution
				"T1204", // User Execution (zero-click bypasses this)
			},
		}
		result.AddAnomaly(anomaly)
	}
}

// analyzeNetworkData analyzes network-related files for anomalies
func (p *SysdiagnoseParser) analyzeNetworkData(e sysdiagnoseEntry, result *models.ForensicResult, timeline *models.Timeline) {
	// Look for network configuration and usage anomalies
	filename, content, label := e.name, e.content, e.kindLabel()

	if !strings.Contains(label, "network") &&
		!strings.Contains(label, "wifi") &&
		!strings.Contains(label, "netusage") {
		return
	}

	// Check for VPN bypass indicators
	if bytes.Contains(content, []byte("VPN")) {
		if bytes.Contains(content, []byte("bypass")) ||
			bytes.Contains(content, []byte("split tunnel")) ||
			bytes.Contains(content, []byte("leak")) {
			anomaly := models.Anomaly{
				ID:          uuid.New().String(),
				Type:        models.AnomalyTypeNetworkAnomaly,
				Severity:    models.ForensicSeverityMedium,
				Confidence:  0.6,
				Title:       "Potential VPN Bypass",
				Description: "Network logs indicate possible VPN bypass activity",
				Path:        filename,
			}
			result.AddAnomaly(anomaly)
		}
	}

	// Check for suspicious DNS queries
	suspiciousDNSPatterns := []string{
		".onion", // Tor
		".i2p",   // I2P
		"duckdns.org",
		"no-ip.org",
		"ddns.net",
	}
	for _, pattern := range suspiciousDNSPatterns {
		if bytes.Contains(content, []byte(pattern)) {
			anomaly := models.Anomaly{
				ID:          uuid.New().String(),
				Type:        models.AnomalyTypeNetworkAnomaly,
				Severity:    models.ForensicSeverityMedium,
				Confidence:  0.65,
				Title:       "Suspicious DNS Pattern",
				Description: fmt.Sprintf("DNS pattern %s found in network logs", pattern),
				Path:        filename,
			}
			result.AddAnomaly(anomaly)
		}
	}
}

// detectCoordinatedActivity looks for coordinated suspicious activity
func (p *SysdiagnoseParser) detectCoordinatedActivity(result *models.ForensicResult, timeline *models.Timeline) {
	// Count anomalies by type
	typeCounts := make(map[models.AnomalyType]int)
	for _, a := range result.Anomalies {
		typeCounts[a.Type]++
	}

	// If multiple different anomaly types, likely coordinated attack
	if len(typeCounts) >= 3 {
		anomaly := models.Anomaly{
			ID:          uuid.New().String(),
			Type:        models.AnomalyTypeProcessAnomaly,
			Severity:    models.ForensicSeverityCritical,
			Confidence:  0.85,
			Title:       "Coordinated Attack Indicators",
			Description: fmt.Sprintf("Multiple anomaly types detected (%d types) suggesting coordinated attack", len(typeCounts)),
			Evidence: map[string]any{
				"anomaly_types": typeCounts,
			},
			MITRETechniques: []string{
				"T1059", // Command and Scripting Interpreter
				"T1055", // Process Injection
				"T1041", // Exfiltration Over C2 Channel
			},
		}
		result.AddAnomaly(anomaly)

		// Add threat if sufficient evidence
		if result.TotalAnomalies >= 5 {
			now := time.Now()
			anomalyIDs := make([]string, 0)
			for _, a := range result.Anomalies {
				anomalyIDs = append(anomalyIDs, a.ID)
			}

			result.AddThreat(models.DetectedThreat{
				Type:        models.InfectionTypeUnknownAPT,
				Name:        "Advanced Persistent Threat Indicators",
				Confidence:  0.75,
				Severity:    models.ForensicSeverityCritical,
				Description: "Multiple forensic indicators suggest sophisticated spyware infection",
				LastActive:  &now,
				AnomalyIDs:  anomalyIDs,
				MITRETechniques: []string{
					"T1059", "T1055", "T1041", "T1547",
				},
				Remediation: []string{
					"Preserve device for professional forensic analysis",
					"Do not factory reset without expert guidance",
					"Contact security professionals",
				},
			})
		}
	}
}

// extractDeviceInfo extracts device information from sysdiagnose
func (p *SysdiagnoseParser) extractDeviceInfo(e sysdiagnoseEntry, result *models.ForensicResult) {
	// Look for device info files
	filename, content := filepath.Base(e.name), e.content

	// Extract iOS version
	if bytes.Contains(content, []byte("ProductVersion")) {
		scanner := bufio.NewScanner(bytes.NewReader(content))
		for scanner.Scan() {
			line := scanner.Text()
			if strings.Contains(line, "ProductVersion") {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					result.RawData["ios_version"] = strings.TrimSpace(parts[1])
				}
			}
			if strings.Contains(line, "ProductName") {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					result.RawData["product_name"] = strings.TrimSpace(parts[1])
				}
			}
			if strings.Contains(line, "SerialNumber") {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					result.RawData["serial_number"] = strings.TrimSpace(parts[1])
				}
			}
		}
	}

	// Extract sysdiagnose timestamp
	if strings.Contains(filename, "sysdiagnose") && strings.Contains(filename, "_") {
		// Try to parse timestamp from filename like sysdiagnose_2024.01.01_12-00-00
		parts := strings.Split(filename, "_")
		if len(parts) >= 2 {
			result.RawData["sysdiagnose_date"] = parts[1]
		}
	}
}

// getSeverity converts confidence score to severity
func (p *SysdiagnoseParser) getSeverity(score float64) models.ForensicSeverity {
	switch {
	case score >= 0.9:
		return models.ForensicSeverityCritical
	case score >= 0.7:
		return models.ForensicSeverityHigh
	case score >= 0.5:
		return models.ForensicSeverityMedium
	case score >= 0.3:
		return models.ForensicSeverityLow
	default:
		return models.ForensicSeverityInfo
	}
}
