-- +goose Up
CREATE TABLE
    venues (
        venue_id uuid PRIMARY KEY DEFAULT uuidv7 (),
        organizer_id text NOT NULL,
        name text NOT NULL,
        address text NOT NULL,
        timezone text NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now (),
        created_by text NOT NULL,
        updated_at timestamptz NOT NULL DEFAULT now (),
        updated_by text NOT NULL
    );

CREATE INDEX venues_organizer_id_idx ON venues (organizer_id);

CREATE TRIGGER venues_set_updated_at BEFORE
UPDATE ON venues FOR EACH ROW EXECUTE FUNCTION set_updated_at ();

-- +goose Down
DROP TABLE venues;