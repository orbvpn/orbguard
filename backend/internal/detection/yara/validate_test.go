package yara

import (
	"context"
	"errors"
	"fmt"
	"regexp/syntax"
	"runtime"
	"strings"
	"testing"
	"time"

	"orbguard-lab/pkg/logger"
)

func newTestLoader() *Loader {
	return NewLoader(logger.NewDefault())
}

func TestValidateSourceValidRule(t *testing.T) {
	src := `
rule Test_Stalkerware : stalkerware android
{
	meta:
		description = "Detects a test stalkerware package"
		author = "unit-test"
		severity = "high"
		category = "stalkerware"
		platform = "android"
	strings:
		$pkg1 = "com.example.spy" nocase
		$hex1 = { DE AD BE EF }
		$re1 = /upload[_-]?data/ nocase
	condition:
		any of them
}
`
	result := newTestLoader().ValidateSource(src)

	if !result.Valid {
		t.Fatalf("expected valid, got errors: %v", result.Errors)
	}
	if len(result.Rules) != 1 {
		t.Fatalf("expected 1 rule, got %d", len(result.Rules))
	}
	meta := result.Rules[0]
	if meta.Name != "Test_Stalkerware" {
		t.Errorf("name = %q, want Test_Stalkerware", meta.Name)
	}
	if meta.Category != "stalkerware" {
		t.Errorf("category = %q, want stalkerware", meta.Category)
	}
	if meta.Severity != "high" {
		t.Errorf("severity = %q, want high", meta.Severity)
	}
	if meta.StringCount != 3 {
		t.Errorf("string_count = %d, want 3", meta.StringCount)
	}
	if meta.Condition != "any of them" {
		t.Errorf("condition = %q, want \"any of them\"", meta.Condition)
	}
}

func TestValidateSourceEmpty(t *testing.T) {
	result := newTestLoader().ValidateSource("   \n  ")
	if result.Valid {
		t.Fatal("expected invalid for empty content")
	}
	if len(result.Errors) == 0 {
		t.Fatal("expected an error for empty content")
	}
}

func TestValidateSourceNoRuleBlock(t *testing.T) {
	result := newTestLoader().ValidateSource("this is not a yara rule at all")
	if result.Valid {
		t.Fatal("expected invalid for non-rule content")
	}
	if len(result.Errors) == 0 {
		t.Fatal("expected an error for non-rule content")
	}
}

func TestValidateSourceBadRegex(t *testing.T) {
	src := `
rule Bad_Regex
{
	strings:
		$re1 = /([unclosed/
	condition:
		any of them
}
`
	result := newTestLoader().ValidateSource(src)
	if result.Valid {
		t.Fatal("expected invalid for unparsable regex pattern")
	}
	found := false
	for _, e := range result.Errors {
		if strings.Contains(e, "Bad_Regex") {
			found = true
		}
	}
	if !found {
		t.Errorf("expected error mentioning rule name, got: %v", result.Errors)
	}
}

func TestValidateSourceNoStrings(t *testing.T) {
	src := `
rule No_Strings
{
	condition:
		filesize > 100
}
`
	result := newTestLoader().ValidateSource(src)
	if result.Valid {
		t.Fatal("expected invalid for rule without string patterns")
	}
}

func TestValidateSourceDuplicateNames(t *testing.T) {
	src := `
rule Dup { strings: $a = "x" condition: any of them }
rule Dup { strings: $b = "y" condition: any of them }
`
	result := newTestLoader().ValidateSource(src)
	if result.Valid {
		t.Fatal("expected invalid for duplicate rule names")
	}
}

func TestValidateSourceWarnsOnMissingDescription(t *testing.T) {
	src := `
rule No_Meta { strings: $a = "indicator" condition: any of them }
`
	result := newTestLoader().ValidateSource(src)
	if !result.Valid {
		t.Fatalf("expected valid, got errors: %v", result.Errors)
	}
	if len(result.Warnings) == 0 {
		t.Error("expected a warning about missing description")
	}
}

