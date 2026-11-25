// Package safezip opens zip archives with a bound on what their directory may
// cost, because archive/zip reads the whole directory before a caller can look
// at a single entry.
package safezip

import (
	"archive/zip"
	"errors"
	"io"
	"os"
	"sync/atomic"

	"orbguard-lab/internal/forensics/models"
)

const (
	// MaxDirectoryBytes fits 20000 entries with paths of about 350 characters.
	MaxDirectoryBytes = 8 << 20
	// MaxBackupDirectoryBytes fits a device backup of about 250000 files.
	MaxBackupDirectoryBytes = 32 << 20
	// maxDirectoryBytesInFlight caps directory bytes held across all uploads.
	// A record of 46 bytes takes about 200 bytes of heap, so this keeps the
	// total near 300 MiB.
	maxDirectoryBytesInFlight = 64 << 20
)

// ErrDirectoryTooLarge means the archive's directory is over the limit.
var ErrDirectoryTooLarge = errors.New("zip directory is over the limit")

var directoryBytesInFlight atomic.Int64

// Reader is an open archive. Close releases its share of the shared budget.
type Reader struct {
	*zip.Reader
	file *os.File
	held int64
}

// Open reads the archive's directory, reading at most maxDirectoryBytes. It
// returns ErrDirectoryTooLarge over that limit and models.ErrAnalysisBusy when
// other uploads hold the shared budget.
func Open(path string, maxDirectoryBytes int64) (*Reader, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	info, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, err
	}

	if directoryBytesInFlight.Add(maxDirectoryBytes) > maxDirectoryBytesInFlight {
		directoryBytesInFlight.Add(-maxDirectoryBytes)
		f.Close()
		return nil, models.ErrAnalysisBusy
	}

	bounded := &boundedReaderAt{r: f, limit: maxDirectoryBytes}
	zr, err := zip.NewReader(bounded, info.Size())
	if err != nil || bounded.over {
		directoryBytesInFlight.Add(-maxDirectoryBytes)
		f.Close()
		if bounded.over {
			return nil, ErrDirectoryTooLarge
		}
		return nil, err
	}

	// Keep only what this directory used, and lift the limit for entry data.
	held := bounded.read
	directoryBytesInFlight.Add(held - maxDirectoryBytes)
	bounded.limit = 0
	return &Reader{Reader: zr, file: f, held: held}, nil
}

// Close closes the archive and releases its share of the budget.
func (r *Reader) Close() error {
	directoryBytesInFlight.Add(-r.held)
	return r.file.Close()
}

// boundedReaderAt fails once more than limit bytes were asked for. A limit of
// zero means no limit.
type boundedReaderAt struct {
	r     io.ReaderAt
	limit int64
	read  int64
	over  bool
}

func (b *boundedReaderAt) ReadAt(p []byte, off int64) (int, error) {
	if b.limit > 0 {
		b.read += int64(len(p))
		if b.read > b.limit {
			b.over = true
			return 0, ErrDirectoryTooLarge
		}
	}
	return b.r.ReadAt(p, off)
}
