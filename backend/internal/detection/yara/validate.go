package yara

import (
	"context"
	"fmt"
	"regexp/syntax"
	"strings"

	"orbguard-lab/internal/domain/models"
)

const (
	// MaxPatternsPerRule and MaxPatternBytes bound one rule block submitted
	// for validation. The compiler is interruptible between patterns but not
	// inside one, so a single pattern is the largest unit of work a request
	// deadline cannot cut short. Real rules carry a few dozen patterns of at
	// most a few hundred bytes.
	MaxPatternsPerRule = 1024
	MaxPatternBytes    = 64 << 10

	// MaxRegexInsts bounds the program one regex pattern may compile to and
	// MaxSubmissionRegexInsts the programs of all regex patterns in one
	// submission together, in regexp instructions estimated from the parse
	// before anything is compiled. Bytes do not bound a regex: a counted
	// repetition multiplies, so /x{1000}/ is 7 bytes and 1000 instructions,
	// and 23 KB of such text compiles to the 3.3M instructions Go itself
	// stops at, allocating close to 1 GB. One pattern may cost what a
	// MaxPatternBytes literal costs, a whole submission four times that,
	// which is about what its 256 KiB body admits as literal text anyway.
	MaxRegexInsts           = MaxPatternBytes
	MaxSubmissionRegexInsts = 4 * MaxRegexInsts
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
	// Background never cancels, so the error path of the context variant is
	// unreachable here.
	result, _ := l.ValidateSourceContext(context.Background(), content)
	return result
}

// ValidateSourceContext is ValidateSource with cooperative cancellation. Rule
// text reaches this from any device key, so the work it can cause is bounded
// before the compiler runs: a block with more than MaxPatternsPerRule
// patterns, a pattern longer than MaxPatternBytes, a regex estimated above
// MaxRegexInsts, or regexes that together exceed MaxSubmissionRegexInsts are
// validation errors and are never compiled. ctx is the backstop on top of
// that: it is checked before every rule block and, inside the compiler,
// before every pattern, and the call returns ctx.Err() as soon as it is done,
// with whatever was validated so far (never marked Valid).
func (l *Loader) ValidateSourceContext(ctx context.Context, content string) (*RuleValidation, error) {
	result := &RuleValidation{}

	trimmed := strings.TrimSpace(content)
	if trimmed == "" {
		result.Errors = append(result.Errors, "rule content is empty")
		return result, nil
	}

	if err := ctx.Err(); err != nil {
		return result, err
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
		return result, nil
	}

	engine := NewEngine()
	seenNames := make(map[string]bool)
	parsedRules := make([]*models.YARARule, 0, len(blocks))
	var regexInstsUsed int64

	for _, block := range blocks {
		if err := ctx.Err(); err != nil {
			return result, err
		}
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

		if msg := patternLimitError(rule.Strings, &regexInstsUsed); msg != "" {
			result.Errors = append(result.Errors, fmt.Sprintf("rule %q: %s", ruleName, msg))
			continue
		}

		// Compile every pattern with the live engine's compiler to surface
		// real regex/hex compilation errors; the deadline is honoured
		// between patterns.
		if _, err := engine.CompileRuleContext(ctx, rule); err != nil {
			if ctxErr := ctx.Err(); ctxErr != nil {
				return result, ctxErr
			}
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
	return result, nil
}

// patternLimitError reports, as a validation message, the first way one
// rule's patterns exceed what a submission may ask the compiler to do, or ""
// when they are within every limit. used carries the regex instructions the
// submission's earlier rules took and is advanced only for a rule that fits,
// so a refused rule leaves its share of the budget to the rules after it.
func patternLimitError(patterns []models.YARAString, used *int64) string {
	if len(patterns) > MaxPatternsPerRule {
		return fmt.Sprintf("%d string patterns exceed the limit of %d per rule", len(patterns), MaxPatternsPerRule)
	}
	var insts int64
	for i := range patterns {
		p := &patterns[i]
		if len(p.Value) > MaxPatternBytes {
			return fmt.Sprintf("pattern %s is %d bytes, over the %d byte limit", p.ID, len(p.Value), MaxPatternBytes)
		}
		// Text and hex patterns compile to one instruction per byte at most,
		// so their byte limit is their cost limit; only a regex multiplies.
		if p.Type != models.YARAStringTypeRegex {
			continue
		}
		n, err := regexInsts(p.Value, MaxRegexInsts)
		if err != nil {
			// Not a valid expression: the compiler rejects it at parse time
			// and reports the real error.
			continue
		}
		if n > MaxRegexInsts {
			return fmt.Sprintf("regex pattern %s would compile to more than %d instructions; use fewer or smaller counted repetitions", p.ID, MaxRegexInsts)
		}
		insts += n
	}
	if *used+insts > MaxSubmissionRegexInsts {
		return fmt.Sprintf("regex patterns of this submission would compile to more than %d instructions in total; submit fewer or simpler regex rules per request", MaxSubmissionRegexInsts)
	}
	*used += insts
	return ""
}

// regexInsts estimates how many instructions regexp compiles expr into, with
// the accounting regexp/syntax applies to its own size limit, but from the
// parse tree alone: building the program (Simplify expands every counted
// repetition) is exactly the cost being bounded. A nocase modifier does not
// change the count (case folding happens inside an instruction). The result
// saturates just past limit, so no expression can overflow it.
func regexInsts(expr string, limit int64) (int64, error) {
	re, err := syntax.Parse(expr, syntax.Perl)
	if err != nil {
		return 0, err
	}
	return instEstimate(re, limit), nil
}

func instEstimate(re *syntax.Regexp, limit int64) int64 {
	var size int64
	switch re.Op {
	case syntax.OpLiteral:
		size = int64(len(re.Rune))
	case syntax.OpCapture, syntax.OpStar:
		size = 2 + instEstimate(re.Sub[0], limit)
	case syntax.OpPlus, syntax.OpQuest:
		size = 1 + instEstimate(re.Sub[0], limit)
	case syntax.OpConcat, syntax.OpAlternate:
		for _, sub := range re.Sub {
			if size += instEstimate(sub, limit); size > limit {
				return limit + 1
			}
		}
		if re.Op == syntax.OpAlternate && len(re.Sub) > 1 {
			size += int64(len(re.Sub)) - 1
		}
	case syntax.OpRepeat:
		sub := instEstimate(re.Sub[0], limit)
		switch {
		case re.Max == -1 && re.Min == 0:
			size = 2 + sub
		case re.Max == -1:
			size = 1 + int64(re.Min)*sub
		default:
			size = int64(re.Max)*sub + int64(re.Max-re.Min)
		}
	}
	return min(max(1, size), limit+1)
}
