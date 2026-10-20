package venue

import (
	"context"
	"errors"
	"time"
	"uuid"

	"github.com/coregatekit/ticketlite/services/catalog/internal/store"
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

type Queries interface {
	CreateVenue(ctx context.Context, arg store.CreateVenueParams) (store.Venue, error)
	GetVenue(ctx context.Context, arg store.GetVenueParams) (store.Venue, error)
	ListVenuesByOrganizer(ctx context.Context, organizerID string) ([]store.Venue, error)
}
