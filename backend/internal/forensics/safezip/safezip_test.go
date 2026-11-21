package safezip

import (
	"archive/zip"
	"bytes"
	"encoding/binary"
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"

	"orbguard-lab/internal/forensics/models"
)

func writeTemp(t *testing.T, content []byte) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "a.zip")
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

// recordsZip declares declared records and holds n of them.
func recordsZip(n, declared int) []byte {
	var b bytes.Buffer
	local := make([]byte, 30)
	binary.LittleEndian.PutUint32(local, 0x04034b50)
	binary.LittleEndian.PutUint16(local[26:], 1)
	b.Write(local)
	b.WriteByte('a')
	start := b.Len()
	record := make([]byte, 47)
	binary.LittleEndian.PutUint32(record, 0x02014b50)
	binary.LittleEndian.PutUint16(record[28:], 1)
	record[46] = 'a'
	for i := 0; i < n; i++ {
		b.Write(record)
	}
	end := make([]byte, 22)
	binary.LittleEndian.PutUint32(end, 0x06054b50)
	binary.LittleEndian.PutUint16(end[8:], uint16(declared))
	binary.LittleEndian.PutUint16(end[10:], uint16(declared))
	binary.LittleEndian.PutUint32(end[12:], uint32(b.Len()-start))
	binary.LittleEndian.PutUint32(end[16:], uint32(start))
	b.Write(end)
	return b.Bytes()
}

func TestDirectoryOverTheLimitIsRefused(t *testing.T) {
	for name, content := range map[string][]byte{
		"honest count":                       recordsZip(70_000, 70_000),
		"count short by a multiple of 65536": recordsZip(65_536+5, 5),
	} {
		t.Run(name, func(t *testing.T) {
			_, err := Open(writeTemp(t, content), 1<<20)
			if !errors.Is(err, ErrDirectoryTooLarge) {
				t.Fatalf("want the directory refused, got %v", err)
			}
			if got := directoryBytesInFlight.Load(); got != 0 {
				t.Fatalf("budget not released: %d", got)
			}
		})
	}
}

func TestDirectoryUnderTheLimitOpensAndEntriesAreNotLimited(t *testing.T) {
	var b bytes.Buffer
	zw := zip.NewWriter(&b)
	w, err := zw.CreateHeader(&zip.FileHeader{Name: "big.bin", Method: zip.Store})
	if err != nil {
		t.Fatal(err)
	}
	payload := bytes.Repeat([]byte("x"), 300*1024)
	if _, err := w.Write(payload); err != nil {
		t.Fatal(err)
	}
	zw.Close()

	const limit = 128 * 1024
	r, err := Open(writeTemp(t, b.Bytes()), limit)
	if err != nil {
		t.Fatal(err)
	}
	if held := directoryBytesInFlight.Load(); held <= 0 || held >= limit {
		t.Fatalf("an open archive holds only what its directory used, got %d", held)
	}
	rc, err := r.File[0].Open()
	if err != nil {
		t.Fatal(err)
	}
	got, err := io.ReadAll(rc)
	rc.Close()
	if err != nil || !bytes.Equal(got, payload) {
		t.Fatalf("entry data must not be limited: %d bytes, %v", len(got), err)
	}
	if err := r.Close(); err != nil {
		t.Fatal(err)
	}
	if got := directoryBytesInFlight.Load(); got != 0 {
		t.Fatalf("budget not released: %d", got)
	}
}

func TestSharedBudget(t *testing.T) {
	path := writeTemp(t, recordsZip(3, 3))
	directoryBytesInFlight.Store(maxDirectoryBytesInFlight - MaxDirectoryBytes + 1)
	defer directoryBytesInFlight.Store(0)
	if _, err := Open(path, MaxDirectoryBytes); !errors.Is(err, models.ErrAnalysisBusy) {
		t.Fatalf("want busy, got %v", err)
	}
	if got := directoryBytesInFlight.Load(); got != maxDirectoryBytesInFlight-MaxDirectoryBytes+1 {
		t.Fatalf("a refused open must release its reservation: %d", got)
	}

	directoryBytesInFlight.Store(maxDirectoryBytesInFlight - MaxDirectoryBytes)
	r, err := Open(path, MaxDirectoryBytes)
	if err != nil {
		t.Fatalf("exactly at the budget must open: %v", err)
	}
	r.Close()
}

func TestBrokenArchiveReleasesItsReservation(t *testing.T) {
	if _, err := Open(writeTemp(t, []byte("not a zip file")), MaxDirectoryBytes); err == nil || errors.Is(err, ErrDirectoryTooLarge) {
		t.Fatalf("want the format error, got %v", err)
	}
	if got := directoryBytesInFlight.Load(); got != 0 {
		t.Fatalf("budget not released: %d", got)
	}
}
