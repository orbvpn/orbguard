package models

import (
	"strings"
	"testing"
)

func TestIndicatorURLHostAccepts(t *testing.T) {
	for raw, want := range map[string]string{
		"http://bad.example/a":          "bad.example",
		"https://BAD.Example:8443/x":    "bad.example",
		"http://bad.example./x":         "bad.example",
		"http://bad.example//bin/x.sh":  "bad.example",
		"http://bad.example?a=//b.test": "bad.example",
		"http://foo_bar.example/":       "foo_bar.example",
		"http://203.0.113.9:8080/b":     "203.0.113.9",
		"http://[2001:db8::1]:80/x":     "2001:db8::1",
	} {
		got, ok := IndicatorURLHost(raw)
		if !ok || got != want {
			t.Errorf("IndicatorURLHost(%q) = %q, %v; want %q", raw, got, ok, want)
		}
	}
}

func TestIndicatorURLHostRejects(t *testing.T) {
	for _, raw := range []string{
		"",
		"bad.example/x",
		"//bad.example/x",
		"http:bad.example/x",
		"HTTP://bad.example/x",
		"ftp://bad.example/x",
		"http://https://github.com/x",
		"https://http://github.com/x",
		"http://https:/github.com/x",
		"http://evil.example:/x",
		"http://evil.example://github.com/x",
		"http:////github.com/x",
		"http:///x",
		"http://u@bad.example/x",
		"http://good.example:80@bad.example/x",
		`http://bad.example\@good.example/x`,
		`http://bad.example/a\b`,
		"http://bad .example/x",
		"http://bad\t.example/x",
		"http://localhost/x",
		"http://github.com../x",
		"http://.github.com/x",
		"http://bad..example/x",
		"http://bücher.example/x",
		"http://facebooK.com/x",
		"http://%67ithub.com/x",
		"http://bad.example%2f/x",
		"http://0177.0.0.1/x",
		"http://1.2.3/x",
		"http://[fe80::1%25en0]/x",
		"https://80:::1",
		"https://::ffff:192.0.2.1:804430",
		"http://2001:db8::1/x",
		"http://2001:db8::1:80/x",
		"http://" + strings.Repeat("a", 64) + ".example/x",
		"http://" + strings.Repeat("a.", 130) + "example/x",
	} {
		if got, ok := IndicatorURLHost(raw); ok {
			t.Errorf("IndicatorURLHost(%q) accepted as %q", raw, got)
		}
	}
}

// net/url accepted these bracket forms in some Go 1.24 releases and refuses
// them in later ones. The result must not depend on the toolchain.
func TestIndicatorURLHostRefusesMalformedBrackets(t *testing.T) {
	for _, raw := range []string{
		"http://[www.github.com]",
		"http://[0github.com]/x",
		"https://[GitHub.COM]",
		"http://[192.0.2.1]/x",
		"http://a[::1]",
		"http://0[::]",
		"http://8080[2001:db8::1]/x",
		"https://;[2001:db8::1]?x",
		"https://%40kK[2001:db8::1]",
		"http://[2001:db8::1]x/",
		"http://[2001:db8::1]:x/",
		"http://[2001:db8::1]]/",
		"http://[[2001:db8::1]/",
		"http://[fe80::1%25en0]/",
	} {
		if host, ok := IndicatorURLHost(raw); ok {
			t.Errorf("IndicatorURLHost(%q) accepted host %q", raw, host)
		}
	}
	for raw, want := range map[string]string{
		"http://[2001:db8::1]/x":      "2001:db8::1",
		"http://[2001:db8::1]:8080/x": "2001:db8::1",
		"https://[2001:DB8::2]":       "2001:db8::2",
	} {
		if host, ok := IndicatorURLHost(raw); !ok || host != want {
			t.Errorf("IndicatorURLHost(%q) = %q, %v, want %q", raw, host, ok, want)
		}
	}
}
