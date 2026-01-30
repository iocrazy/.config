package history

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// Conversation represents a Claude conversation history record
type Conversation struct {
	ID             int64
	ProjectPath    string
	SessionID      string
	StartedAt      time.Time
	EndedAt        *time.Time
	UserPrompt     string
	AssistantReply string
	TranscriptPath string
}

// DB wraps the SQLite database connection
type DB struct {
	conn *sql.DB
}

// DefaultDBPath returns the default path for the history database
func DefaultDBPath() string {
	return filepath.Join(os.Getenv("HOME"), ".config", "agent-tracker", "data", "history.db")
}

// Open opens or creates the history database
func Open(path string) (*DB, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("create data directory: %w", err)
	}

	conn, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	db := &DB{conn: conn}
	if err := db.init(); err != nil {
		conn.Close()
		return nil, err
	}

	return db, nil
}

// Close closes the database connection
func (db *DB) Close() error {
	return db.conn.Close()
}

func (db *DB) init() error {
	schema := `
	CREATE TABLE IF NOT EXISTS conversations (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		project_path TEXT NOT NULL,
		session_id TEXT,
		started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		ended_at DATETIME,
		user_prompt TEXT,
		assistant_reply TEXT,
		transcript_path TEXT
	);
	CREATE INDEX IF NOT EXISTS idx_project_path ON conversations(project_path);
	CREATE INDEX IF NOT EXISTS idx_started_at ON conversations(started_at);
	`
	_, err := db.conn.Exec(schema)
	if err != nil {
		return fmt.Errorf("create schema: %w", err)
	}
	return nil
}

// CreateConversation creates a new conversation record and returns its ID
func (db *DB) CreateConversation(projectPath, sessionID, userPrompt string) (int64, error) {
	projectPath = normalizePath(projectPath)
	result, err := db.conn.Exec(
		`INSERT INTO conversations (project_path, session_id, user_prompt, started_at) VALUES (?, ?, ?, ?)`,
		projectPath, sessionID, userPrompt, time.Now().UTC(),
	)
	if err != nil {
		return 0, fmt.Errorf("insert conversation: %w", err)
	}
	return result.LastInsertId()
}

// UpdateConversation updates an existing conversation with the reply and transcript
func (db *DB) UpdateConversation(projectPath, assistantReply, transcriptPath string) error {
	projectPath = normalizePath(projectPath)
	now := time.Now().UTC()
	_, err := db.conn.Exec(
		`UPDATE conversations SET assistant_reply = ?, transcript_path = ?, ended_at = ?
		 WHERE id = (SELECT id FROM conversations WHERE project_path = ? ORDER BY started_at DESC LIMIT 1)`,
		assistantReply, transcriptPath, now, projectPath,
	)
	if err != nil {
		return fmt.Errorf("update conversation: %w", err)
	}
	return nil
}

// QueryOptions specifies options for querying conversations
type QueryOptions struct {
	ProjectPath string
	Limit       int
	Offset      int
	Search      string
}

// QueryConversations retrieves conversations matching the query options
func (db *DB) QueryConversations(opts QueryOptions) ([]Conversation, error) {
	projectPath := normalizePath(opts.ProjectPath)
	if opts.Limit <= 0 {
		opts.Limit = 50
	}

	query := `SELECT id, project_path, session_id, started_at, ended_at, user_prompt, assistant_reply, transcript_path
			  FROM conversations WHERE project_path = ?`
	args := []interface{}{projectPath}

	if opts.Search != "" {
		query += ` AND (user_prompt LIKE ? OR assistant_reply LIKE ?)`
		searchPattern := "%" + opts.Search + "%"
		args = append(args, searchPattern, searchPattern)
	}

	query += ` ORDER BY started_at DESC LIMIT ? OFFSET ?`
	args = append(args, opts.Limit, opts.Offset)

	rows, err := db.conn.Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("query conversations: %w", err)
	}
	defer rows.Close()

	var conversations []Conversation
	for rows.Next() {
		var c Conversation
		var startedAt, endedAt sql.NullString
		var sessionID, userPrompt, assistantReply, transcriptPath sql.NullString

		err := rows.Scan(&c.ID, &c.ProjectPath, &sessionID, &startedAt, &endedAt,
			&userPrompt, &assistantReply, &transcriptPath)
		if err != nil {
			return nil, fmt.Errorf("scan conversation: %w", err)
		}

		if sessionID.Valid {
			c.SessionID = sessionID.String
		}
		if userPrompt.Valid {
			c.UserPrompt = userPrompt.String
		}
		if assistantReply.Valid {
			c.AssistantReply = assistantReply.String
		}
		if transcriptPath.Valid {
			c.TranscriptPath = transcriptPath.String
		}
		if startedAt.Valid {
			if t, err := time.Parse("2006-01-02 15:04:05", startedAt.String); err == nil {
				c.StartedAt = t
			} else if t, err := time.Parse(time.RFC3339, startedAt.String); err == nil {
				c.StartedAt = t
			}
		}
		if endedAt.Valid {
			if t, err := time.Parse("2006-01-02 15:04:05", endedAt.String); err == nil {
				c.EndedAt = &t
			} else if t, err := time.Parse(time.RFC3339, endedAt.String); err == nil {
				c.EndedAt = &t
			}
		}

		conversations = append(conversations, c)
	}

	return conversations, rows.Err()
}

// GetLatestSessionID returns the session ID of the most recent conversation for a project
func (db *DB) GetLatestSessionID(projectPath string) (string, error) {
	projectPath = normalizePath(projectPath)
	var sessionID sql.NullString
	err := db.conn.QueryRow(
		`SELECT session_id FROM conversations WHERE project_path = ? AND session_id IS NOT NULL AND session_id != '' ORDER BY started_at DESC LIMIT 1`,
		projectPath,
	).Scan(&sessionID)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("get latest session: %w", err)
	}
	if sessionID.Valid {
		return sessionID.String, nil
	}
	return "", nil
}

func normalizePath(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return path
	}
	// Expand ~ to home directory
	if strings.HasPrefix(path, "~/") {
		path = filepath.Join(os.Getenv("HOME"), path[2:])
	}
	// Clean the path
	path = filepath.Clean(path)
	return path
}
