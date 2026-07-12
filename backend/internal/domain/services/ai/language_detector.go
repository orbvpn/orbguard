package ai

import (
	"regexp"
	"strings"
	"unicode"

	"orbguard-lab/pkg/logger"
)

// LanguageDetector detects the language of text content
type LanguageDetector struct {
	logger *logger.Logger
}

// SupportedLanguage represents a supported language
type SupportedLanguage struct {
	Code        string `json:"code"`
	Name        string `json:"name"`
	NativeName  string `json:"native_name"`
	Direction   string `json:"direction"` // ltr or rtl
	ScriptRange []rune `json:"-"`         // Unicode range
}

// Supported languages
var (
	LanguageEnglish = SupportedLanguage{
		Code:       "en",
		Name:       "English",
		NativeName: "English",
		Direction:  "ltr",
	}
	LanguageArabic = SupportedLanguage{
		Code:       "ar",
		Name:       "Arabic",
		NativeName: "العربية",
		Direction:  "rtl",
		ScriptRange: []rune{0x0600, 0x06FF}, // Arabic block
	}
	LanguagePersian = SupportedLanguage{
		Code:       "fa",
		Name:       "Persian",
		NativeName: "فارسی",
		Direction:  "rtl",
		ScriptRange: []rune{0x0600, 0x06FF}, // Uses Arabic block + extensions
	}
	LanguageHindi = SupportedLanguage{
		Code:       "hi",
		Name:       "Hindi",
		NativeName: "हिन्दी",
		Direction:  "ltr",
		ScriptRange: []rune{0x0900, 0x097F}, // Devanagari block
	}
	LanguageUrdu = SupportedLanguage{
		Code:       "ur",
		Name:       "Urdu",
		NativeName: "اردو",
		Direction:  "rtl",
		ScriptRange: []rune{0x0600, 0x06FF}, // Uses Arabic block
	}
	LanguageChinese = SupportedLanguage{
		Code:       "zh",
		Name:       "Chinese",
		NativeName: "中文",
		Direction:  "ltr",
		ScriptRange: []rune{0x4E00, 0x9FFF}, // CJK Unified Ideographs
	}
	LanguageRussian = SupportedLanguage{
		Code:       "ru",
		Name:       "Russian",
		NativeName: "Русский",
		Direction:  "ltr",
		ScriptRange: []rune{0x0400, 0x04FF}, // Cyrillic block
	}
	LanguageSpanish = SupportedLanguage{
		Code:       "es",
		Name:       "Spanish",
		NativeName: "Español",
		Direction:  "ltr",
	}
	LanguageFrench = SupportedLanguage{
		Code:       "fr",
		Name:       "French",
		NativeName: "Français",
		Direction:  "ltr",
	}
	LanguageGerman = SupportedLanguage{
		Code:       "de",
		Name:       "German",
		NativeName: "Deutsch",
		Direction:  "ltr",
	}
)

// NewLanguageDetector creates a new language detector
func NewLanguageDetector(log *logger.Logger) *LanguageDetector {
	return &LanguageDetector{
		logger: log.WithComponent("language-detector"),
	}
}

// Detect detects the language of the given text
func (d *LanguageDetector) Detect(text string) string {
	if len(text) == 0 {
		return "en"
	}

	// Count characters by script
	scriptCounts := d.analyzeScript(text)

	// Determine primary script
	primaryScript := d.getPrimaryScript(scriptCounts)

	// Detect specific language within script
	return d.detectLanguageByScript(primaryScript, text)
}

// DetectWithConfidence detects language with confidence score
func (d *LanguageDetector) DetectWithConfidence(text string) (string, float64) {
	if len(text) == 0 {
		return "en", 0.5
	}

	scriptCounts := d.analyzeScript(text)
	totalChars := 0
	maxCount := 0
	var maxScript string

	for script, count := range scriptCounts {
		totalChars += count
		if count > maxCount {
			maxCount = count
			maxScript = script
		}
	}

	confidence := 0.5
	if totalChars > 0 {
		confidence = float64(maxCount) / float64(totalChars)
	}

	lang := d.detectLanguageByScript(maxScript, text)
	return lang, confidence
}

// analyzeScript counts characters by script type
func (d *LanguageDetector) analyzeScript(text string) map[string]int {
	counts := make(map[string]int)

	for _, r := range text {
		script := d.getScript(r)
		if script != "" {
			counts[script]++
		}
	}

	return counts
}

