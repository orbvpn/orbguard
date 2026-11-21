package models

import (
	"net"
	"net/url"
	"strings"
)

const (
	maxHostLength  = 253
	maxLabelLength = 63
)

// IndicatorURLHost returns the lower-case host of an http(s) URL from a feed
// whose rows are treated as hostile. It decides which URLhaus rows are usable.
// It is deliberately strict: for example http://https://github.com/x has the
// authority "https:" to net/url, while stripping scheme prefixes one after
// another yields github.com, so that row is refused.
//
// ok is false for anything but a plain scheme, a clean authority and a public
// looking name or IP literal: other schemes, user info, an empty port, control
// characters, backslashes, non-ASCII or single-label names, empty labels, and
// numeric names that are not valid IP addresses.
func IndicatorURLHost(raw string) (host string, ok bool) {
	if !strings.HasPrefix(raw, "http://") && !strings.HasPrefix(raw, "https://") {
		return "", false
	}
	for i := 0; i < len(raw); i++ {
		if c := raw[i]; c <= ' ' || c == 0x7f || c == '\\' {
			return "", false
		}
	}

	parsed, err := url.Parse(raw)
	if err != nil || parsed.Opaque != "" || parsed.User != nil || parsed.Host == "" {
		return "", false
	}
	if strings.HasSuffix(parsed.Host, ":") {
		return "", false
	}

	name := parsed.Hostname()
	if ip := net.ParseIP(name); ip != nil {
		return ip.String(), true
	}
	return validHostName(name)
}

func validHostName(name string) (string, bool) {
	// Checked before lower-casing: strings.ToLower maps some non-ASCII runes,
	// such as the Kelvin sign, onto ASCII letters.
	for i := 0; i < len(name); i++ {
		if name[i] >= 0x80 {
			return "", false
		}
	}

	name = strings.TrimSuffix(strings.ToLower(name), ".")
	if len(name) == 0 || len(name) > maxHostLength {
		return "", false
	}
	labels := strings.Split(name, ".")
	if len(labels) < 2 {
		return "", false
	}
	for _, label := range labels {
		if len(label) == 0 || len(label) > maxLabelLength {
			return "", false
		}
		for i := 0; i < len(label); i++ {
			c := label[i]
			if (c < 'a' || c > 'z') && (c < '0' || c > '9') && c != '-' && c != '_' {
				return "", false
			}
		}
	}

	last := labels[len(labels)-1]
	if strings.Trim(last, "0123456789") == "" {
		return "", false
	}
	return name, true
}
