package models

import (
	"errors"
	"fmt"
)

// ErrNothingExamined means an analysis recognised nothing in the artifact it
// was given, or was given none. It must never be answered as a clean result.
var ErrNothingExamined = errors.New("no forensic artifact was examined")

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
