-- name: CreateVenue :one
INSERT INTO venues (organizer_id, name, address, timezone, created_by, updated_by)
VALUES (@organizer_id, @name, @address, @timezone, @actor, @actor)
RETURNING *;

-- name: GetVenue :one
SELECT * FROM venues
WHERE venue_id = @venue_id AND organizer_id = @organizer_id;

-- name: ListVenuesByOrganizer :many
SELECT * FROM venues
WHERE organizer_id = @organizer_id
ORDER BY venue_id;
