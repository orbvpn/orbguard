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
