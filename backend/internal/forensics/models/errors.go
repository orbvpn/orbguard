package models

import (
	"errors"
	"fmt"
)

// ErrNothingExamined means an analysis recognised nothing in the artifact it
// was given, or was given none. It must never be answered as a clean result.
var ErrNothingExamined = errors.New("no forensic artifact was examined")

// ErrAnalysisBusy means the server is at its limit for analyses running at
// once. The artifact may be fine, so sending it again later can succeed.
var ErrAnalysisBusy = errors.New("forensic analysis capacity is in use")

// MinLogEntries is the fewest entries that count as having read a log.
const MinLogEntries = 3

// PartlyExaminedError means part of what was supplied could not be examined
// and nothing was found in the rest, so the result is not an all-clear.
type PartlyExaminedError struct {
	NotExamined []string
}

func (e *PartlyExaminedError) Error() string {
	return fmt.Sprintf("%d supplied item(s) could not be examined", len(e.NotExamined))
}

// RecognisedEnough reports whether recognised lines are a large enough share
// of a log's non-blank lines to call the log read. Real logs are almost wholly
// entry, header and status lines, so one in ten unread lines means the format
// is not the one this parser reads.
func RecognisedEnough(recognised, total int) bool {
	return total > 0 && recognised*10 >= total*9
}