// getScript determines the script of a character
func (d *LanguageDetector) getScript(r rune) string {
	switch {
	case r >= 0x0600 && r <= 0x06FF:
		return "arabic"
	case r >= 0x0750 && r <= 0x077F:
		return "arabic_supplement"
	case r >= 0xFB50 && r <= 0xFDFF:
		return "arabic_presentation_a"
	case r >= 0xFE70 && r <= 0xFEFF:
		return "arabic_presentation_b"
	case r >= 0x0900 && r <= 0x097F:
		return "devanagari"
	case r >= 0x0980 && r <= 0x09FF:
		return "bengali"
	case r >= 0x0A00 && r <= 0x0A7F:
		return "gurmukhi"
	case r >= 0x0A80 && r <= 0x0AFF:
		return "gujarati"
	case r >= 0x4E00 && r <= 0x9FFF:
		return "cjk"
	case r >= 0x3040 && r <= 0x309F:
		return "hiragana"
	case r >= 0x30A0 && r <= 0x30FF:
		return "katakana"
	case r >= 0xAC00 && r <= 0xD7AF:
		return "hangul"
	case r >= 0x0400 && r <= 0x04FF:
		return "cyrillic"
	case r >= 0x0370 && r <= 0x03FF:
		return "greek"
	case r >= 0x0590 && r <= 0x05FF:
		return "hebrew"
	case r >= 0x0E00 && r <= 0x0E7F:
		return "thai"
	case unicode.IsLetter(r) && r < 0x0250:
		return "latin"
	default:
		return ""
	}
}

// getPrimaryScript determines the primary script from counts
func (d *LanguageDetector) getPrimaryScript(counts map[string]int) string {
	maxCount := 0
	primaryScript := "latin"

	for script, count := range counts {
		if count > maxCount {
			maxCount = count
			primaryScript = script
		}
	}

	return primaryScript
}

// detectLanguageByScript detects specific language within a script
func (d *LanguageDetector) detectLanguageByScript(script, text string) string {
	switch script {
	case "arabic", "arabic_supplement", "arabic_presentation_a", "arabic_presentation_b":
		return d.detectArabicVariant(text)
	case "devanagari":
		return "hi" // Hindi
	case "bengali":
		return "bn" // Bengali
	case "gurmukhi":
		return "pa" // Punjabi
	case "gujarati":
		return "gu" // Gujarati
	case "cjk":
		return d.detectCJKLanguage(text)
	case "hiragana", "katakana":
		return "ja" // Japanese
	case "hangul":
		return "ko" // Korean
	case "cyrillic":
		return d.detectCyrillicLanguage(text)
	case "greek":
		return "el" // Greek
	case "hebrew":
		return "he" // Hebrew
	case "thai":
		return "th" // Thai
	case "latin":
		return d.detectLatinLanguage(text)
	default:
		return "en"
	}
}

// detectArabicVariant detects Arabic vs Persian vs Urdu
func (d *LanguageDetector) detectArabicVariant(text string) string {
	// Persian-specific characters
	persianSpecific := []rune{'پ', 'چ', 'ژ', 'گ', 'ی'} // Pe, Che, Zhe, Gaf, Yeh

	// Urdu-specific characters
	urduSpecific := []rune{'ٹ', 'ڈ', 'ڑ', 'ں', 'ے', 'ہ'} // Tteh, Ddal, Rreh, Noon Ghunna, Yeh Barree, Heh Goal

	persianCount := 0
	urduCount := 0

	for _, r := range text {
		for _, p := range persianSpecific {
			if r == p {
				persianCount++
			}
		}
		for _, u := range urduSpecific {
			if r == u {
				urduCount++
			}
		}
	}

	// Persian-specific words
	persianWords := []string{"است", "این", "آن", "را", "می", "که"}
	for _, word := range persianWords {
		if strings.Contains(text, word) {
			persianCount += 2
		}
	}

	// Urdu-specific words
	urduWords := []string{"ہے", "کا", "کی", "نے", "سے", "میں"}
	for _, word := range urduWords {
		if strings.Contains(text, word) {
			urduCount += 2
		}
	}

	if persianCount > urduCount && persianCount > 0 {
		return "fa"
	} else if urduCount > persianCount && urduCount > 0 {
		return "ur"
	}

	return "ar"
}

// detectCJKLanguage attempts to distinguish Chinese variants
func (d *LanguageDetector) detectCJKLanguage(text string) string {
	// Check for Japanese specific characters (hiragana/katakana mixed in)
	hasHiragana := regexp.MustCompile(`[\x{3040}-\x{309F}]`).MatchString(text)
	hasKatakana := regexp.MustCompile(`[\x{30A0}-\x{30FF}]`).MatchString(text)

	if hasHiragana || hasKatakana {
		return "ja"
	}

	// Traditional vs Simplified Chinese detection would require
	// character frequency analysis - defaulting to simplified
	return "zh"
}

