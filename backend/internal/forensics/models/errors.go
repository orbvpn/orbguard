package models

import "errors"

// ErrNothingExamined means an analysis recognised nothing in the artifact it
// was given, or was given none. It must never be answered as a clean result.
var ErrNothingExamined = errors.New("no forensic artifact was examined")