func TestValidateSourceContextStopsWhenCancelled(t *testing.T) {
	// Twenty valid rules; with a live context they all validate.
	var src strings.Builder
	for i := 0; i < 20; i++ {
		fmt.Fprintf(&src, "rule Cancel_%d { strings: $a = \"indicator-%d\" condition: any of them }\n", i, i)
	}
	loader := newTestLoader()

	result, err := loader.ValidateSourceContext(context.Background(), src.String())
	if err != nil || !result.Valid || len(result.Rules) != 20 {
		t.Fatalf("live context: want 20 valid rules and no error, got valid=%v rules=%d err=%v", result.Valid, len(result.Rules), err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	result, err = loader.ValidateSourceContext(ctx, src.String())
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled context: want context.Canceled, got %v", err)
	}
	if result == nil || result.Valid {
		t.Fatal("a cancelled validation must never report Valid")
	}
	if len(result.Rules) != 0 {
		t.Fatalf("cancelled before the first block: want no rules, got %d", len(result.Rules))
	}

	// The context-free wrapper is unaffected.
	if plain := loader.ValidateSource(src.String()); !plain.Valid {
		t.Fatalf("ValidateSource: want valid, got errors %v", plain.Errors)
	}
}

// validateCost runs one validation and reports how long it took and how many
// bytes it allocated, the two things a hostile submission tries to inflate.
func validateCost(t *testing.T, src string) (*RuleValidation, time.Duration, uint64) {
	t.Helper()
	loader := newTestLoader()
	var before, after runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&before)
	start := time.Now()
	result, err := loader.ValidateSourceContext(context.Background(), src)
	elapsed := time.Since(start)
	runtime.ReadMemStats(&after)
	if err != nil {
		t.Fatalf("validation with a live context failed: %v", err)
	}
	return result, elapsed, after.TotalAlloc - before.TotalAlloc
}

// hexWildcards is a hex string body of n characters that is all wildcards.
func hexWildcards(n int) string { return strings.Repeat("A?", n/2) }

// TestValidateSourceBoundsCompileWork pins the work one submission can cause.
// Before the limits, one hex-wildcard string under the 256 KiB body cap cost
// seconds of CPU, and 230 KB of /x{1000}x{1000}.../ patterns cost 2 s and
// 7 GB of allocation; every case below is refused (or accepted) in a small
// fraction of the 5 s request deadline, without compiling anything over
// budget.
func TestValidateSourceBoundsCompileWork(t *testing.T) {
	const budget = time.Second // generous: each case takes milliseconds
	const allocBudget = 128 << 20

	rule := func(name, strs string) string {
		return "rule " + name + " { strings:\n" + strs + "\ncondition: any of them }\n"
	}
	regexOf := func(n int) string { return strings.Repeat("x{1000}", n) } // n*1000 instructions

	tests := []struct {
		name      string
		src       string
		wantValid bool
		wantErr   string
	}{
		{
			name:    "240 KiB hex wildcard string is refused without compiling",
			src:     rule("Huge_Hex", "$a = { "+hexWildcards(240<<10)+" }"),
			wantErr: "byte limit",
		},
		{
			name:      "a hex wildcard string at the byte limit still validates",
			src:       rule("Max_Hex", "$a = { "+hexWildcards(MaxPatternBytes)+" }"),
			wantValid: true,
		},
		{
			name:    "one 23 KB regex expanding to 3.35M instructions is refused",
			src:     rule("Huge_Regex", "$a = /"+regexOf(3350)+"/"),
			wantErr: "instructions",
		},
		{
			name: "ten such regexes in one 230 KB submission are refused",
			src: func() string {
				var b strings.Builder
				for i := 0; i < 10; i++ {
					fmt.Fprintf(&b, "$a%d = /%s/\n", i, regexOf(3300))
				}
				return rule("Many_Regex", b.String())
			}(),
			wantErr: "instructions",
		},
		{
			name: "regexes just inside both instruction budgets validate",
			src: func() string {
				var b strings.Builder
				for i := 0; i < 4; i++ {
					fmt.Fprintf(&b, "$a%d = /%s/\n", i, regexOf(65))
				}
				return rule("Max_Regex", b.String())
			}(),
			wantValid: true,
		},
		{
			name: "the submission-wide regex budget spans rules",
			src: func() string {
				var b strings.Builder
				for i := 0; i < 5; i++ {
					b.WriteString(rule(fmt.Sprintf("Spread_%d", i), "$a = /"+regexOf(60)+"/"))
				}
				return b.String()
			}(),
			wantErr: "in total",
		},
		{
			name: "more patterns than a rule may carry are refused",
			src: func() string {
				var b strings.Builder
				for i := 0; i <= MaxPatternsPerRule; i++ {
					fmt.Fprintf(&b, "$s%d = \"v%d\"\n", i, i)
				}
				return rule("Too_Many", b.String())
			}(),
			wantErr: "per rule",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result, elapsed, alloc := validateCost(t, tc.src)
			if result.Valid != tc.wantValid {
				t.Fatalf("valid = %v, want %v (errors %v)", result.Valid, tc.wantValid, result.Errors)
			}
			if tc.wantErr != "" && !strings.Contains(strings.Join(result.Errors, "\n"), tc.wantErr) {
				t.Fatalf("want an error mentioning %q, got %v", tc.wantErr, result.Errors)
			}
			if elapsed > budget {
				t.Fatalf("validation took %s, want well under the request deadline (< %s)", elapsed, budget)
			}
			if alloc > allocBudget {
				t.Fatalf("validation allocated %d MiB, want < %d MiB", alloc>>20, allocBudget>>20)
			}
		})
	}
}

