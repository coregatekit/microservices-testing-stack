package testdb

import (
	"testing"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
)

// StartPostgres starts an empty Postgres container and returns its DSN.
func StartPostgres(t testing.TB) string {
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
