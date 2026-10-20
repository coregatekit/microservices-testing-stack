package venue_test

import (
	"errors"
	"testing"

	"github.com/coregatekit/ticketlite/services/catalog/internal/venue"
)

var actor = venue.Actor{
	UserID:      "user-1",
	OrganizerID: "org-1",
}

func TestCreate_EmptyName(t *testing.T) {
	q := &QueriesMock{}

	_, err := venue.NewService(q).Create(t.Context(), actor, venue.CreateInput{
		Name:     "",
		Address:  "a",
		Timezone: "Asia/Bangkok",
	})
	if !errors.Is(err, venue.ErrInvalid) {
		t.Errorf("Create returned err = %v, want ErrInvalid", err)
	}
	if n := len(q.CreateVenueCalls()); n != 0 {
		t.Errorf("CreateVenue was called %d times, want 0", n)
	}
}
