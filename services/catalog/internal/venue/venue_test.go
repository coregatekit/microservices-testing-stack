package venue_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/coregatekit/ticketlite/services/catalog/internal/store"
	"github.com/coregatekit/ticketlite/services/catalog/internal/venue"
)

var actor = venue.Actor{
	UserID:      "user-1",
	OrganizerID: "org-1",
}

func TestCreate_Invalid(t *testing.T) {
	tests := []struct {
		name string
		in   venue.CreateInput
	}{
		{"EmptyName", venue.CreateInput{Name: "", Address: "a", Timezone: "Asia/Bangkok"}},
		{"BlankName", venue.CreateInput{Name: "   ", Address: "a", Timezone: "Asia/Bangkok"}},
		{"EmptyAddress", venue.CreateInput{Name: "a", Address: "", Timezone: "Asia/Bangkok"}},
		{"BlankAddress", venue.CreateInput{Name: "a", Address: "   ", Timezone: "Asia/Bangkok"}},
		{"EmptyTimezone", venue.CreateInput{Name: "a", Address: "a", Timezone: ""}},
		{"TimezoneMustNotBeLocal", venue.CreateInput{Name: "a", Address: "a", Timezone: "Local"}},
		{"TimezoneMustReturnErrorWhenInvalid", venue.CreateInput{Name: "a", Address: "a", Timezone: "Mars/Olympus"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			q := &QueriesMock{}
			_, err := venue.NewService(q).Create(t.Context(), actor, tt.in)
			if !errors.Is(err, venue.ErrInvalid) {
				t.Errorf("Create returned err = %v, want ErrInvalid", err)
			}
			if n := len(q.CreateVenueCalls()); n != 0 {
				t.Errorf("CreateVenue was called %d times, want 0", n)
			}
		})
	}
}

func TestCreate_Error(t *testing.T) {
	t.Run("CreateVenueReturnsError", func(t *testing.T) {
		q := &QueriesMock{
			CreateVenueFunc: func(ctx context.Context, arg store.CreateVenueParams) (store.Venue, error) {
				return store.Venue{}, errors.New("some error")
			},
		}
		in := venue.CreateInput{
			Name:     "Impact Arena",
			Address:  "99 Muang Thong Thani, Nonthaburi",
			Timezone: "Asia/Bangkok",
		}
		_, err := venue.NewService(q).Create(t.Context(), actor, in)
		if err == nil || errors.Is(err, venue.ErrInvalid) {
			t.Fatalf("Create returned err = nil or ErrInvalid, want non-nil and not ErrInvalid")
		}
	})
}

func TestCreate_Success(t *testing.T) {
	t.Run("ValidInput", func(t *testing.T) {
		q := &QueriesMock{
			CreateVenueFunc: func(ctx context.Context, arg store.CreateVenueParams) (store.Venue, error) {
				return store.Venue{}, nil
			},
		}
		in := venue.CreateInput{
			Name:     "  Impact Arena ",
			Address:  "  99 Muang Thong Thani, Nonthaburi   ",
			Timezone: "             Asia/Bangkok         ",
		}

		if _, err := venue.NewService(q).Create(t.Context(), actor, in); err != nil {
			t.Fatalf("Create returned err = %v, want nil", err)
		}

		calls := q.CreateVenueCalls()
		if len(calls) != 1 {
			t.Fatalf("CreateVenue was called %d times, want 1", len(calls))
		}

		want := store.CreateVenueParams{
			OrganizerID: actor.OrganizerID,
			Name:        "Impact Arena",
			Address:     "99 Muang Thong Thani, Nonthaburi",
			Timezone:    "Asia/Bangkok",
			Actor:       actor.UserID,
		}
		if got := calls[0].Arg; got != want {
			t.Errorf("CreateVenue arg = %+v, want %+v", got, want)
		}
	})

	t.Run("ReturnsVenueOnSuccess", func(t *testing.T) {
		venueID, _ := uuid.NewV7()
		in := venue.CreateInput{
			Name:     "  Impact Arena ",
			Address:  "  99 Muang Thong Thani, Nonthaburi   ",
			Timezone: "             Asia/Bangkok         ",
		}
		row := store.Venue{
			VenueID:     venueID,
			OrganizerID: "org-from-db",
			Name:        "Inserted Name",
			Address:     "Inserted Address",
			Timezone:    "Asia/Tokyo",
			CreatedAt:   time.Date(2026, 10, 26, 10, 0, 0, 0, time.UTC),
			CreatedBy:   "creator-from-db",
			UpdatedAt:   time.Date(2026, 10, 26, 10, 0, 0, 0, time.UTC),
			UpdatedBy:   "updater-from-db",
		}
		q := &QueriesMock{
			CreateVenueFunc: func(ctx context.Context, arg store.CreateVenueParams) (store.Venue, error) {
				return row, nil
			},
		}

		got, err := venue.NewService(q).Create(t.Context(), actor, in)
		if err != nil {
			t.Fatalf("Create returned err = %v, want nil", err)
		}

		if got.ID == uuid.Nil || got.ID != row.VenueID {
			t.Errorf("Create returned ID = %v, want %v", got.ID, row.VenueID)
		}
		if got.OrganizerID != row.OrganizerID {
			t.Errorf("Create returned OrganizerID = %v, want %v", got.OrganizerID, row.OrganizerID)
		}
		if got.Name != row.Name {
			t.Errorf("Create returned Name = %v, want %v", got.Name, row.Name)
		}
		if got.Address != row.Address {
			t.Errorf("Create returned Address = %v, want %v", got.Address, row.Address)
		}
		if got.Timezone != row.Timezone {
			t.Errorf("Create returned Timezone = %v, want %v", got.Timezone, row.Timezone)
		}

		if got.CreatedAt != row.CreatedAt {
			t.Errorf("Create returned CreatedAt = %v, want %v", got.CreatedAt, row.CreatedAt)
		}
		if got.CreatedBy != row.CreatedBy {
			t.Errorf("Create returned CreatedBy = %v, want %v", got.CreatedBy, row.CreatedBy)
		}
		if got.UpdatedAt != row.UpdatedAt {
			t.Errorf("Create returned UpdatedAt = %v, want %v", got.UpdatedAt, row.UpdatedAt)
		}
		if got.UpdatedBy != row.UpdatedBy {
			t.Errorf("Create returned UpdatedBy = %v, want %v", got.UpdatedBy, row.UpdatedBy)
		}
	})
}
