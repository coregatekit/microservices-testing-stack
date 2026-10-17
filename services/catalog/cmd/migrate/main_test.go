package main

import (
	"database/sql"
	"io/fs"
	"strings"
	"testing"

	"github.com/pressly/goose/v3"
)

// TestRun_RejectsBadInput verifies that the run function correctly rejects invalid input.
func TestRun_RejectsBadInput(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		dsn     string
		wantErr string
	}{
		{name: "unknown command", args: []string{"down"}, dsn: "postgres://x", wantErr: "unknown command"},
		{name: "missing dsn with default command", args: nil, dsn: "", wantErr: "MIGRATOR_DATABASE_URL is not set"},
		{name: "missing dsn with status", args: []string{"status"}, dsn: "", wantErr: "MIGRATOR_DATABASE_URL is not set"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("MIGRATOR_DATABASE_URL", tc.dsn)

			err := run(t.Context(), tc.args)
			if err == nil {
				t.Fatalf("run(%q) = nil, want error containing %q", tc.args, tc.wantErr)
			}
			if !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("run(%q) error = %q, want it to contain %q", tc.args, err, tc.wantErr)
			}
		})
	}
}

// TestMigrationFS_HasSQLFiles verifies that the embedded migration filesystem contains .sql files.
func TestMigrationFS_HasSQLFiles(t *testing.T) {
	fsys, err := migrationsFS()
	if err != nil {
		t.Fatalf("migrationsFS() error = %v", err)
	}

	files, err := fs.Glob(fsys, "*.sql")
	if err != nil {
		t.Fatalf("fs.Glob() error = %v", err)
	}
	if len(files) == 0 {
		t.Fatalf("no .sql files embedded; check the //go:embed pattern in db/migrations.go")
	}
}

// TestMigrationFS_VersionsAreSequential verifies that the migration versions in the embedded filesystem are sequential without gaps.
func TestMigrationFS_VersionsAreSequential(t *testing.T) {
	fsys, err := migrationsFS()
	if err != nil {
		t.Fatalf("migrationsFS() error = %v", err)
	}

	conn, err := sql.Open("pgx", "postgres://unused")
	if err != nil {
		t.Fatalf("sql.Open error = %v", err)
	}
	t.Cleanup(func() { conn.Close() })

	provider, err := goose.NewProvider(goose.DialectPostgres, conn, fsys)
	if err != nil {
		t.Fatalf("goose.NewProvider error = %v", err)
	}

	for i, src := range provider.ListSources() {
		want := int64(i + 1)
		if src.Version != want {
			t.Fatalf("migrations %s has version %d, want %d (gap or duplicate?)", src.Path, src.Version, want)
		}
	}
}