// detectCyrillicLanguage detects Russian vs Ukrainian vs Bulgarian
func (d *LanguageDetector) detectCyrillicLanguage(text string) string {
	// Ukrainian-specific characters
	ukrainianChars := []rune{'і', 'ї', 'є', 'ґ'}
	for _, r := range text {
		for _, u := range ukrainianChars {
			if r == u || unicode.ToLower(r) == u {
				return "uk"
			}
		}
	}

	// Bulgarian-specific characters
	bulgarianChars := []rune{'ъ', 'ь'}
	bulgarianCount := 0
	for _, r := range text {
		for _, b := range bulgarianChars {
			if r == b {
				bulgarianCount++
			}
		}
	}

	// Default to Russian
	return "ru"
}

// Minimum number of letter characters required before we trust a non-English
// Latin-script classification. Below this, short strings (e.g. "you won a
// prize") produce too few stop-word hits to distinguish languages reliably, so
// we default to English — the app's primary language — to avoid the common
// misfire where a short English phishing message is tagged as Portuguese/Spanish.
const minLatinLettersForNonEnglish = 25

// minNonEnglishMargin is the score lead a non-English language must hold over
// English (and over the runner-up) before we accept it. A thin margin is more
// likely noise than a genuine signal, so we fall back to English.
const minNonEnglishMargin = 2

// detectLatinLanguage detects specific Latin-script language.
//
// Detection is intentionally conservative: it uses whole-word matching of
// stop-words (not substring matching, which lets short English text accidentally
// match foreign single-letter articles like "a"/"o"/"de"), weights
// language-specific diacritics, and requires both a minimum amount of text and a
// confidence margin before returning a non-English language. When the text is
// short or the margin is thin it defaults to English.
func (d *LanguageDetector) detectLatinLanguage(text string) string {
	textLower := strings.ToLower(text)
	tokens := tokenizeWords(textLower)

	// Count letters to gauge how much signal we actually have.
	letterCount := 0
	for _, r := range textLower {
		if unicode.IsLetter(r) {
			letterCount++
		}
	}

	// Whole-word stop-word sets. Single-character entries are deliberately
	// excluded because they match far too easily across languages.
	wordScore := func(words map[string]struct{}) int {
		score := 0
		for _, tok := range tokens {
			if _, ok := words[tok]; ok {
				score++
			}
		}
		return score
	}

	// Diacritic signals: characters that strongly indicate a specific language.
	diacriticScore := func(chars string) int {
		score := 0
		for _, c := range chars {
			score += strings.Count(textLower, string(c))
		}
		return score
	}

	englishScore := wordScore(englishStopWords)
	// Diacritics are a strong signal; weight them so a single accented marker
	// can tip a short message away from English when nothing else fires.
	spanishScore := wordScore(spanishStopWords) + diacriticScore("ñ¿¡")*2
	frenchScore := wordScore(frenchStopWords) + diacriticScore("çêàùû")*2
	germanScore := wordScore(germanStopWords) + diacriticScore("ßüöä")*2
	portugueseScore := wordScore(portugueseStopWords) + diacriticScore("ãõç")*2
	italianScore := wordScore(italianStopWords)
	dutchScore := wordScore(dutchStopWords)

	type cand struct {
		lang  string
		score int
	}
	nonEnglish := []cand{
		{"es", spanishScore},
		{"fr", frenchScore},
		{"de", germanScore},
		{"pt", portugueseScore},
		{"it", italianScore},
		{"nl", dutchScore},
	}

	// Pick the best non-English candidate.
	best := cand{lang: "en", score: 0}
	for _, c := range nonEnglish {
		if c.score > best.score {
			best = c
		}
	}

	// Default to English when there's not enough text to trust a non-English
	// guess, or when the candidate doesn't clearly beat English.
	if letterCount < minLatinLettersForNonEnglish {
		return "en"
	}
	if best.score-englishScore < minNonEnglishMargin {
		return "en"
	}

	return best.lang
}

// tokenizeWords splits text into lowercase word tokens using non-letter
// boundaries (so punctuation and digits don't merge words). It preserves
// accented letters so diacritic-bearing stop-words still match.
func tokenizeWords(textLower string) []string {
	return strings.FieldsFunc(textLower, func(r rune) bool {
		return !unicode.IsLetter(r)
	})
}

