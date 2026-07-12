package yara

import (
	"strings"
	"testing"

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
