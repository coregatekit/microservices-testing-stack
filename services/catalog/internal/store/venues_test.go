//go:build integration

package store_test

import (
	"errors"
	"testing"

	"github.com/coregatekit/ticketlite/services/catalog/internal/store"
	"github.com/coregatekit/ticketlite/services/catalog/internal/testdb"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// newOrganizerID generates a new unique organizer ID for testing purposes.
func newOrganizerID() string {
	return "org-" + uuid.NewString()
}

// createVenue is a helper function to create a venue for testing purposes. It fails the test if venue creation encounters an error.
func createVenue(t *testing.T, q *store.Queries, organizerID, name string) store.Venue {
	t.Helper()

	venue, err := q.CreateVenue(t.Context(), store.CreateVenueParams{
		OrganizerID: organizerID,
		Name:        name,
		Address:     "1 Test Road",
		Timezone:    "Asia/Bangkok",
		Actor:       "user-1",
	})
	if err != nil {
		t.Fatalf("q.CreateVenue error: %v", err)
	}

	return venue
}

func TestVenueQueries(t *testing.T) {
	pool := testdb.NewPool(t)
	q := store.New(pool)

	t.Run("CreateThenGet", func(t *testing.T) {
		org := newOrganizerID()
		created := createVenue(t, q, org, "Hall A")

		if created.VenueID == uuid.Nil {
			t.Error("VenueID is empty, want DB default uuidv7")
		}
		if created.CreatedBy != "user-1" || created.UpdatedBy != "user-1" {
			t.Errorf("CreatedBy/UpdatedBy = %q/%q, want user-1/user-1", created.CreatedBy, created.UpdatedBy)
		}
		if created.CreatedAt.IsZero() || !created.CreatedAt.Equal(created.UpdatedAt) {
			t.Errorf("CreatedAt = %v, UpdatedAt = %v, want same non-zero time", created.CreatedAt, created.UpdatedAt)
		}

		got, err := q.GetVenue(t.Context(), store.GetVenueParams{
			VenueID:     created.VenueID,
			OrganizerID: org,
		})
		if err != nil {
			t.Fatalf("GetVenue: %v", err)
		}
		if got != created {
			t.Errorf("GetVenue = %+v, want %+v", got, created)
		}
	})

	t.Run("GetFromOtherOrganizer", func(t *testing.T) {
		created := createVenue(t, q, newOrganizerID(), "Hall B")

		_, err := q.GetVenue(t.Context(), store.GetVenueParams{
			VenueID:     created.VenueID,
			OrganizerID: newOrganizerID(),
		})

		if !errors.Is(err, pgx.ErrNoRows) {
			t.Fatalf("GetVenue with other organizer: err = %v, want pgx.ErrNoRows", err)
		}
	})

	t.Run("ListByOrganizer", func(t *testing.T) {
		org := newOrganizerID()
		first := createVenue(t, q, org, "First")
		second := createVenue(t, q, org, "Second")
		_ = createVenue(t, q, newOrganizerID(), "Other Organizer Venue")

		got, err := q.ListVenuesByOrganizer(t.Context(), org)
		if err != nil {
			t.Fatalf("ListVenuesByOrganizer: %v", err)
		}
		if len(got) != 2 {
			t.Errorf("ListVenuesByOrganizer = %d venues, want 2", len(got))
		}
		if got[0].VenueID != first.VenueID {
			t.Errorf("ListVenuesByOrganizer[0] = %+v, want %+v", got[0], first)
		}
		if got[1].VenueID != second.VenueID {
			t.Errorf("ListVenuesByOrganizer[1] = %+v, want %+v", got[1], second)
		}
	})
}
