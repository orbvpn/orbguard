package yara

import (
	"fmt"
	"strings"

	"orbguard-lab/internal/domain/models"
)

// RuleMetadata is the metadata extracted from a successfully parsed rule.
// It is returned by validation endpoints and stored alongside submissions.
type RuleMetadata struct {
	Name        string   `json:"name"`
	Description string   `json:"description,omitempty"`
	Author      string   `json:"author,omitempty"`
	Reference   string   `json:"reference,omitempty"`
	Category    string   `json:"category"`
	Severity    string   `json:"severity"`
	Tags        []string `json:"tags,omitempty"`
	Platforms   []string `json:"platforms,omitempty"`
	MitreTTPs   []string `json:"mitre_ttps,omitempty"`
	StringCount int      `json:"string_count"`
	Condition   string   `json:"condition,omitempty"`
}

// RuleValidation is the result of validating YARA rule source text against
// the same parser and pattern compiler used by the live scan path.
type RuleValidation struct {
	Valid    bool           `json:"valid"`
	Errors   []string       `json:"errors,omitempty"`
	Warnings []string       `json:"warnings,omitempty"`
	Rules    []RuleMetadata `json:"rules,omitempty"`
}

// ValidateSource parses and compiles YARA rule source text using the exact
// parser (Loader.parseRuleBody) and compiler (Engine.CompileRule) that the
// /yara/scan path uses, so a rule that validates here is guaranteed to load
// into the live engine. It returns real parse/compile errors, warnings, and
// extracted metadata for each rule found; it never fabricates success.
func (l *Loader) ValidateSource(content string) *RuleValidation {
	result := &RuleValidation{}

	trimmed := strings.TrimSpace(content)
	if trimmed == "" {
		result.Errors = append(result.Errors, "rule content is empty")
		return result
	}

	blocks := ruleBlockPattern.FindAllStringSubmatch(trimmed, -1)
	if len(blocks) == 0 {
		if strings.Contains(trimmed, "rule") {
			result.Errors = append(result.Errors,
				"no parsable rule definitions found: expected `rule <name> [: tags] { meta:/strings:/condition: ... }`")
		} else {
			result.Errors = append(result.Errors,
				"no rule definitions found: content must contain at least one `rule` block")
		}
		return result
	}

	engine := NewEngine()
	seenNames := make(map[string]bool)
	parsedRules := make([]*models.YARARule, 0, len(blocks))

	for _, block := range blocks {
		if len(block) < 4 {
			continue
		}

		ruleName := strings.TrimSpace(block[1])
		ruleTags := strings.TrimSpace(block[2])
		ruleBody := strings.TrimSpace(block[3])

		if seenNames[ruleName] {
			result.Errors = append(result.Errors,
				fmt.Sprintf("rule %q: duplicate rule name in submission", ruleName))
			continue
		}
		seenNames[ruleName] = true

		rule, err := l.parseRuleBody(ruleName, ruleTags, ruleBody)
		if err != nil {
			result.Errors = append(result.Errors,
				fmt.Sprintf("rule %q: parse failed: %v", ruleName, err))
			continue
		}

		// The pure-Go engine matches string patterns only; a rule without
		// any parsable strings can never match anything.
		if len(rule.Strings) == 0 {
			result.Errors = append(result.Errors,
				fmt.Sprintf("rule %q: no string patterns parsed; the engine requires at least one $string definition", ruleName))
			continue
		}

		// Compile every pattern with the live engine's compiler to surface
		// real regex/hex compilation errors.
		if _, err := engine.CompileRule(rule); err != nil {
			result.Errors = append(result.Errors,
				fmt.Sprintf("rule %q: compile failed: %v", ruleName, err))
			continue
		}

		// Honest warnings about behavior the engine will apply implicitly.
		condition := ""
		if len(rule.Conditions) > 0 {
			condition = strings.TrimSpace(rule.Conditions[0].Expression)
		}
		if condition == "" {
			result.Warnings = append(result.Warnings,
				fmt.Sprintf("rule %q: no condition specified; the engine defaults to \"any of them\"", ruleName))
		}
		if rule.Description == "" {
			result.Warnings = append(result.Warnings,
				fmt.Sprintf("rule %q: meta description is missing", ruleName))
		}

		parsedRules = append(parsedRules, rule)
		result.Rules = append(result.Rules, RuleMetadata{
			Name:        rule.Name,
			Description: rule.Description,
			Author:      rule.Author,
			Reference:   rule.Reference,
			Category:    string(rule.Category),
			Severity:    string(rule.Severity),
			Tags:        rule.Tags,
			Platforms:   rule.Platforms,
			MitreTTPs:   rule.MitreTTPs,
			StringCount: len(rule.Strings),
			Condition:   condition,
		})
	}

	result.Valid = len(result.Errors) == 0 && len(parsedRules) > 0
	return result
}
