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
