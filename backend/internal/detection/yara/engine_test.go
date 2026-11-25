package yara

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"orbguard-lab/internal/domain/models"
)

func threePatternRule() *models.YARARule {
	return &models.YARARule{
		Name: "Ctx_Test",
		Strings: []models.YARAString{
			{ID: "$t", Value: "indicator", Type: models.YARAStringTypeText},
			{ID: "$h", Value: "41 ?? 43", Type: models.YARAStringTypeHex},
			{ID: "$r", Value: `upload[_-]?data`, Type: models.YARAStringTypeRegex},
		},
	}
}

func TestCompileRuleContextHonoursCancellation(t *testing.T) {
	e := NewEngine()

	compiled, err := e.CompileRuleContext(context.Background(), threePatternRule())
	if err != nil || len(compiled.Patterns) != 3 {
		t.Fatalf("live context: want 3 compiled patterns, got %v (err %v)", compiled, err)
	}

	// A context that is already over stops before the first pattern.
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if compiled, err := e.CompileRuleContext(ctx, threePatternRule()); !errors.Is(err, context.Canceled) || compiled != nil {
		t.Fatalf("cancelled context: want (nil, context.Canceled), got (%v, %v)", compiled, err)
	}
	expired, cancelExpired := context.WithDeadline(context.Background(), time.Now().Add(-time.Second))
	defer cancelExpired()
	if _, err := e.CompileRuleContext(expired, threePatternRule()); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("expired deadline: want context.DeadlineExceeded, got %v", err)
	}

	// CompileRule (trusted paths: built-in rules, admin adds) never cancels.
	if _, err := e.CompileRule(threePatternRule()); err != nil {
		t.Fatalf("CompileRule: %v", err)
	}
}

// TestHexWildcardPatternCompilesLinearly pins the hex-wildcard conversion
// (built with a strings.Builder; it used to be quadratic string +=): the
// result still matches what it did, and a pattern at the byte limit compiles
// in milliseconds.
func TestHexWildcardPatternCompilesLinearly(t *testing.T) {
	e := NewEngine()

	p, err := e.compilePattern(&models.YARAString{ID: "$h", Value: "{ 41 ?? 4? 44 }", Type: models.YARAStringTypeHex})
	if err != nil {
		t.Fatalf("compile: %v", err)
	}
	if p.Regex == nil || !p.Regex.MatchString("A#xD") || p.Regex.MatchString("A#xE") {
		t.Fatalf("hex wildcard semantics changed: regex %v", p.Regex)
	}

	start := time.Now()
	if _, err := e.compilePattern(&models.YARAString{ID: "$big", Value: strings.Repeat("A?", MaxPatternBytes/2), Type: models.YARAStringTypeHex}); err != nil {
		t.Fatalf("compile %d-byte hex wildcard: %v", MaxPatternBytes, err)
	}
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("a %d-byte hex wildcard took %s to compile", MaxPatternBytes, elapsed)
	}
}
