package venue_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/go-cmp/cmp"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

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
		dbErr := errors.New("connection refused")
		q := &QueriesMock{
			CreateVenueFunc: func(ctx context.Context, arg store.CreateVenueParams) (store.Venue, error) {
				return store.Venue{}, dbErr
			},
		}
		in := venue.CreateInput{
			Name:     "Impact Arena",
			Address:  "99 Muang Thong Thani, Nonthaburi",
			Timezone: "Asia/Bangkok",
		}
		_, err := venue.NewService(q).Create(t.Context(), actor, in)
		if !errors.Is(err, dbErr) {
			t.Fatalf("Create returned err = %v, want it to wrap %v", err, dbErr)
		}
		if errors.Is(err, venue.ErrInvalid) {
			t.Errorf("Create returned err = %v, must not be ErrInvalid", err)
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

		assertVenueMatchesRow(t, got, row)
	})
}

func TestGet_Success(t *testing.T) {
	t.Run("PassesIDAndOrganizer", func(t *testing.T) {
		q := &QueriesMock{
			GetVenueFunc: func(ctx context.Context, arg store.GetVenueParams) (store.Venue, error) {
				return store.Venue{}, nil
			},
		}
		svc := venue.NewService(q)
		id := uuid.MustParse("01a1a570-3a28-76ed-991f-795348c97806")

		_, err := svc.Get(t.Context(), actor, id)
		if err != nil {
			t.Fatalf("Get returned err = %v, want nil", err)
		}

		calls := q.GetVenueCalls()
		if len(calls) != 1 {
			t.Fatalf("GetVenue was called %d times, want 1", len(calls))
		}
		want := store.GetVenueParams{
			VenueID:     id,
			OrganizerID: actor.OrganizerID,
		}
		if got := calls[0].Arg; got != want {
			t.Errorf("GetVenue arg = %+v, want %+v", got, want)
		}
	})

	t.Run("ReturnsVenueOnSuccess", func(t *testing.T) {
		row := store.Venue{
			VenueID:     uuid.MustParse("01a1a570-3a28-76ed-991f-795348c97806"),
			OrganizerID: "org-from-db",
			Name:        "Stored Name",
			Address:     "Stored Address",
			Timezone:    "Asia/Tokyo",
			CreatedAt:   time.Date(2026, 10, 26, 10, 0, 0, 0, time.UTC),
			CreatedBy:   "creator-from-db",
			UpdatedAt:   time.Date(2026, 10, 26, 11, 0, 0, 0, time.UTC),
			UpdatedBy:   "updater-from-db",
		}
		q := &QueriesMock{
			GetVenueFunc: func(ctx context.Context, arg store.GetVenueParams) (store.Venue, error) {
				return row, nil
			},
		}

		svc := venue.NewService(q)
		got, err := svc.Get(t.Context(), actor, row.VenueID)
		if err != nil {
			t.Fatalf("Get returned err = %v, want nil", err)
		}

		assertVenueMatchesRow(t, got, row)
	})
}

func TestGet_NotFound(t *testing.T) {
	q := &QueriesMock{
		GetVenueFunc: func(ctx context.Context, arg store.GetVenueParams) (store.Venue, error) {
			return store.Venue{}, pgx.ErrNoRows
		},
	}

	svc := venue.NewService(q)
	_, err := svc.Get(t.Context(), actor, uuid.MustParse("01a1a570-3a28-76ed-991f-795348c97806"))
	if !errors.Is(err, venue.ErrNotFound) {
		t.Errorf("Get returned err = %v, want %v", err, venue.ErrNotFound)
	}
}

func TestGet_Error(t *testing.T) {
	dbErr := errors.New("connection refused")
	q := &QueriesMock{
		GetVenueFunc: func(ctx context.Context, arg store.GetVenueParams) (store.Venue, error) {
			return store.Venue{}, dbErr
		},
	}

	svc := venue.NewService(q)
	_, err := svc.Get(t.Context(), actor, uuid.MustParse("01a1a570-3a28-76ed-991f-795348c97806"))
	if !errors.Is(err, dbErr) {
		t.Fatalf("Get returned err = %v, want it to wrap %v", err, dbErr)
	}
	if errors.Is(err, venue.ErrNotFound) {
		t.Errorf("Get returned err = %v, must not be ErrNotFound", err)
	}
}

func TestList_Success(t *testing.T) {
	t.Run("PassesOrganizer", func(t *testing.T) {
		q := &QueriesMock{
			ListVenuesByOrganizerFunc: func(ctx context.Context, organizerID string) ([]store.Venue, error) {
				return nil, nil
			},
		}

		svc := venue.NewService(q)
		_, err := svc.List(t.Context(), actor)
		if err != nil {
			t.Fatalf("List returned err = %v, want nil", err)
		}

		calls := q.ListVenuesByOrganizerCalls()
		if len(calls) != 1 {
			t.Fatalf("ListVenuesByOrganizer was called %d times, want 1", len(calls))
		}
		if calls[0].OrganizerID != actor.OrganizerID {
			t.Errorf("ListVenuesByOrganizer was called with OrganizerID = %v, want %v", calls[0].OrganizerID, actor.OrganizerID)
		}
	})
}

func assertVenueMatchesRow(t *testing.T, got venue.Venue, row store.Venue) {
	t.Helper()

	want := venue.Venue{
		ID:          row.VenueID,
		OrganizerID: row.OrganizerID,
		Name:        row.Name,
		Address:     row.Address,
		Timezone:    row.Timezone,
		CreatedAt:   row.CreatedAt,
		CreatedBy:   row.CreatedBy,
		UpdatedAt:   row.UpdatedAt,
		UpdatedBy:   row.UpdatedBy,
	}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("Venue mismatch (-want +got):\n%s", diff)
	}
}
