package android

import (
	"strings"
	"testing"

	"github.com/rs/zerolog"

	"orbguard-lab/pkg/logger"
)

func TestBannersAloneAreNotALogcat(t *testing.T) {
	p := NewLogcatParser(&logger.Logger{Logger: zerolog.Nop()})
	banner := "--------- beginning of main\n"
	if p.Recognises([]byte(strings.Repeat(banner, 5))) {
		t.Fatal("banners alone must not read as a logcat")
	}
	if !p.Recognises([]byte(banner + strings.Repeat("11-21 08:12:33.123  1234  5678 I Agent: started\n", 3))) {
		t.Fatal("a banner and an entry read as a logcat")
	}
}
