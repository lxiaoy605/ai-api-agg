package workgroup

import (
	"database/sql"
	"strconv"
	"time"

	"github.com/ai-api-agg/backend/internal/audit"
	"github.com/ai-api-agg/backend/internal/middleware"
	"github.com/gin-gonic/gin"
)

type Handler struct {
	db *sql.DB
}

func NewHandler(db *sql.DB) *Handler {
	return &Handler{db: db}
}

type Workgroup struct {
	ID          int64  `json:"id"`
	UserID      int64  `json:"user_id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	KeyCount    int    `json:"key_count"`
	CreatedAt   int64  `json:"created_at"`
}

type CreateReq struct {
	Name        string `json:"name" binding:"required"`
	Description string `json:"description"`
}

type UpdateReq struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

func (h *Handler) List(c *gin.Context) {
	userID := c.GetInt64("user_id")

	rows, err := h.db.Query(
		`SELECT w.id, w.user_id, w.name, w.description, w.created_at,
		        (SELECT COUNT(*) FROM api_keys k WHERE k.workgroup_id = w.id) as key_count
		 FROM workgroups w WHERE w.user_id = ? ORDER BY w.id ASC`,
		userID,
	)
	if err != nil {
		middleware.InternalError(c, "Failed to list workgroups")
		return
	}
	defer rows.Close()

	groups := make([]Workgroup, 0)
	for rows.Next() {
		var g Workgroup
		if err := rows.Scan(&g.ID, &g.UserID, &g.Name, &g.Description, &g.CreatedAt, &g.KeyCount); err != nil {
			middleware.InternalError(c, "Failed to read workgroup data")
			return
		}
		groups = append(groups, g)
	}

	middleware.Success(c, groups)
}

func (h *Handler) Create(c *gin.Context) {
	userID := c.GetInt64("user_id")

	var req CreateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "Workgroup name is required")
		return
	}

	var existingID int64
	err := h.db.QueryRow("SELECT id FROM workgroups WHERE user_id = ? AND name = ?", userID, req.Name).Scan(&existingID)
	if err == nil {
		middleware.BadRequest(c, "Workgroup name already exists")
		return
	}

	now := time.Now().Unix()
	result, err := h.db.Exec(
		"INSERT INTO workgroups (user_id, name, description, created_at) VALUES (?, ?, ?, ?)",
		userID, req.Name, req.Description, now,
	)
	if err != nil {
		middleware.InternalError(c, "Failed to create workgroup")
		return
	}

	wgID, _ := result.LastInsertId()

	actor := "user:" + strconv.FormatInt(userID, 10)
	audit.Log(h.db, "workgroup.create", actor, "wg:"+strconv.FormatInt(wgID, 10),
		"name:"+req.Name, c.ClientIP())

	middleware.Success(c, Workgroup{
		ID:          wgID,
		UserID:      userID,
		Name:        req.Name,
		Description: req.Description,
		CreatedAt:   now,
	})
}

func (h *Handler) Update(c *gin.Context) {
	userID := c.GetInt64("user_id")
	wgID := c.Param("id")

	var ownerID int64
	err := h.db.QueryRow("SELECT user_id FROM workgroups WHERE id = ?", wgID).Scan(&ownerID)
	if err == sql.ErrNoRows {
		middleware.NotFound(c, "Workgroup not found")
		return
	}
	if err != nil {
		middleware.InternalError(c, "Failed to query workgroup")
		return
	}
	if ownerID != userID {
		middleware.NotFound(c, "Workgroup not found")
		return
	}

	var req UpdateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		middleware.BadRequest(c, "Invalid request format")
		return
	}

	if req.Name != "" {
		if _, err := h.db.Exec("UPDATE workgroups SET name = ? WHERE id = ?", req.Name, wgID); err != nil {
			middleware.InternalError(c, "Failed to update workgroup name")
			return
		}
	}
	if req.Description != "" {
		if _, err := h.db.Exec("UPDATE workgroups SET description = ? WHERE id = ?", req.Description, wgID); err != nil {
			middleware.InternalError(c, "Failed to update workgroup description")
			return
		}
	}

	actor := "user:" + strconv.FormatInt(userID, 10)
	audit.Log(h.db, "workgroup.update", actor, "wg:"+wgID, "name:"+req.Name, c.ClientIP())

	middleware.Success(c, gin.H{"updated": true})
}

func (h *Handler) Delete(c *gin.Context) {
	userID := c.GetInt64("user_id")
	wgID := c.Param("id")

	var ownerID int64
	err := h.db.QueryRow("SELECT user_id FROM workgroups WHERE id = ?", wgID).Scan(&ownerID)
	if err == sql.ErrNoRows {
		middleware.NotFound(c, "Workgroup not found")
		return
	}
	if err != nil {
		middleware.InternalError(c, "Failed to query workgroup")
		return
	}
	if ownerID != userID {
		middleware.NotFound(c, "Workgroup not found")
		return
	}

	var keyCount int
	if err := h.db.QueryRow("SELECT COUNT(*) FROM api_keys WHERE workgroup_id = ?", wgID).Scan(&keyCount); err == nil && keyCount > 0 {
		middleware.BadRequest(c, "Workgroup still has API keys. Remove or transfer keys first.")
		return
	}

	if _, err := h.db.Exec("DELETE FROM workgroups WHERE id = ?", wgID); err != nil {
		middleware.InternalError(c, "Failed to delete workgroup")
		return
	}

	actor := "user:" + strconv.FormatInt(userID, 10)
	audit.Log(h.db, "workgroup.delete", actor, "wg:"+wgID, "", c.ClientIP())

	middleware.Success(c, gin.H{"deleted": true})
}
