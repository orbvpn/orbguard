package android

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"io"
)

// maxLogcatLineBytes is how much of one line is kept for parsing. A logcat
// entry is far shorter: the logger caps a message near 4 KiB. A bug report's
// other sections hold longer lines (one from an emulator ran to 388 KiB), and
// those are read past in pieces of this size rather than held whole.
const maxLogcatLineBytes = 64 * 1024

// spywareNameOverlap is how much of the end of one piece of a cut line is
// looked at again with the next piece, so a name split across two pieces is
// still seen. It is longer than the longest name in logcatSpywareNames.
const spywareNameOverlap = 16

// logLine is one line as it was read. A line longer than maxLogcatLineBytes
// keeps only its first piece in text, is marked cut, and says whether a known
// spyware name was in the part that was not kept.
type logLine struct {
	text          string
	cut           bool
	nameInCutPart bool
}

// logLineReader reads lines of any length while holding at most
// maxLogcatLineBytes of one at a time.
type logLineReader struct {
	r *bufio.Reader
}

func newLogLineReader(r io.Reader) *logLineReader {
	return &logLineReader{r: bufio.NewReaderSize(r, maxLogcatLineBytes)}
}

// next reads one line, without its line ending. It answers io.EOF once the
// stream is done, the stream's own error when it broke, and ctx's error when
// ctx ended while a long line was being read past. A line the stream broke
// in the middle of is not returned.
func (l *logLineReader) next(ctx context.Context) (logLine, error) {
	piece, err := l.r.ReadSlice('\n')
	if !errors.Is(err, bufio.ErrBufferFull) {
		if len(piece) == 0 {
			return logLine{}, err
		}
		if err != nil && !errors.Is(err, io.EOF) {
			return logLine{}, err
		}
		// A last line without a line ending still counts.
		return logLine{text: string(trimLineEnd(piece))}, nil
	}

	line := logLine{text: string(piece), cut: true}
	tail := lastBytes(nil, piece, spywareNameOverlap)
	for errors.Is(err, bufio.ErrBufferFull) {
		if ctx.Err() != nil {
			return logLine{}, ctx.Err()
		}
		piece, err = l.r.ReadSlice('\n')
		window := append(tail, piece...)
		if !line.nameInCutPart && holdsSpywareName(string(window)) {
			line.nameInCutPart = true
		}
		tail = lastBytes(nil, window, spywareNameOverlap)
	}
	if err != nil && !errors.Is(err, io.EOF) {
		return logLine{}, err
	}
	return line, nil
}

// lastBytes appends the last n bytes of b to dst.
func lastBytes(dst, b []byte, n int) []byte {
	if len(b) > n {
		b = b[len(b)-n:]
	}
	return append(dst, b...)
}

// trimLineEnd drops a trailing "\n" and then one "\r", as bufio.ScanLines does.
func trimLineEnd(b []byte) []byte {
	b = bytes.TrimSuffix(b, []byte("\n"))
	return bytes.TrimSuffix(b, []byte("\r"))
}
