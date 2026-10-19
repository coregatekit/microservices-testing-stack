// Package testdb starts a throwaway Postgres for integration testing.
package testdb

import (
	"database/sql"
	"io/fs"
	"testing"

	"github.com/coregatekit/ticketlite/services/catalog/db"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
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

// Migrate applies every migration to the database at dsn.
func Migrate(t testing.TB, dsn string) {
	t.Helper()

	fsys, err := fs.Sub(db.Migrations, "migrations")
	if err != nil {
		t.Fatalf("migrations FS error = %v", err)
	}

	conn, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatalf("sql.Open error: %v", err)
	}
	defer conn.Close()

	provider, err := goose.NewProvider(goose.DialectPostgres, conn, fsys)
	if err != nil {
		t.Fatalf("goose.NewProvider error: %v", err)
	}

	if _, err := provider.Up(t.Context()); err != nil {
		t.Fatalf("migrate error: %v", err)
	}
}
