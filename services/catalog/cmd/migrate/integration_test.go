//go:build integration

package main

import (
	"testing"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
)

// startPostgres is a helper function to start a PostgreSQL instance for integration tests.
func startPostgres(t *testing.T) string {
	t.Helper()

	ctr, err := postgres.Run(t.Context(), "postgres:18.6", postgres.WithDatabase("catalog"), postgres.BasicWaitStrategies())
	testcontainers.CleanupContainer(t, ctr)
	if err != nil {
		t.Fatalf("start postgres: %v", err)
	}

	dsn, err := ctr.ConnectionString(t.Context(), "sslmode=disable")
	if err != nil {
		t.Fatalf("connection string: %v", err)
	}

	return dsn
}

// TestRun_Integration tests the migration commands against a real PostgreSQL instance.
func TestRun_Integration(t *testing.T) {
	dsn := startPostgres(t)
	t.Setenv("MIGRATOR_DATABASE_URL", dsn)

	for _, args := range [][]string{
		{"status"},
		{"up"},
		{"up"},
		{"status"},
	} {
		if err := run(t.Context(), args); err != nil {
			t.Fatalf("run(%q) error = %v", args, err)
		}
	}

	provider := newTestProvider(t, dsn)
	got, err := provider.GetDBVersion(t.Context())
	if err != nil {
		t.Fatalf("GetDBVersion: %v", err)
	}
	sources := provider.ListSources()
	want := sources[len(sources)-1].Version
	if got != want {
		t.Fatalf("db version = %d, want %d", got, want)
	}
}

// TestMigrations_DownAndUpAgain tests that migrations can be applied, rolled back to version 0, and then applied again successfully.
func TestMigrations_DownAndUpAgain(t *testing.T) {
	dsn := startPostgres(t)
	provider := newTestProvider(t, dsn)
	ctx := t.Context()

	if _, err := provider.Up(ctx); err != nil {
		t.Fatalf("first up: %v", err)
	}
	if _, err := provider.DownTo(ctx, 0); err != nil {
		t.Fatalf("down to 0: %v", err)
	}
	if _, err := provider.Up(ctx); err != nil {
		t.Fatalf("up after down: %v", err)
	}
}
