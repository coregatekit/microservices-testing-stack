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
