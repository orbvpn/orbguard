package ai

import (
	"testing"

	"orbguard-lab/pkg/logger"
)

func newTestDetector(t *testing.T) *LanguageDetector {
	t.Helper()
	return NewLanguageDetector(logger.NewDevelopment())
}

// TestDetect_ShortEnglishStaysEnglish guards the live regression where short
// English phishing text was misclassified as Portuguese (and the LLM was then
// told to answer in Portuguese). Short English must never flip to pt/es.
func TestDetect_ShortEnglishStaysEnglish(t *testing.T) {
	d := newTestDetector(t)

	cases := []string{
		"URGENT bank account suspended click here",
		"you won a prize",
		"hi mom new number",
		"Your package could not be delivered, click the link to reschedule",
		"Verify your account now or it will be closed",
		"Congratulations! You have been selected for a reward.",
	}

	for _, text := range cases {
		got := d.Detect(text)
		if got == "pt" || got == "es" {
			t.Errorf("Detect(%q) = %q; short English text must not flip to pt/es", text, got)
		}
		if got != "en" {
			t.Errorf("Detect(%q) = %q; want en", text, got)
		}
	}
}

// TestDetect_ClearPortuguese ensures genuine multi-language support survives:
// a clearly Portuguese sentence still detects pt.
func TestDetect_ClearPortuguese(t *testing.T) {
	d := newTestDetector(t)

	cases := []string{
		"Olá, a sua conta no banco foi suspensa, por favor clique aqui para verificar os seus dados agora.",
		"Você ganhou um prémio, mas precisa confirmar os seus dados pessoais para receber o pagamento.",
	}

	for _, text := range cases {
		if got := d.Detect(text); got != "pt" {
			t.Errorf("Detect(%q) = %q; want pt", text, got)
		}
	}
}

// TestDetect_ClearSpanish ensures clearly Spanish text detects es.
func TestDetect_ClearSpanish(t *testing.T) {
	d := newTestDetector(t)

	text := "Hola, su cuenta del banco ha sido suspendida, por favor haga clic aquí para verificar sus datos ahora."
	if got := d.Detect(text); got != "es" {
		t.Errorf("Detect(%q) = %q; want es", text, got)
	}
}

// TestDetect_ClearPersian ensures a clearly Persian sentence still detects fa.
func TestDetect_ClearPersian(t *testing.T) {
	d := newTestDetector(t)

	cases := []string{
		"سلام، حساب بانکی شما مسدود شده است، لطفا برای تایید اطلاعات خود اینجا کلیک کنید.",
		"این پیام مهم است و شما باید همین الان اقدام کنید.",
	}

	for _, text := range cases {
		if got := d.Detect(text); got != "fa" {
			t.Errorf("Detect(%q) = %q; want fa", text, got)
		}
	}
}

// TestDetect_EmptyDefaultsEnglish covers the trivial empty/whitespace case.
func TestDetect_EmptyDefaultsEnglish(t *testing.T) {
	d := newTestDetector(t)

	for _, text := range []string{"", "   ", "123 456"} {
		if got := d.Detect(text); got != "en" {
			t.Errorf("Detect(%q) = %q; want en", text, got)
		}
	}
}

// TestDetect_LongEnglishStaysEnglish ensures longer English passages with words
// that overlap foreign stop-words (e.g. "as", "is") still resolve to English.
func TestDetect_LongEnglishStaysEnglish(t *testing.T) {
	d := newTestDetector(t)

	text := "This is a long message from your bank. We have detected suspicious activity on your account and you must verify your identity by clicking the link below as soon as possible."
	if got := d.Detect(text); got != "en" {
		t.Errorf("Detect(%q) = %q; want en", text, got)
	}
}