// Whole-word stop-word sets. Single-character function words are omitted on
// purpose: matching them as substrings (or even whole tokens) creates too many
// false positives for short text.
var (
	englishStopWords = toSet([]string{
		"the", "be", "to", "of", "and", "in", "that", "have", "it", "for",
		"not", "on", "with", "he", "as", "you", "do", "at", "this", "but",
		"his", "by", "from", "they", "we", "say", "her", "she", "will",
		"your", "click", "here", "account", "bank", "won", "prize", "now",
		"new", "number", "urgent", "suspended", "verify", "please", "is", "has",
	})
	spanishStopWords = toSet([]string{
		"el", "la", "los", "las", "del", "que", "una", "por", "con", "está",
		"para", "como", "pero", "más", "este", "esta", "son", "muy", "todo",
		"hola", "gracias", "usted", "su", "se",
	})
	frenchStopWords = toSet([]string{
		"le", "les", "des", "une", "est", "dans", "pour", "avec", "ce", "vous",
		"nous", "qui", "que", "pas", "sur", "mais", "votre", "bonjour", "merci",
		"cliquez", "ici", "compte",
	})
	germanStopWords = toSet([]string{
		"der", "die", "das", "und", "ist", "ein", "eine", "nicht", "mit",
		"auf", "ich", "sie", "sind", "wird", "haben", "für", "konto", "bitte",
		"hallo", "danke",
	})
	portugueseStopWords = toSet([]string{
		"que", "em", "do", "da", "com", "não", "uma", "os", "as", "dos",
		"das", "para", "como", "mas", "mais", "este", "esta", "são", "você",
		"sua", "seu", "obrigado", "olá", "clique", "aqui", "conta", "banco",
	})
	italianStopWords = toSet([]string{
		"il", "di", "che", "è", "la", "un", "una", "per", "non", "sono",
		"con", "del", "della", "questo", "questa", "ciao", "grazie",
	})
	dutchStopWords = toSet([]string{
		"de", "het", "een", "van", "en", "is", "dat", "op", "te", "niet",
		"met", "ij", "zijn", "voor", "maar", "hallo", "bedankt",
	})
)

// toSet builds a set from a slice of strings for O(1) membership checks.
func toSet(items []string) map[string]struct{} {
	set := make(map[string]struct{}, len(items))
	for _, it := range items {
		set[it] = struct{}{}
	}
	return set
}

// GetLanguageInfo returns information about a language code
func (d *LanguageDetector) GetLanguageInfo(code string) *SupportedLanguage {
	languages := map[string]SupportedLanguage{
		"en": LanguageEnglish,
		"ar": LanguageArabic,
		"fa": LanguagePersian,
		"hi": LanguageHindi,
		"ur": LanguageUrdu,
		"zh": LanguageChinese,
		"ru": LanguageRussian,
		"es": LanguageSpanish,
		"fr": LanguageFrench,
		"de": LanguageGerman,
	}

	if lang, exists := languages[code]; exists {
		return &lang
	}
	return nil
}

// IsRTL returns whether a language is right-to-left
func (d *LanguageDetector) IsRTL(code string) bool {
	rtlLanguages := map[string]bool{
		"ar": true,
		"fa": true,
		"ur": true,
		"he": true,
	}
	return rtlLanguages[code]
}

// GetSupportedLanguages returns all supported languages
func (d *LanguageDetector) GetSupportedLanguages() []SupportedLanguage {
	return []SupportedLanguage{
		LanguageEnglish,
		LanguageArabic,
		LanguagePersian,
		LanguageHindi,
		LanguageUrdu,
		LanguageChinese,
		LanguageRussian,
		LanguageSpanish,
		LanguageFrench,
		LanguageGerman,
	}
}

// NormalizeText normalizes text for a specific language
func (d *LanguageDetector) NormalizeText(text, langCode string) string {
	// Basic normalization
	text = strings.TrimSpace(text)

	switch langCode {
	case "ar", "fa", "ur":
		// Arabic/Persian/Urdu normalization
		text = d.normalizeArabicText(text)
	case "zh":
		// Chinese normalization (e.g., full-width to half-width)
		text = d.normalizeChineseText(text)
	}

	return text
}

// normalizeArabicText normalizes Arabic/Persian/Urdu text
func (d *LanguageDetector) normalizeArabicText(text string) string {
	// Normalize Arabic characters
	replacements := map[rune]rune{
		'أ': 'ا', // Alef with Hamza above -> Alef
		'إ': 'ا', // Alef with Hamza below -> Alef
		'آ': 'ا', // Alef with Madda -> Alef
		'ؤ': 'و', // Waw with Hamza -> Waw
		'ئ': 'ي', // Yeh with Hamza -> Yeh
		'ة': 'ه', // Teh Marbuta -> Heh
		'ى': 'ي', // Alef Maksura -> Yeh
	}

	var result strings.Builder
	for _, r := range text {
		if replacement, exists := replacements[r]; exists {
			result.WriteRune(replacement)
		} else {
			result.WriteRune(r)
		}
	}

	return result.String()
}

// normalizeChineseText normalizes Chinese text
func (d *LanguageDetector) normalizeChineseText(text string) string {
	// Convert full-width characters to half-width
	var result strings.Builder
	for _, r := range text {
		// Full-width ASCII variants (FF01-FF5E) to ASCII (0021-007E)
		if r >= 0xFF01 && r <= 0xFF5E {
			result.WriteRune(r - 0xFEE0)
		} else if r == 0x3000 { // Full-width space
			result.WriteRune(' ')
		} else {
			result.WriteRune(r)
		}
	}
	return result.String()
}
