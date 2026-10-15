package main

import (
	"io/fs"
	"strings"
	"testing"
)

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