func TestValidateSourceSubmissionBudgetLeavesRoomAfterARefusedRule(t *testing.T) {
	// A rule refused for its own size must not consume the shared budget:
	// the four rules after it fill all but 2,144 of the 262,144 instructions,
	// so any share charged for the refused one would push the last one out.
	src := "rule Too_Big { strings: $a = /" + strings.Repeat("x{1000}", 70) + "/ condition: any of them }\n"
	for i := 1; i <= 4; i++ {
		src += fmt.Sprintf("rule Fits_%d { strings: $a = /%s/ condition: any of them }\n", i, strings.Repeat("x{1000}", 65))
	}
	result := newTestLoader().ValidateSource(src)
	if result.Valid || len(result.Errors) != 1 || !strings.Contains(result.Errors[0], `"Too_Big"`) {
		t.Fatalf("want exactly one error, for Too_Big; got %v", result.Errors)
	}
	if len(result.Rules) != 4 {
		t.Fatalf("want the four Fits rules validated, got %+v", result.Rules)
	}

	// The same holds for a rule refused because the submission ran out: four
	// rules take 240,000, a fifth of 60,000 does not fit, and a sixth of
	// 20,000 still does.
	src = ""
	for i := 1; i <= 4; i++ {
		src += fmt.Sprintf("rule Fill_%d { strings: $a = /%s/ condition: any of them }\n", i, strings.Repeat("x{1000}", 60))
	}
	src += "rule Over { strings: $a = /" + strings.Repeat("x{1000}", 60) + "/ condition: any of them }\n"
	src += "rule Small { strings: $a = /" + strings.Repeat("x{1000}", 20) + "/ condition: any of them }\n"
	result = newTestLoader().ValidateSource(src)
	if len(result.Errors) != 1 || !strings.Contains(result.Errors[0], `"Over"`) || !strings.Contains(result.Errors[0], "in total") {
		t.Fatalf("want exactly one error, the total budget for Over; got %v", result.Errors)
	}
	if len(result.Rules) != 5 || result.Rules[4].Name != "Small" {
		t.Fatalf("want Fill_1..4 and Small validated, got %+v", result.Rules)
	}
}

// TestRegexInstsTracksCompiledProgram checks the estimate against the
// program regexp really builds: it must not undercount (or the budget is
// fiction) nor overcount real rule patterns into refusals. The compiled
// program carries two fixed instructions (fail, match) the estimate omits.
func TestRegexInstsTracksCompiledProgram(t *testing.T) {
	for _, expr := range []string{
		"a", "abc", "a*", "a+", "a?", "(a)", "(?:ab)*", "a{3}", "a{2,5}", "a{2,}",
		"(a|b|c)", "a|bc", "[a-f0-9]{64}", ".{0,1000}", "(x{2}){3}", `(?i)hello\s+world`,
		"^foo$", "x{1000}", "(?:(?:a{10}){10}){10}", `https?://[a-z0-9.-]+/[a-z0-9]{32}`,
		"(a*)*", `\bword\b`, "(?:)", "", `upload[_-]?data`, `[\x{0}-\x{10FFFF}]{100}`,
	} {
		re, err := syntax.Parse(expr, syntax.Perl)
		if err != nil {
			t.Fatalf("parse %q: %v", expr, err)
		}
		prog, err := syntax.Compile(re.Simplify())
		if err != nil {
			t.Fatalf("compile %q: %v", expr, err)
		}
		est, err := regexInsts(expr, 1<<30)
		if err != nil {
			t.Fatalf("regexInsts(%q): %v", expr, err)
		}
		if actual := int64(len(prog.Inst)); est < actual-2 || est > actual {
			t.Errorf("regexInsts(%q) = %d, compiled program has %d instructions (want %d..%d)", expr, est, actual, actual-2, actual)
		}
	}

	// It saturates instead of growing with the expression.
	if n, err := regexInsts(strings.Repeat("x{1000}", 3000), 5000); err != nil || n != 5001 {
		t.Fatalf("saturation: want 5001, got %d (err %v)", n, err)
	}
	// An invalid expression is reported, not estimated.
	if _, err := regexInsts("a(b", MaxRegexInsts); err == nil {
		t.Fatal("an unparsable expression must return the parse error")
	}
}
