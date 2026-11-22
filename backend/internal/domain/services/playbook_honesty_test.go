package services

import (
	"context"
	"strings"
	"testing"

	"github.com/rs/zerolog"

	"orbguard-lab/internal/domain/models"
	"orbguard-lab/pkg/logger"
)

func TestNoPlaybookActionClaimsSuccess(t *testing.T) {
	log := &logger.Logger{Logger: zerolog.Nop()}
	svc := NewPlaybookService(nil, nil, log, &PlaybookServiceConfig{WorkerCount: 1, QueueSize: 1})
	t.Cleanup(svc.Stop)

	if len(svc.actionHandlers) == 0 {
		t.Fatal("no action handlers registered")
	}
	for actionType := range svc.actionHandlers {
		for _, continueOnError := range []bool{false, true} {
			playbook := &models.Playbook{
				Name:     "honesty " + string(actionType),
				Enabled:  true,
				Triggers: []models.PlaybookTrigger{{Type: models.TriggerTypeManual}},
				Actions: []models.PlaybookAction{{
					ID: "a1", Name: "a1", Type: actionType, ContinueOnError: continueOnError,
				}},
			}
			if err := svc.RegisterPlaybook(context.Background(), playbook); err != nil {
				t.Fatalf("%s: register: %v", actionType, err)
			}
			execution, err := svc.TriggerManually(context.Background(), playbook.ID, nil)
			if err != nil {
				t.Fatalf("%s: run: %v", actionType, err)
			}
			if execution.Status != models.ExecutionStatusFailed {
				t.Fatalf("%s (continue_on_error=%v): run status %q, want failed", actionType, continueOnError, execution.Status)
			}
			if !strings.Contains(execution.Error, "not implemented") {
				t.Fatalf("%s: run error %q does not say not implemented", actionType, execution.Error)
			}
			if len(execution.ActionResults) != 1 || execution.ActionResults[0].Status != models.ExecutionStatusFailed {
				t.Fatalf("%s: action results %+v", actionType, execution.ActionResults)
			}
			if len(execution.OutputData) != 0 {
				t.Fatalf("%s: a skipped action produced output %v", actionType, execution.OutputData)
			}
		}
	}
}
