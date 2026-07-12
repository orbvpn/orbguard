package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"orbguard-lab/internal/infrastructure/cache"
	"orbguard-lab/internal/infrastructure/database/repository"
	"orbguard-lab/pkg/logger"
)

// AlertsHandler handles alert endpoints
type AlertsHandler struct {
	repos  *repository.Repositories
	cache  *cache.RedisCache
	logger *logger.Logger
}

// NewAlertsHandler creates a new AlertsHandler
func NewAlertsHandler(repos *repository.Repositories, c *cache.RedisCache, log *logger.Logger) *AlertsHandler {
	return &AlertsHandler{
		repos:  repos,
		cache:  c,
		logger: log.WithComponent("alerts-handler"),
	}
}

// alertItem represents a security alert
type alertItem struct {
	ID          string                 `json:"id"`
	Title       string                 `json:"title"`
	Description string                 `json:"description"`
	Severity    string                 `json:"severity"`
	Category    string                 `json:"category"`
	Source      string                 `json:"source"`
	IsRead      bool                   `json:"is_read"`
	CreatedAt   time.Time              `json:"created_at"`
	ReadAt      *time.Time             `json:"read_at,omitempty"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// List handles GET /api/v1/alerts
func (h *AlertsHandler) List(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page < 1 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	severity := r.URL.Query().Get("severity")
	unreadOnly := r.URL.Query().Get("unread") == "true"

	// Try cache
	var alerts []alertItem
	_ = h.cache.GetJSON(r.Context(), "alerts:list", &alerts)
	if alerts == nil {
		alerts = []alertItem{}
	}

	// Filter
	var filtered []alertItem
	for _, a := range alerts {
		if severity != "" && a.Severity != severity {
			continue
		}
		if unreadOnly && a.IsRead {
			continue
		}
		filtered = append(filtered, a)
	}
	if filtered == nil {
		filtered = []alertItem{}
	}

	unread := 0
	for _, a := range alerts {
		if !a.IsRead {
			unread++
		}
	}

	total := len(filtered)
	start := (page - 1) * pageSize
	end := start + pageSize
	if start > total {
		start = total
	}
	if end > total {
		end = total
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"alerts":    filtered[start:end],
		"total":     total,
		"unread":    unread,
		"page":      page,
		"page_size": pageSize,
	})
}

// MarkRead handles POST /api/v1/alerts/{id}/read
func (h *AlertsHandler) MarkRead(w http.ResponseWriter, r *http.Request) {
	alertID := chi.URLParam(r, "id")
	if alertID == "" {
		http.Error(w, `{"error":"alert ID is required"}`, http.StatusBadRequest)
		return
	}

	_ = h.cache.SetJSON(r.Context(), "alerts:read:"+alertID, map[string]interface{}{
		"read_at": time.Now().UTC().Format(time.RFC3339),
	}, 30*24*time.Hour)

	h.logger.Info().Str("alert_id", alertID).Msg("alert marked as read")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":      alertID,
		"is_read": true,
		"read_at": time.Now().UTC().Format(time.RFC3339),
	})
}

// Clear handles DELETE /api/v1/alerts
func (h *AlertsHandler) Clear(w http.ResponseWriter, r *http.Request) {
	_ = h.cache.Delete(r.Context(), "alerts:list")
	h.logger.Info().Msg("all alerts cleared")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":    "All alerts cleared",
		"cleared_at": time.Now().UTC().Format(time.RFC3339),
	})
}

// GetDashboard handles GET /api/v1/stats/dashboard
func (h *AlertsHandler) GetDashboard(w http.ResponseWriter, r *http.Request) {
	var dashboard map[string]interface{}
	err := h.cache.GetJSON(r.Context(), "stats:dashboard", &dashboard)
	if err != nil {
		now := time.Now()
		trend := make([]map[string]interface{}, 7)
		for i := 6; i >= 0; i-- {
			date := now.AddDate(0, 0, -i)
			trend[6-i] = map[string]interface{}{
				"date": date.Format("2006-01-02"),
				"count": 0, "critical": 0, "high": 0, "medium": 0, "low": 0,
			}
		}
		dashboard = map[string]interface{}{
			"threat_score":      85.0,
			"protection_grade":  "B",
			"active_threats":    0,
			"resolved_today":    0,
			"unread_alerts":     0,
			"recent_alerts":     []interface{}{},
			"threat_trend":      trend,
			"protection_status": map[string]bool{"sms": true, "web": true, "app": true, "network": true, "vpn": false},
			"last_scan":         now,
		}
		_ = h.cache.SetJSON(r.Context(), "stats:dashboard", dashboard, 1*time.Minute)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(dashboard)
}
