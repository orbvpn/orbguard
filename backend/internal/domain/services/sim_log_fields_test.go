package services

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// SIM and handset identifiers must not reach a log line, either as a field or
// inside an error that a caller logs. Persisting SIM events needs a database,
// so this is checked in source across the module's internal packages.
func TestSIMIdentifiersStayOutOfLogs(t *testing.T) {
	field := regexp.MustCompile(`(?i)\b(Str|Interface|Any)\("(iccid|imsi|imei)"`)
	wrapped := regexp.MustCompile(`Errorf\([^\n]*\.(ICCID|IMSI|IMEI)\b`)
	err := filepath.WalkDir("../..", func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return err
		}
		source, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if field.Match(source) {
			t.Errorf("%s logs a SIM or handset identifier", path)
		}
		if wrapped.Match(source) {
			t.Errorf("%s puts a SIM or handset identifier in an error", path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}
