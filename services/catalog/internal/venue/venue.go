package venue

import (
	"errors"
	"time"
	"uuid"
)

var (
	ErrNotFound = errors.New("venue not found")
	ErrInvalid  = errors.New("invalid venue")
)

type Venue struct {
	ID          uuid.UUID
	OrganizerID string
	Name        string
	Address     string
	Timezone    string
	CreatedAt   time.Time
	CreatedBy   string
	UpdatedAt   time.Time
	UpdatedBy   string
}

type Actor struct {
	UserID      string
	OrganizerID string
}

type CreateInput struct {
	Name     string
	Address  string
	Timezone string
}
