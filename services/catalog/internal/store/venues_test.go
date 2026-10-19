//go:build integration

package store_test

import (
	"testing"

	"github.com/coregatekit/ticketlite/services/catalog/internal/store"
	"github.com/google/uuid"
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
